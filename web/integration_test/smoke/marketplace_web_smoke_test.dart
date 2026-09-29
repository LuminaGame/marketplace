// The marketplace web front end in real Chrome on GPU 1, against a real
// backend (temp SQLite DB + storage, seeded with the CC0 samples) that serves
// the release web build, the way production runs it.
//
// It is a plain Dart test (puppeteer drives Chrome from the VM), so run it
// with `dart test`, under the shared test lock and with the GPU-1 environment:
//
//   CUDA_VISIBLE_DEVICES=1 FILAMENT_GPU='RTX PRO 2000' __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only DRI_PRIME=1 \
//     flock -w 7000 /tmp/lumina_tests.lock dart test integration_test/smoke/marketplace_web_smoke_test.dart
//
// On Windows (no flock, no PRIME variables):
//
//   $env:CUDA_VISIBLE_DEVICES='1'; $env:FILAMENT_GPU='RTX PRO 2000'
//   dart test integration_test/smoke/marketplace_web_smoke_test.dart
//
// Evidence, written with lumina_smoke: build/smoke_artifacts/ holds a PNG per
// page (`<scenario>: <page>`) and a VP8/WebM per scenario named after it
// (≥ 10 s, 1440×900, 30 fps; GStreamer, else ffmpeg), each with a sidecar
// JSON naming its scenario; build/smoke_report.html links them. A run of some
// scenarios merges into the report of the earlier runs
// (build/smoke_report.events.jsonl).
//
// A second scenario covers the listing page's 3D view: the Lumina web
// runtime renders the Banana Bunch preview model in the same Chrome. Run it
// alone with `--plain-name 'listing 3D view'` (MKT_SKIP_WEB_BUILD=1 reuses an
// existing build). It is skipped when flutter_filament's WebAssembly module
// is not built (see tool/sync_filament_module.dart); the others run without it.
//
// The game template publish flow: a template without
// contents/ is refused at the Upload step with the server's invalid_template
// message, then the real Lumina project in the server's fixtures publishes
// (`--plain-name 'game template'`).
//
// The plugin publish flow: Plugin asks for the package first; a
// non-free variant is refused, then the whole lumina_plugin_pcg folder zip
// (with .git/, build/, .dart_tool/, left out) is read from its .lmplugin
// (`--plain-name 'plugin publish'`).
@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:lumina_smoke/lumina_smoke.dart' show SmokeArtifacts, SmokeVideoRecorder;
import 'package:lumina_smoke/report.dart'
    show
        SmokeReportConfig,
        SmokeReportGenerator,
        SmokeReportPaths,
        TestCategories,
        readSmokeEvents,
        runOf,
        smokeEventsKeptOnMerge,
        smokeRunKey;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

/// This repository's root (the smoke runs in `web/`).
final _repo = Directory.current.parent.path;

/// The shared test assets: `LUMINA_TEST_ASSETS`, else the repository's `test-assets/`.
final _testAssets = Platform.environment['LUMINA_TEST_ASSETS'] ?? '$_repo/test-assets';

/// lumina_plugin_pcg in the plugins checkout (LuminaGame/plugins):
/// `LUMINA_PLUGINS_DIR`, else `../plugins` next to this repository.
final _pcgDir =
    '${Platform.environment['LUMINA_PLUGINS_DIR'] ?? '${Directory(_repo).parent.path}/plugins'}/lumina_plugin_pcg';
const _chromeCandidates = [
  '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/snap/bin/chromium', //
  r'C:\Program Files\Google\Chrome\Application\chrome.exe',
  r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
];
const _pluginTestName = 'plugin publish flow from the .lmplugin manifest in Chrome';
const _gpuEnv = {
  'CUDA_VISIBLE_DEVICES': '1',
  'FILAMENT_GPU': 'RTX PRO 2000',
  '__NV_PRIME_RENDER_OFFLOAD': '1',
  '__VK_LAYER_NV_optimus': 'NVIDIA_only',
  'DRI_PRIME': '1',
};
const _width = 1440;
const _height = 900;
const _testName = 'marketplace web front end in Chrome';
const _viewerTestName = 'listing 3D view rendered with Lumina in Chrome';
const _templateTestName = 'game template publish flow in Chrome';
const _templateFixture = '../server/test/fixtures/game_template/Arena';

final _webDir = Directory(Platform.environment['MKT_WEB_DIR'] ?? 'build/web');
const _suitePath = 'integration_test/smoke/marketplace_web_smoke_test.dart';

void main() {
  late MarketplaceServer server;
  late Directory tmp;
  late Browser browser;
  late Page page;
  // What setUpAll started, closed in reverse by tearDownAll.
  final cleanups = <FutureOr<void> Function()>[];
  final errors = <String>[];
  final frames = <(int, Uint8List)>[];
  final clock = Stopwatch();
  StreamSubscription<dynamic>? screencast;
  var gpuRenderer = 'unknown';
  // Why the 3D view cannot run (flutter_filament's wasm module is not built).
  String? moduleMissing;

  setUpAll(() => _recorded('marketplace web smoke (setUpAll)', () async {
    // flutter_filament's wasm module ships in the build under filament/.
    final sync = await Process.run('dart', ['run', 'tool/sync_filament_module.dart'], runInShell: true);
    if (sync.exitCode != 0) moduleMissing = 'tool/sync_filament_module.dart: ${sync.stdout}${sync.stderr}'.trim();
    if (Platform.environment['MKT_SKIP_WEB_BUILD'] != '1' ||
        !File('${_webDir.path}/index.html').existsSync() ||
        (moduleMissing == null && !File('${_webDir.path}/filament/flutter_filament.wasm').existsSync())) {
      final build = await Process.run('flutter', ['build', 'web', '--release', '--no-web-resources-cdn'],
          runInShell: true, environment: _gpuEnv);
      if (build.exitCode != 0) fail('flutter build web failed:\n${build.stdout}\n${build.stderr}');
    }
    tmp = Directory.systemTemp.createTempSync('mkt_web_smoke_');
    cleanups.add(() => tmp.deleteSync(recursive: true));
    server = await MarketplaceServer.start(
      MarketplaceConfig(
        port: 0,
        databasePath: '${tmp.path}/marketplace.db',
        storageDir: '${tmp.path}/storage',
        jwtSecret: 'web-smoke-secret-that-is-at-least-32-chars',
        webDir: _webDir.path,
      ),
      log: MarketplaceLog.silent(),
    );
    cleanups.add(server.close);
    await seedSampleContent(server.services,
        testAssetsDir: _testAssets, adminPassword: 'smoke-admin-password', moderatorPassword: 'smoke-moderator-password');
    // A reported listing for the moderation page.
    final reporter = MarketplaceClient(baseUrl: server.url);
    await reporter.signUp(email: 'reporter@example.test', username: 'reporter', password: 'reporter password');
    final chair = await reporter.listing('chair');
    await reporter.report(chair.id, ReportReason.broken, details: 'The mount variant has no mount point.');
    reporter.close();

    final chrome = _chromeCandidates.where((p) => File(p).existsSync()).first;
    browser = await puppeteer.launch(
      executablePath: chrome,
      headless: true,
      environment: {...Platform.environment, ..._gpuEnv},
      args: ['--ignore-gpu-blocklist', '--enable-gpu-rasterization', '--use-angle=vulkan', '--enable-features=Vulkan', '--no-sandbox'],
    );
    cleanups.add(browser.close);
    page = await browser.newPage();
    // Upload bodies stay out of the DevTools request events: a 50 MB zip
    // would otherwise arrive in this isolate as one JSON message and stall it
    // (and the screencast) while it is decoded.
    await page.devTools.network.enable(maxPostDataSize: 64 * 1024);
    page.onError.listen((e) {
      final frames = e.details?.stackTrace?.callFrames.take(6).map((f) => '${f.functionName}@${f.url.split('/').last}:${f.lineNumber}').join(' < ');
      errors.add('pageerror at ${page.url}: ${e.message} [${frames ?? ''}] ${e.details?.exception?.description ?? ''}');
    });
    page.onConsole.listen((m) {
      // A 401 is the answer to the start-up session restore when nobody is
      // signed in (no refresh cookie yet), not an error.
      if (m.type == ConsoleMessageType.error && !m.text!.contains('favicon') && !m.text!.contains('401')) {
        errors.add('console: ${m.text}');
      }
    });
    await page.setViewport(DeviceViewport(width: _width, height: _height));
    clock.start();
    screencast = page.devTools.page.onScreencastFrame.listen((e) {
      frames.add((clock.elapsedMilliseconds, base64Decode(e.data)));
      page.devTools.page.screencastFrameAck(e.sessionId);
    });
    gpuRenderer = await _webglRenderer(page);
  }));

  tearDownAll(() async {
    try {
      await screencast?.cancel();
      for (final cleanup in cleanups.reversed) {
        await cleanup();
      }
    } finally {
      _writeReport();
    }
  });

  Future<void> startRecording() async {
    frames.clear();
    await page.devTools.page.startScreencast(format: 'png', everyNthFrame: 1, maxWidth: _width, maxHeight: _height);
  }

  /// The semantics node (Flutter web's accessible DOM) whose text or label
  /// contains [text].
  Future<ElementHandle> node(String text,
      {String role = '*', bool exact = false, Duration timeout = const Duration(seconds: 30)}) async {
    final match = exact
        ? '(@aria-label="$text" or normalize-space(.)="$text")'
        : '(contains(@aria-label, "$text") or contains(normalize-space(.), "$text"))';
    final xpath = role == 'input'
        ? '//input[contains(@aria-label, "$text")] | //textarea[contains(@aria-label, "$text")]'
        : '//flt-semantics[${role == '*' ? '' : '@role="$role" and '}$match]';
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final found = await page.$x(xpath);
      if (found.isNotEmpty) {
        // The innermost match is the widget itself, not an ancestor.
        return found.last;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('no semantics node for "$text" (role $role)');
  }

  Future<void> click(String text, {String role = 'button', bool exact = false}) async {
    final n = await node(text, role: role, exact: exact);
    await n.click();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  Future<void> type(String label, String value) async {
    final n = await node(label, role: 'input');
    await n.click();
    // Flutter moves focus to its own editing element on the click; let it.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Text goes in as input events (CDP insertText) rather than synthetic key
    // presses: Flutter's web KeyboardConverter throws on CDP-synthesised key
    // events that lack a physical `code` (an engine quirk, not an app bug).
    for (final chunk in RegExp(r'.{1,4}', dotAll: true).allMatches(value)) {
      await page.keyboard.sendCharacter(chunk[0]!);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  /// On failure: a screenshot of [test] and, beside it, the semantics tree.
  Future<void> dumpFailure(String test) async {
    final png = SmokeArtifacts.saveScreenshot('$test: failure', Uint8List.fromList(await page.screenshot()),
        metrics: {'url': page.url, 'gpuRenderer': gpuRenderer});
    final dump = await page.evaluate<String>(r'''() => Array.from(document.querySelectorAll('flt-semantics, input, textarea'))
        .map(e => e.tagName + ' ' + (e.getAttribute('role') || '') + ' [' + (e.getAttribute('aria-label') || '') + '] ' + (e.innerText || '').slice(0, 80).replace(/\n/g, ' ')).join('\n')''');
    File(png.path.replaceAll(RegExp(r'\.png$'), '_semantics.txt')).writeAsStringSync(dump);
  }

  /// Lets the page settle while the pointer visits its buttons and links in
  /// turn (real hover events: each one highlights under it, so the recording
  /// shows the page rather than one still frame), then parks the pointer in
  /// the bottom-left corner, clear of the content.
  Future<void> hoverAcross() async {
    final targets = await page.evaluate<List<dynamic>>(r'''() => Array.from(
        document.querySelectorAll('flt-semantics[role="button"], flt-semantics[role="link"]'))
      .map(e => e.getBoundingClientRect())
      .filter(r => r.width > 4 && r.height > 4 && r.top >= 0 && r.bottom <= window.innerHeight)
      .map(r => [r.left + r.width / 2, r.top + r.height / 2])''');
    final points = [for (final t in targets.cast<List<dynamic>>()) Point((t[0] as num).toDouble(), (t[1] as num).toDouble())];
    // At most six short stops spread over the page's controls: a settle
    // time, not a still one.
    final step = points.length <= 6 ? 1 : points.length / 6;
    for (var i = 0.0; i < points.length && i < 6 * step; i += step) {
      await page.mouse.move(points[i.floor()], steps: 2);
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
    await page.mouse.move(Point(4, _height - 4), steps: 2);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  /// Saves the page as the PNG `<test>: <name>` (its sidecar names [test]'s
  /// scenario) and checks it is not blank.
  Future<img.Image> shot(String name,
      {String test = _testName,
      List<String>? usedAssets,
      Map<String, Object?> extra = const {}}) async {
    await hoverAcross();
    final png = Uint8List.fromList(await page.screenshot());
    SmokeArtifacts.saveScreenshot('$test: $name', png,
        usedAssets: usedAssets ?? ['$_testAssets/Props/Barrels', '$_testAssets/Props/Candles'],
        metrics: {'url': page.url, 'gpuRenderer': gpuRenderer, ...extra});
    final decoded = img.decodePng(png)!;
    expect(decoded.width, _width);
    // Not a blank frame: a share of the page is painted above the background.
    var painted = 0;
    var samples = 0;
    for (var y = 0; y < decoded.height; y += 9) {
      for (var x = 0; x < decoded.width; x += 9) {
        final p = decoded.getPixel(x, y);
        samples++;
        if (p.r + p.g + p.b > 60) painted++;
      }
    }
    expect(painted / samples, greaterThan(0.01), reason: '$name looks blank');
    return decoded;
  }

  _scenario(_testName, () async {
    await startRecording();
    try {
      final base = server.url.toString().replaceAll(RegExp(r'/$'), '');

      // Home.
      await page.goto('$base/', wait: Until.networkIdle);
      await node('FEATURED');
      await node('Open Barrel');
      await shot('home');

      // Search: "barrel" in Models.
      await page.goto('$base/search?q=barrel&category=model', wait: Until.networkIdle);
      await node('2 results');
      await shot('search_results');

      // Listing page.
      await page.goto('$base/listings/barrel', wait: Until.networkIdle);
      await node('Eight steel drums');
      await shot('listing_page');

      // Sign up through the UI.
      await page.goto('$base/signup', wait: Until.networkIdle);
      await type('Email', 'smoke.maker@example.test');
      await type('Username', 'smoke_maker');
      await type('Display name', 'Smoke Maker');
      await type('Password', 'smoke maker password');
      await click('Create account', exact: true);
      await node('My listings');

      // Publish flow: details → screenshots → upload → licenses → attestation.
      final zip = File('${tmp.path}/candles.zip');
      final archive = Archive();
      for (final f in Directory('$_testAssets/Props/Candles').listSync().whereType<File>().where((f) => f.path.endsWith('.glb'))) {
        archive.addFile(ArchiveFile.bytes(f.uri.pathSegments.last, f.readAsBytesSync()));
      }
      zip.writeAsBytesSync(ZipEncoder().encode(archive));

      // A full page load: the session comes back from the httpOnly refresh cookie.
      await page.goto('$base/publish', wait: Until.networkIdle);
      await node('Publish to the marketplace');
      await click('Pick a category');
      await click('Model', exact: true);
      await type('Title', 'Candle Collection');
      await type('Description', '# Candles\n\nWax candles from test-assets, published by the browser smoke.');
      await type('Tags', 'candle, light, prop');
      await shot('publish_details');
      await click('Create listing');
      await node('Add screenshot');
      await click('Continue', exact: true);
      await node('Choose .zip');
      final chooser = page.waitForFileChooser();
      await click('Choose .zip');
      await (await chooser).accept([zip]);
      await node('candles.zip');
      await click('Continue', exact: true);
      await click('Pick a content license');
      await click('CC0-1.0');
      await shot('publish_licenses');
      await click('Continue', exact: true);
      await node('I own this work');
      await click('I own this work', role: '*');
      await shot('publish_attestation');
      await click('Publish', exact: true);
      await node('is live');
      await shot('publish_done');

      // Library: Get (Free) on another listing.
      await page.goto('$base/listings/banana-bunch', wait: Until.networkIdle);
      await click('Get (Free)', exact: true);
      await node('In your library');
      await page.goto('$base/my/library', wait: Until.networkIdle);
      await node('Banana Bunch');
      await shot('library');

      // Moderation, as the seed moderator.
      await page.evaluate<void>('''() => fetch('/api/v1/auth/logout', {method: 'POST', credentials: 'include'})''');
      await page.goto('$base/login', wait: Until.networkIdle);
      await type('Email or username', 'moderator');
      await type('Password', 'smoke-moderator-password');
      await click('Log in', exact: true);
      await node('Moderation');
      await page.goto('$base/moderation', wait: Until.networkIdle);
      await node('Chair');
      await shot('moderation');

      await page.devTools.page.stopScreencast();
      _saveVideo(frames, test: _testName, usedAssets: ['$_testAssets/Props/Barrels', '$_testAssets/Props/Candles']);

      final published = await MarketplaceClient(baseUrl: server.url).search(const SearchQuery(q: 'candle'));
      expect(published.items.map((l) => l.title), contains('Candle Collection'));
      expect(errors, isEmpty, reason: errors.join('\n'));
    } catch (_) {
      await dumpFailure(_testName);
      rethrow;
    }
  });

  // The listing page's 3D view, rendered by the Lumina web runtime.
  _scenario(_viewerTestName, () async {
    if (moduleMissing != null) {
      _skip(_viewerTestName, "flutter_filament's WebAssembly module is not built: $moduleMissing");
      return;
    }
    final assets = ['$_testAssets/Props/Banana Bunch/banana_bunch_short.glb'];
    final requested = <String>[];
    final types = <String, String>{};
    final requests = page.onRequest.listen((r) => requested.add(r.url));
    final responses = page.onResponse.listen((r) => types[r.url] = r.headers['content-type'] ?? '');
    addTearDown(requests.cancel);
    addTearDown(responses.cancel);
    try {
      final base = server.url.toString().replaceAll(RegExp(r'/$'), '');
      await page.goto('$base/listings/banana-bunch', wait: Until.networkIdle);
      await node('Short, medium and long banana bunches');
      await node('3D view');
      // The Lumina runtime is lazy: no part file, no wasm before the 3D view.
      bool fetched(String suffix) => requested.any((u) => Uri.parse(u).path.endsWith(suffix));
      expect(fetched('flutter_filament.wasm'), isFalse, reason: 'the page loads without the renderer');
      expect(fetched('flutter_filament.js'), isFalse);
      expect(requested.any((u) => u.contains('.part.js')), isFalse, reason: 'the Lumina runtime is a deferred library');
      expect(gpuRenderer, contains('RTX PRO 2000'), reason: 'smoke renders run on GPU 1');

      await startRecording();
      final opened = DateTime.now();
      await click('3D view', role: '*', exact: true);
      final viewer = await node('3D view ready', timeout: const Duration(minutes: 2));
      final loadSeconds = DateTime.now().difference(opened).inMilliseconds / 1000;
      expect(fetched('flutter_filament.wasm'), isTrue);
      expect(requested.any((u) => u.contains('.part.js')), isTrue);
      final wasmUrl = types.keys.firstWhere((u) => u.endsWith('flutter_filament.wasm'));
      expect(types[wasmUrl], 'application/wasm');
      final previewUrl = types.keys.firstWhere((u) => u.endsWith('/preview.glb'));
      expect(types[previewUrl], 'model/gltf-binary');

      final box = (await viewer.boundingBox)!;
      final region = Rectangle<int>(box.left.round(), box.top.round(), box.width.round(), box.height.round());
      final extra = {
        'viewer': {'x': region.left, 'y': region.top, 'w': region.width, 'h': region.height},
        'loadSeconds': loadSeconds,
      };
      final initial = await shot('3d_view_initial', test: _viewerTestName, usedAssets: assets, extra: extra);
      final variance = _modelVariance(initial, region);
      expect(variance.stdDev, greaterThan(6), reason: 'the model region is not a flat canvas ($variance)');
      expect(variance.modelShare, greaterThan(0.01), reason: 'model pixels differ from the backdrop ($variance)');

      // Orbit: drag left → right across the viewport, then up.
      final cx = box.left + box.width / 2;
      final cy = box.top + box.height / 2;
      await page.mouse.move(Point(cx - 220, cy));
      await page.mouse.down();
      await page.mouse.move(Point(cx + 220, cy + 40), steps: 60);
      await page.mouse.move(Point(cx + 160, cy - 60), steps: 30);
      await page.mouse.up();
      final orbited = await shot('3d_view_orbited', test: _viewerTestName, usedAssets: assets, extra: extra);
      final diff = _meanDiff(initial, orbited, region);
      expect(diff, greaterThan(2), reason: 'the orbit changed the view (mean diff $diff)');
      expect(_modelVariance(orbited, region).modelShare, greaterThan(0.01), reason: 'the model stays in view');

      // Zoom in with the wheel, pan with a right-drag.
      await page.mouse.move(Point(cx, cy));
      for (var i = 0; i < 6; i++) {
        await page.mouse.wheel(deltaY: -120);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await page.mouse.down(button: MouseButton.right);
      await page.mouse.move(Point(cx + 90, cy + 50), steps: 30);
      await page.mouse.up(button: MouseButton.right);
      final zoomed = await shot('3d_view_zoomed_panned', test: _viewerTestName, usedAssets: assets, extra: extra);
      expect(_meanDiff(orbited, zoomed, region), greaterThan(2), reason: 'zoom and pan changed the view');

      // A slow turntable orbit for the video, then Reset view.
      await page.mouse.move(Point(cx - 250, cy));
      await page.mouse.down();
      await page.mouse.move(Point(cx + 250, cy), steps: 150);
      await page.mouse.up();
      await click('Reset view', role: '*', exact: true);
      final reset = await shot('3d_view_reset', test: _viewerTestName, usedAssets: assets, extra: extra);
      expect(_meanDiff(initial, reset, region), lessThan(_meanDiff(initial, zoomed, region)),
          reason: 'Reset view returns towards the framed pose');

      // Fullscreen: the viewer fills the window and renders again.
      await click('Fullscreen', role: '*', exact: true);
      await node('Exit fullscreen', timeout: const Duration(minutes: 1));
      await node('3D view ready', timeout: const Duration(minutes: 1));
      final full = await shot('3d_view_fullscreen', test: _viewerTestName, usedAssets: assets);
      expect(_modelVariance(full, Rectangle<int>(0, 0, full.width, full.height)).modelShare, greaterThan(0.01),
          reason: 'the fullscreen viewer renders the model');
      await click('Exit fullscreen', role: '*', exact: true);
      await node('Images');
      await Future<void>.delayed(const Duration(seconds: 1));

      await page.devTools.page.stopScreencast();
      _saveVideo(frames, test: _viewerTestName, usedAssets: assets, extra: {'gpuRenderer': gpuRenderer});
      expect(errors, isEmpty, reason: errors.join('\n'));
    } catch (_) {
      await dumpFailure(_viewerTestName);
      rethrow;
    }
  });

  // Game templates are checked against the template format at the
  // Upload step; a valid one (a real Lumina project) publishes.
  _scenario(_templateTestName, () async {
    await startRecording();
    try {
      final base = server.url.toString().replaceAll(RegExp(r'/$'), '');
      final fixture = Directory(_templateFixture);
      final files = {
        for (final f in fixture.listSync(recursive: true).whereType<File>())
          'Arena/${f.path.substring(fixture.path.length + 1).replaceAll(r'\', '/')}': f.readAsBytesSync(),
      };
      File zipOf(String name, Map<String, List<int>> entries) {
        final archive = Archive();
        entries.forEach((path, bytes) => archive.addFile(ArchiveFile.bytes(path, bytes)));
        return File('${tmp.path}/$name')..writeAsBytesSync(ZipEncoder().encode(archive));
      }

      final broken = zipOf('arena_broken.zip', Map.of(files)..removeWhere((path, _) => path.startsWith('Arena/contents/')));
      final valid = zipOf('arena.zip', files);
      final assets = [for (final f in fixture.listSync(recursive: true).whereType<File>()) f.absolute.path];

      // Signed out (the front end scenario leaves the moderator signed in); the page may still
      // be about:blank when this scenario runs alone.
      await page.goto('$base/', wait: Until.networkIdle);
      await page.evaluate<void>('''() => fetch('/api/v1/auth/logout', {method: 'POST', credentials: 'include'})''');
      await page.goto('$base/signup', wait: Until.networkIdle);
      await type('Email', 'template.maker@example.test');
      await type('Username', 'template_maker');
      await type('Display name', 'Template Maker');
      await type('Password', 'template maker password');
      await click('Create account', exact: true);
      await node('My listings');

      await page.goto('$base/publish', wait: Until.networkIdle);
      await node('Publish to the marketplace');
      await click('Pick a category');
      await click('Game template', exact: true);
      await type('Title', 'Arena Starter');
      await type('Description', '# Arena\n\nA first-person starter arena: a real Lumina project packed as a game template.');
      await click('Create listing');
      await node('Add screenshot');
      await click('Continue', exact: true);
      await node('Game template (format 1)');
      await shot('template_upload_format', test: _templateTestName, usedAssets: assets);

      var chooser = page.waitForFileChooser();
      await click('Choose .zip');
      await (await chooser).accept([broken]);
      await node('The game template was refused: it has no contents/ folder');
      await shot('template_refused', test: _templateTestName, usedAssets: assets,
          extra: {'upload': 'arena_broken.zip (the Arena template without contents/)'});

      chooser = page.waitForFileChooser();
      await click('Choose .zip');
      await (await chooser).accept([valid]);
      await node('arena.zip');
      await node('Arena/contents/levels/L_DefaultLevel.lmas');
      await shot('template_uploaded', test: _templateTestName, usedAssets: assets);
      await click('Continue', exact: true);
      await click('Pick a content license');
      await click('CC-BY-4.0');
      await click('Pick a code license');
      await click('MIT', exact: false);
      await click('Continue', exact: true);
      await node('I own this work');
      await click('I own this work', role: '*');
      await click('Publish', exact: true);
      await node('is live');
      await shot('template_published', test: _templateTestName, usedAssets: assets);

      await page.devTools.page.stopScreencast();
      _saveVideo(frames, test: _templateTestName, usedAssets: assets);

      final listing = await MarketplaceClient(baseUrl: server.url).listing('arena-starter');
      expect(listing.category, ListingCategory.gameTemplate);
      expect(listing.latestVersion!.fileCount, files.length);
      expect(listing.licenses.ids, ['CC-BY-4.0', 'MIT']);
      // The refused upload's 422 is the answer under test, not a page error.
      final unexpected = errors.where((e) => !e.contains('status of 422')).toList();
      expect(unexpected, isEmpty, reason: unexpected.join('\n'));
    } catch (_) {
      await dumpFailure(_templateTestName);
      rethrow;
    }
  });

  // Plugin asks for the package first; the listing, the license, the
  // version and the release notes come from the plugins checkout's lumina_plugin_pcg.
  _scenario(_pluginTestName, () async {
    if (!File('$_pcgDir/lumina_plugin_pcg.lmplugin').existsSync()) {
      _skip(_pluginTestName, 'lumina_plugin_pcg is not checked out at $_pcgDir: clone LuminaGame/plugins next to this repository '
          '(../plugins) or set LUMINA_PLUGINS_DIR');
      return;
    }
    await startRecording();
    try {
      final base = server.url.toString().replaceAll(RegExp(r'/$'), '');
      final pcg = Directory(_pcgDir);
      final manifest = (jsonDecode(File('${pcg.path}/lumina_plugin_pcg.lmplugin').readAsStringSync()) as Map).cast<String, Object?>();
      File zipOf(String name, Map<String, List<int>> entries) {
        final archive = Archive();
        entries.forEach((path, bytes) => archive.addFile(ArchiveFile.bytes(path, bytes)));
        return File('${tmp.path}/$name')..writeAsBytesSync(ZipEncoder().encode(archive));
      }

      // A non-free variant (LICENSE "All rights reserved", no "license" key,
      // as the plugin once shipped) and the real folder as
      // a user zips it: every file, with .git/, build/, .dart_tool/.
      final nonFreeManifest = Map.of(manifest)..remove('license');
      final nonFree = zipOf('lumina_plugin_pcg_non_free.zip', {
        for (final f in pcg.listSync(recursive: true).whereType<File>())
          if (_pcgPackaged(f.path.substring(pcg.path.length + 1).replaceAll(r'\', '/')))
            'lumina_plugin_pcg/${f.path.substring(pcg.path.length + 1).replaceAll(r'\', '/')}': f.readAsBytesSync(),
        'lumina_plugin_pcg/lumina_plugin_pcg.lmplugin': utf8.encode(const JsonEncoder.withIndent('  ').convert(nonFreeManifest)),
        'lumina_plugin_pcg/LICENSE': utf8.encode('Copyright (c) 2026 Lumina. All rights reserved.\n'),
      });
      final folderFiles = {
        for (final f in pcg.listSync(recursive: true).whereType<File>())
          'lumina_plugin_pcg/${f.path.substring(pcg.path.length + 1).replaceAll(r'\', '/')}': f.readAsBytesSync(),
      };
      final folderZip = zipOf('lumina_plugin_pcg.zip', folderFiles);
      final assets = [
        '${pcg.path}/lumina_plugin_pcg.lmplugin',
        '${pcg.path}/CHANGELOG.md',
        '${pcg.path}/LICENSE',
        '${pcg.path}/lib',
        '${pcg.path}/resources/icon128.png',
      ];

      await page.goto('$base/', wait: Until.networkIdle);
      await page.evaluate<void>('''() => fetch('/api/v1/auth/logout', {method: 'POST', credentials: 'include'})''');
      await page.goto('$base/signup', wait: Until.networkIdle);
      await type('Email', 'plugin.maker@example.test');
      await type('Username', 'plugin_maker');
      await type('Display name', 'Plugin Maker');
      await type('Password', 'plugin maker password');
      await click('Create account', exact: true);
      await node('My listings');

      await page.goto('$base/publish', wait: Until.networkIdle);
      await node('Publish to the marketplace');
      await click('Pick a category');
      await click('Plugin', exact: true);
      await node('Plugin: a .zip of the plugin folder');
      await shot('plugin_upload_first', test: _pluginTestName, usedAssets: assets);

      var chooser = page.waitForFileChooser();
      await click('Choose plugin .zip');
      await (await chooser).accept([nonFree]);
      await node('The plugin package was refused: LICENSE reads');
      await shot('plugin_refused', test: _pluginTestName, usedAssets: assets,
          extra: {'upload': 'lumina_plugin_pcg with LICENSE "All rights reserved" and no "license" key'});

      chooser = page.waitForFileChooser();
      await click('Choose plugin .zip');
      await (await chooser).accept([folderZip]);
      await node('Read from lumina_plugin_pcg.lmplugin', timeout: const Duration(minutes: 2));
      // The generated folders were left out, and the wizard says so.
      await node('Left out');
      await shot('plugin_manifest_read', test: _pluginTestName, usedAssets: [...assets, '${pcg.path}/build', '${pcg.path}/.dart_tool'],
          extra: {
            'upload': 'the whole lumina_plugin_pcg folder (${folderFiles.length} files, ${folderZip.lengthSync()} bytes, '
                'with .git/, build/, .dart_tool/)',
          });
      await click('Continue', exact: true);
      await node('Filled from lumina_plugin_pcg.lmplugin');
      await shot('plugin_details_prefilled', test: _pluginTestName, usedAssets: assets);
      await click('Create listing');
      await node('Add screenshot');
      chooser = page.waitForFileChooser();
      await click('Add screenshot');
      await (await chooser).accept([File('${pcg.path}/resources/icon128.png')]);
      await node('Procedural Content Generation screenshot 1');
      await click('Continue', exact: true);
      await node('Declared by lumina_plugin_pcg.lmplugin');
      await click('Pick a content license');
      await click('CC-BY-4.0');
      await shot('plugin_license_locked', test: _pluginTestName, usedAssets: assets);
      await click('Continue', exact: true);
      await node('I own this work');
      await click('Show CHANGELOG.md');
      await node('Unreleased');
      await shot('plugin_publish_changelog', test: _pluginTestName, usedAssets: assets);
      await click('I own this work', role: '*');
      await click('Publish', exact: true);
      await node('is live');
      await shot('plugin_published', test: _pluginTestName, usedAssets: assets);

      await page.devTools.page.stopScreencast();
      _saveVideo(frames, test: _pluginTestName, usedAssets: assets);

      final listing = await MarketplaceClient(baseUrl: server.url).listing('procedural-content-generation');
      expect(listing.category, ListingCategory.plugin);
      expect(listing.tags, ['procedural', 'plugin']);
      expect(listing.licenses.ids, ['CC-BY-4.0', 'MIT']);
      expect(listing.latestVersion!.version, '0.1.0');
      expect(listing.latestVersion!.releaseNotes, startsWith('- Initial release'));
      // The refused upload's 422 is the answer under test, not a page error.
      final unexpected = errors.where((e) => !e.contains('status of 422')).toList();
      expect(unexpected, isEmpty, reason: unexpected.join('\n'));
    } catch (_) {
      await dumpFailure(_pluginTestName);
      rethrow;
    }
  });
}

/// Chrome's WebGL renderer string (the GPU that draws the 3D view).
Future<String> _webglRenderer(Page page) => page.evaluate<String>('''() => {
      const gl = document.createElement('canvas').getContext('webgl2') || document.createElement('canvas').getContext('webgl');
      if (!gl) return 'no webgl';
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
    }''');

/// Luminance spread in the middle of [region] and the share of pixels that
/// differ clearly from the backdrop (the region's most common grey).
({double stdDev, double modelShare}) _modelVariance(img.Image image, Rectangle<int> region) {
  final values = <int>[];
  final x0 = region.left + region.width ~/ 4, x1 = region.left + region.width * 3 ~/ 4;
  final y0 = region.top + region.height ~/ 4, y1 = region.top + region.height * 3 ~/ 4;
  for (var y = y0; y < y1; y += 3) {
    for (var x = x0; x < x1; x += 3) {
      final p = image.getPixel(x.clamp(0, image.width - 1), y.clamp(0, image.height - 1));
      values.add((0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b).round());
    }
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
  final histogram = <int, int>{};
  for (final v in values) {
    histogram[v ~/ 4] = (histogram[v ~/ 4] ?? 0) + 1;
  }
  final backdrop = histogram.entries.reduce((a, b) => a.value >= b.value ? a : b).key * 4 + 2;
  final model = values.where((v) => (v - backdrop).abs() > 24).length;
  return (stdDev: math.sqrt(variance), modelShare: model / values.length);
}

/// Mean absolute RGB difference of two frames inside [region].
double _meanDiff(img.Image a, img.Image b, Rectangle<int> region) {
  var sum = 0.0;
  var n = 0;
  for (var y = region.top; y < region.top + region.height; y += 3) {
    for (var x = region.left; x < region.left + region.width; x += 3) {
      if (x >= a.width || y >= a.height || x >= b.width || y >= b.height) continue;
      final p = a.getPixel(x, y), q = b.getPixel(x, y);
      sum += ((p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs()) / 3;
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// Lays Chrome's screencast frames on a real-time 30 fps timeline (each video
/// frame is the newest painted frame) and saves them as [test]'s VP8/WebM
/// with lumina_smoke, which checks the smoke-video rules first.
void _saveVideo(List<(int, Uint8List)> frames,
    {required String test, List<String>? usedAssets, Map<String, Object?> extra = const {}}) {
  if (frames.isEmpty) fail('Chrome streamed no frames');
  const fps = 30;
  final recorder = SmokeVideoRecorder(width: _width, height: _height, fps: fps, testName: test);
  try {
    final start = frames.first.$1;
    final end = frames.last.$1;
    var next = 0;
    Uint8List? current;
    Uint8List? rgba;
    for (var t = start.toDouble(); t <= end; t += 1000 / fps) {
      while (next < frames.length && frames[next].$1 <= t) {
        current = frames[next++].$2;
        rgba = null;
      }
      if (current == null) continue;
      rgba ??= _rgba(current);
      recorder.addFrame(rgba);
    }
    final frameCount = recorder.frameCount;
    SmokeArtifacts.saveVideo(test, recorder.finish(),
        usedAssets: usedAssets, frameCount: frameCount, fps: fps.toDouble(), width: _width, height: _height);
  } finally {
    recorder.discard();
  }
  SmokeArtifacts.annotate(test, {'chromeFrames': frames.length, ...extra});
}

/// A screencast PNG as [_width] × [_height] RGBA.
Uint8List _rgba(Uint8List png) {
  var frame = img.decodePng(png)!;
  if (frame.width != _width || frame.height != _height) frame = img.copyResize(frame, width: _width, height: _height);
  return frame.getBytes(order: img.ChannelOrder.rgba);
}

/// The scenarios this file declares, in order.
final _declared = <String>[];

/// What each scenario (and setUpAll) did in this run, for the report.
final _outcomes = <({String name, int start, int end, String? skipped, Object? error, StackTrace? stack})>[];

/// Why a scenario skipped itself, by name.
final _skipReasons = <String, String>{};

/// A scenario whose outcome goes into the report.
void _scenario(String name, Future<void> Function() body) {
  _declared.add(name);
  test(name, () {
    // An earlier run's failure evidence would otherwise stay on this run's card.
    final failure = '${SmokeArtifacts.dir.path}/${SmokeArtifacts.sanitizeTestName('$name: failure')}';
    for (final suffix in ['.png', '.json', '_semantics.txt']) {
      final f = File('$failure$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    return _recorded(name, body);
  });
}

/// Skips the running scenario [name] with [reason].
void _skip(String name, String reason) {
  _skipReasons[name] = reason;
  markTestSkipped(reason);
}

/// Runs [body], recording its outcome under [name].
Future<void> _recorded(String name, Future<void> Function() body) async {
  final start = DateTime.now().millisecondsSinceEpoch;
  try {
    await body();
    _outcomes.add((
      name: name,
      start: start,
      end: DateTime.now().millisecondsSinceEpoch,
      skipped: _skipReasons[name],
      error: null,
      stack: null,
    ));
  } catch (e, stack) {
    _outcomes.add((name: name, start: start, end: DateTime.now().millisecondsSinceEpoch, skipped: null, error: e, stack: stack));
    rethrow;
  }
}

const _reportConfig = SmokeReportConfig(
  title: 'Lumina Marketplace Web Smoke Report',
  categories: TestCategories([
    ('Marketplace web', ['marketplace']),
  ]),
  configDirVariable: null,
);

/// Merges this run into build/smoke_report.events.jsonl and writes
/// build/smoke_report.html from it with lumina_smoke: every PNG and video in
/// build/smoke_artifacts/ is matched to its scenario through its sidecar and
/// linked, never embedded. A run of some scenarios (`--plain-name`) replaces
/// only their earlier results.
void _writeReport() {
  final paths = SmokeReportPaths.fromEnvironment();
  final previous = readSmokeEvents(paths.eventsFile);
  final latestRun = <String, int>{};
  var run = 0;
  for (final e in previous) {
    final r = runOf(e);
    if (r >= run) run = r + 1;
    final key = smokeRunKey(e);
    if (key != null && r > (latestRun[key] ?? -1)) latestRun[key] = r;
  }
  final ran = {for (final o in _outcomes) o.name};
  final filter = _declared.every(ran.contains) ? null : [for (final n in _declared) if (ran.contains(n)) n].join(' | ');
  final kept = smokeEventsKeptOnMerge(previous, rerun: {_suitePath}, filter: filter, latestRun: latestRun);
  final now = DateTime.now().millisecondsSinceEpoch;
  final tags = <String, dynamic>{'run': run, 'target': _suitePath, 'targets': [_suitePath], 'filter': ?filter};
  final events = <Map<String, dynamic>>[
    {'type': 'suite', 'suite': {'id': 0, 'path': _suitePath}, 'time': _outcomes.firstOrNull?.start ?? now},
    for (final (i, o) in _outcomes.indexed) ...[
      {'type': 'testStart', 'test': {'id': i + 1, 'name': o.name, 'suiteID': 0, 'groupIDs': <int>[]}, 'time': o.start},
      if (o.skipped != null) {'type': 'print', 'testID': i + 1, 'message': 'Skip: ${o.skipped}', 'time': o.end},
      if (o.error != null)
        {'type': 'error', 'testID': i + 1, 'error': '${o.error}', 'stackTrace': '${o.stack ?? ''}', 'time': o.end},
      {
        'type': 'testDone',
        'testID': i + 1,
        'result': o.error == null ? 'success' : 'failure',
        'skipped': o.skipped != null,
        'hidden': false,
        'time': o.end,
      },
    ],
    {'type': 'done', 'success': _outcomes.every((o) => o.error == null), 'time': now},
  ].map((e) => {...e, ...tags}).toList();

  paths.eventsFile.parent.createSync(recursive: true);
  paths.eventsFile.writeAsStringSync([...kept, ...events].map((e) => '${jsonEncode(e)}\n').join());
  final generator = SmokeReportGenerator(_reportConfig);
  final model = generator.processEvents([...kept, ...events], artifactsDir: paths.artifactsDir, countedRuns: {run});
  final index = generator.writeReport(model, paths.reportFile);
  stdout.writeln('Smoke report: ${index.path} (${model.passedCount} passed, ${model.failedCount} failed, '
      '${model.skippedCount} skipped; ${model.artifactCount} artifacts)');
}

/// The files of lumina_plugin_pcg that make its package (besides the
/// manifest and LICENSE, which the scenario writes).
bool _pcgPackaged(String rel) =>
    rel == 'CHANGELOG.md' || rel == 'README.md' || rel == 'pubspec.yaml' || rel == 'resources/icon128.png' || rel.startsWith('lib/');
