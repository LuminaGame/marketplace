import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:path/path.dart' as p;

/// End-to-end smoke of the marketplace API against a real server process.
///
/// Starts `bin/server.dart --seed` on an ephemeral port with a temp database
/// and storage dir, then drives it through `MarketplaceClient` the way the web
/// front end and Lumina Studio do: sign up, publish a CC0 model (real meshes
/// from test-assets) with the ownership attestation, search it, "Get (Free)"
/// it, fetch the install manifest and download every file, verifying hashes.
/// Publish a game template (the real Lumina project in
/// `test/fixtures/game_template/Arena/`), see a broken one refused with
/// `422 invalid_template` (on upload and on publish), and download the valid
/// one's manifest, which installs under `templates/Arena/`.
/// A non-free package and a stray executable are refused
/// (naming the path); the workspace's whole lumina_plugin_pcg folder zip (MIT,
/// with .git/, build/, .dart_tool/, which are left out) is published from its
/// `.lmplugin`: 422 version_mismatch / license_mismatch, release notes from its
/// CHANGELOG.md, installed under `plugins/lumina_plugin_pcg/`.
///
/// Evidence: `build/smoke_artifacts/e2e_smoke.log` (every step and the
/// server's structured log) and `build/smoke_artifacts/e2e_smoke.json`.
///
///   dart run tool/e2e_smoke.dart
Future<void> main() async {
  final serverDir = p.normalize(p.join(p.dirname(Platform.script.toFilePath()), '..'));
  final artifacts = Directory(p.join(serverDir, 'build', 'smoke_artifacts'))..createSync(recursive: true);
  final testAssets = Platform.environment['LUMINA_TEST_ASSETS'] ?? p.normalize(p.join(serverDir, '..', 'test-assets'));
  // lumina_plugin_pcg of the plugins checkout (LuminaGame/plugins):
  // LUMINA_PLUGINS_DIR, else ../plugins next to this repository.
  final pcgPath = p.normalize(
      p.join(Platform.environment['LUMINA_PLUGINS_DIR'] ?? p.join(serverDir, '..', '..', 'plugins'), 'lumina_plugin_pcg'));
  final tmp = Directory.systemTemp.createTempSync('mkt_e2e_smoke_');
  final log = <String>[];
  final steps = <Map<String, Object?>>[];
  final clock = Stopwatch()..start();
  void note(String line) {
    final stamped = '[${(clock.elapsedMilliseconds / 1000).toStringAsFixed(2)}s] $line';
    log.add(stamped);
    stdout.writeln(stamped);
  }

  Future<T> step<T>(String name, Future<T> Function() body, [Object? Function(T)? evidence]) async {
    final sw = Stopwatch()..start();
    try {
      final result = await body();
      steps.add({'step': name, 'ok': true, 'ms': sw.elapsedMilliseconds, 'evidence': ?evidence?.call(result)});
      note('PASS $name (${sw.elapsedMilliseconds} ms)');
      return result;
    } catch (e) {
      steps.add({'step': name, 'ok': false, 'ms': sw.elapsedMilliseconds, 'error': '$e'});
      note('FAIL $name: $e');
      rethrow;
    }
  }

  note('starting server: dart run bin/server.dart --seed (db + storage in ${tmp.path})');
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'bin/server.dart', '--seed'],
    workingDirectory: serverDir,
    environment: {
      'MARKETPLACE_PORT': '0',
      'MARKETPLACE_DB': p.join(tmp.path, 'marketplace.db'),
      'MARKETPLACE_STORAGE': p.join(tmp.path, 'storage'),
      'MARKETPLACE_JWT_SECRET': base64.encode(List.generate(32, (i) => (i * 97 + DateTime.now().microsecond) % 256)),
      'MARKETPLACE_TEST_ASSETS': testAssets,
      'MARKETPLACE_SEED_ADMIN_PASSWORD': 'smoke-admin-password',
      'MARKETPLACE_SEED_MODERATOR_PASSWORD': 'smoke-moderator-password',
    },
  );
  final serverLog = <String>[];
  final listening = Completer<Uri>();
  final seeded = Completer<void>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    serverLog.add(line);
    try {
      final json = jsonDecode(line) as Map;
      if (json['msg'] == 'listening' && !listening.isCompleted) listening.complete(Uri.parse(json['url'] as String));
      if ((json['msg'] == 'seeded' || json['msg'] == 'seed accounts') && !seeded.isCompleted) seeded.complete();
    } catch (_) {}
  });
  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => serverLog.add('stderr: $l'));

  var ok = false;
  final clients = <MarketplaceClient>[];
  try {
    final url = await listening.future.timeout(const Duration(minutes: 3));
    note('server listening at $url');
    await seeded.future.timeout(const Duration(minutes: 2));
    note('seed finished');

    final anon = MarketplaceClient(baseUrl: url);
    final publisher = MarketplaceClient(baseUrl: url);
    final buyer = MarketplaceClient(baseUrl: url);
    clients.addAll([anon, publisher, buyer]);

    await step('health + docs', () async {
      final http = HttpClient();
      try {
        final health = await http.getUrl(url.resolve('api/v1/health')).then((r) => r.close());
        await health.drain<void>();
        if (health.statusCode != 200) throw StateError('health ${health.statusCode}');
        final docs = await http.getUrl(url.resolve('docs')).then((r) => r.close());
        await docs.drain<void>();
        if (docs.statusCode != 200) throw StateError('docs ${docs.statusCode}');
        return docs.statusCode;
      } finally {
        http.close(force: true);
      }
    });

    await step('seeded catalogue is searchable', () => anon.search(const SearchQuery(pageSize: 100)),
        (ResultPage<Listing> r) => [for (final l in r.items) '${l.category.wire}: ${l.title}']);

    await step('sign up a publisher', () => publisher.signUp(
        email: 'smoke.publisher@example.test', username: 'smoke_publisher', password: 'smoke publisher password',
        displayName: 'Smoke Publisher'), (AuthSession s) => {'user': s.user.username, 'role': s.user.role.wire});

    final terms = await step('read the publishing terms', () => publisher.terms(),
        (Terms t) => {'version': t.version, 'attestation': t.attestationStatement, 'penalty': t.penalty});

    final coconutDir = Directory(p.join(testAssets, 'Props', 'Coconut'));
    final meshes = coconutDir.listSync().whereType<File>().where((f) => f.path.endsWith('.glb')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final zip = await step('zip real CC0 meshes from test-assets/Props/Coconut', () async {
      final archive = Archive();
      for (final m in meshes) {
        archive.addFile(ArchiveFile.bytes(p.basename(m.path), m.readAsBytesSync()));
      }
      return ZipEncoder().encode(archive);
    }, (List<int> z) => {'files': meshes.map((m) => p.basename(m.path)).toList(), 'bytes': z.length});

    final listing = await step('create a draft listing (free)', () => publisher.createListing(const NewListing(
          category: ListingCategory.model,
          title: 'Coconut Smoke Pack',
          description: '# Coconut Smoke Pack\n\nCoconuts published by the end-to-end smoke.',
          tags: ['coconut', 'fruit', 'smoke'],
        )), (Listing l) => {'id': l.id, 'slug': l.slug, 'status': l.status.wire, 'priceCents': l.priceCents});

    await step('a paid listing is refused (free only)', () async {
      try {
        await publisher.createListing(const NewListing(category: ListingCategory.model, title: 'Paid', priceCents: 500));
        throw StateError('priceCents 500 was accepted');
      } on MarketplaceException catch (e) {
        if (e.code != 'price_not_supported') rethrow;
        return e.code;
      }
    });

    final upload = await step('upload the zip', () => publisher.upload(zip, fileName: 'coconut.zip'),
        (UploadInfo u) => {'id': u.id, 'sha256': u.sha256, 'files': u.files.map((f) => f.path).toList(),
          'detectedLicenseKinds': u.detectedLicenseKinds.map((k) => k.wire).toList()});

    await step('publishing without the attestation is refused', () async {
      try {
        await publisher.publishVersion(listing.id, NewVersion(version: '1.0.0', uploadId: upload.id,
            licenses: const LicenseSelection(content: 'CC0-1.0'), attestation: false, termsVersion: terms.version));
        throw StateError('published without attestation');
      } on MarketplaceException catch (e) {
        if (e.code != 'attestation_required') rethrow;
        return e.code;
      }
    });

    await step('publish v1.0.0 under CC0-1.0 with the attestation', () => publisher.publishVersion(listing.id,
        NewVersion(version: '1.0.0', uploadId: upload.id, licenses: const LicenseSelection(content: 'CC0-1.0'),
            attestation: true, termsVersion: terms.version, releaseNotes: 'First release.')),
        (ListingVersion v) => v.toJson());

    await step('search "coconut" finds it', () async {
      final r = await anon.search(const SearchQuery(q: 'coconut', category: ListingCategory.model, licenseKind: LicenseKind.content));
      if (r.items.isEmpty || r.items.first.id != listing.id) throw StateError('not first: ${r.items.map((l) => l.title)}');
      return r;
    }, (ResultPage<Listing> r) => [for (final l in r.items) l.title]);

    await step('sign up a buyer and Get (Free)', () async {
      await buyer.signUp(email: 'smoke.buyer@example.test', username: 'smoke_buyer', password: 'smoke buyer password');
      return buyer.getListing(listing.id);
    }, (LibraryEntry e) => {'listing': e.listing.title, 'acquiredAt': e.acquiredAt.toIso8601String()});

    await step('the library lists it', () async {
      final lib = await buyer.library();
      if (!lib.any((e) => e.listing.id == listing.id)) throw StateError('not in library');
      return lib;
    }, (List<LibraryEntry> lib) => [for (final e in lib) e.listing.title]);

    final manifest = await step('fetch the install manifest', () => buyer.manifest(listing.id, '1.0.0'),
        (InstallManifest m) => m.toJson());
    if (!manifest.files.every((f) => f.target.startsWith('contents/Marketplace/smoke_publisher/Coconut_Smoke_Pack/'))) {
      throw StateError('a manifest target is outside contents/Marketplace/<Publisher>/<Listing>/');
    }

    await step('download every manifest file and verify its SHA-256', () async {
      final checked = <String>[];
      for (final f in manifest.files) {
        final bytes = await buyer.downloadUrl(f.url);
        final original = File(p.join(coconutDir.path, f.path)).readAsBytesSync();
        if (sha256.convert(bytes).toString() != f.sha256 || bytes.length != original.length) {
          throw StateError('${f.path} does not match');
        }
        checked.add('${f.path} → ${f.target} (${f.size} B, sha256 ok)');
      }
      final archive = await buyer.downloadUrl(manifest.archiveUrl);
      if (sha256.convert(archive).toString() != manifest.archiveSha256) throw StateError('archive hash mismatch');
      checked.add('archive ${manifest.archiveSize} B, sha256 ok, identical to the upload: ${_same(archive, zip)}');
      return checked;
    }, (List<String> c) => c);

    // A plugin version is read from its package — the
    // plugins checkout's real lumina_plugin_pcg (MIT since its commit 7d66ca2), zipped
    // the way a user zips the folder: everything, with .git/, the generated
    // build/ (native-asset DLLs) and .dart_tool/, which the server leaves out.
    final pcgRoot = Directory(pcgPath);
    Map<String, List<int>> pcgFiles({Map<String, Object?> manifestExtra = const {}, String? license, bool wholeFolder = false}) {
      final manifest = (jsonDecode(File(p.join(pcgRoot.path, 'lumina_plugin_pcg.lmplugin')).readAsStringSync()) as Map)
          .cast<String, Object?>()
        ..addAll(manifestExtra)
        ..removeWhere((_, v) => v == null);
      final files = <String, List<int>>{};
      for (final f in pcgRoot.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: pcgRoot.path).replaceAll(r'\', '/');
        if (wholeFolder ||
            rel == 'CHANGELOG.md' || rel == 'README.md' || rel == 'pubspec.yaml' || rel == 'resources/icon128.png' ||
            rel.startsWith('lib/')) {
          files['lumina_plugin_pcg/$rel'] = f.readAsBytesSync();
        }
      }
      if (manifestExtra.isNotEmpty) {
        files['lumina_plugin_pcg/lumina_plugin_pcg.lmplugin'] = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
      } else {
        files['lumina_plugin_pcg/lumina_plugin_pcg.lmplugin'] = File(p.join(pcgRoot.path, 'lumina_plugin_pcg.lmplugin')).readAsBytesSync();
      }
      files['lumina_plugin_pcg/LICENSE'] = license == null ? File(p.join(pcgRoot.path, 'LICENSE')).readAsBytesSync() : utf8.encode(license);
      return files;
    }

    List<int> zipFiles(Map<String, List<int>> files) {
      final archive = Archive();
      files.forEach((path, bytes) => archive.addFile(ArchiveFile.bytes(path, bytes)));
      return ZipEncoder().encode(archive);
    }

    await step('A package with a non-free LICENSE and no "license" key is refused on upload: 422 invalid_plugin',
        () async {
      try {
        await publisher.upload(zipFiles(pcgFiles(manifestExtra: {'license': null}, license: 'Copyright (c) 2026 Lumina. All rights reserved.\n')),
            fileName: 'lumina_plugin_pcg.zip', category: ListingCategory.plugin);
        throw StateError('a package with a non-free LICENSE was accepted');
      } on MarketplaceException catch (e) {
        if (e.statusCode != 422 || e.code != 'invalid_plugin' || e.details['problem'] != 'license_not_free') rethrow;
        return e;
      }
    }, (MarketplaceException e) => e.toJson());

    final pluginFiles = pcgFiles(wholeFolder: true);
    final folderZip = zipFiles(pluginFiles);
    await step('A stray executable is refused, and the message names it', () async {
      try {
        await publisher.upload(zipFiles({...pcgFiles(), 'lumina_plugin_pcg/tools/run.exe': [0x4D, 0x5A, 0x90, 0]}),
            fileName: 'lumina_plugin_pcg.zip', category: ListingCategory.plugin);
        throw StateError('an executable was accepted');
      } on MarketplaceException catch (e) {
        if (e.code != 'invalid_archive' || !e.message.contains('lumina_plugin_pcg/tools/run.exe')) rethrow;
        return e;
      }
    }, (MarketplaceException e) => e.toJson());
    final pluginUpload = await step(
        'Upload the whole lumina_plugin_pcg folder zip (${pluginFiles.length} files, '
        '${(folderZip.length / 1048576).toStringAsFixed(1)} MB, incl. .git/ build/ .dart_tool/) → generated folders left out',
        () async {
      final u = await publisher.upload(folderZip, fileName: 'lumina_plugin_pcg.zip', category: ListingCategory.plugin);
      final pl = u.plugin;
      if (pl == null || pl.title != 'Procedural Content Generation' || pl.version != '0.1.0' || pl.license?.code != 'MIT' ||
          pl.minEngineVersion != '0.0.1' || !(pl.releaseNotes ?? '').startsWith('- Initial release')) {
        throw StateError('unexpected plugin package: ${u.toJson()['plugin']}');
      }
      for (final folder in ['lumina_plugin_pcg/.dart_tool/', 'lumina_plugin_pcg/.git/', 'lumina_plugin_pcg/build/']) {
        if (!u.skippedPaths.contains(folder)) throw StateError('$folder was not left out: ${u.skippedPaths}');
      }
      if (u.files.any((f) => u.skippedPaths.any(f.path.startsWith))) throw StateError('a generated file was stored');
      return u;
    }, (UploadInfo u) => {
          'skippedPaths': u.skippedPaths,
          'skippedFileCount': u.skippedFileCount,
          'storedFiles': u.files.length,
          'plugin': u.plugin!.toJson(),
        });
    final pluginInfo = pluginUpload.plugin!;

    final plugin = await step('Create the plugin listing from the manifest',
        () => publisher.createListing(NewListing(
              category: ListingCategory.plugin,
              title: pluginInfo.title,
              description: pluginInfo.description,
              tags: pluginInfo.tags,
              engineVersion: pluginInfo.minEngineVersion!,
            )),
        (Listing l) => {'id': l.id, 'slug': l.slug, 'title': l.title, 'tags': l.tags, 'engineVersion': l.engineVersion});

    Future<MarketplaceException> refused(String code, NewVersion v) async {
      try {
        await publisher.publishVersion(plugin.id, v);
        throw StateError('published although it should be $code');
      } on MarketplaceException catch (e) {
        if (e.statusCode != 422 || e.code != code) rethrow;
        return e;
      }
    }

    await step('Publishing it as 2.0.0 is refused: 422 version_mismatch', () => refused('version_mismatch',
        NewVersion(version: '2.0.0', uploadId: pluginUpload.id, licenses: const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT'),
            attestation: true, termsVersion: terms.version)), (MarketplaceException e) => e.toJson());
    await step('Replacing the declared MIT by Apache-2.0 is refused: 422 license_mismatch', () => refused('license_mismatch',
        NewVersion(version: '0.1.0', uploadId: pluginUpload.id, licenses: const LicenseSelection(content: 'CC-BY-4.0', code: 'Apache-2.0'),
            attestation: true, termsVersion: terms.version)), (MarketplaceException e) => e.toJson());

    final pluginVersion = await step('Publish 0.1.0 (MIT from the manifest + CC-BY-4.0 for the icon), notes from CHANGELOG.md',
        () => publisher.publishVersion(plugin.id, NewVersion(version: '0.1.0', uploadId: pluginUpload.id,
            licenses: const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT'), attestation: true, termsVersion: terms.version)),
        (ListingVersion v) => v.toJson());
    if (pluginVersion.releaseNotes != pluginInfo.releaseNotes) throw StateError('the release notes are not the changelog section');

    await step('Get (Free) the plugin; its manifest installs under plugins/lumina_plugin_pcg/', () async {
      await buyer.getListing(plugin.id);
      final m = await buyer.manifest(plugin.id, '0.1.0');
      if (m.targetRoot != 'plugins/lumina_plugin_pcg/' ||
          !m.files.any((f) => f.target == 'plugins/lumina_plugin_pcg/lumina_plugin_pcg.lmplugin')) {
        throw StateError('unexpected install target ${m.targetRoot}');
      }
      for (final f in m.files) {
        final bytes = await buyer.downloadUrl(f.url);
        if (!_same(bytes, pluginFiles[f.path]!)) throw StateError('${f.path} does not match');
      }
      return m;
    }, (InstallManifest m) => {'targetRoot': m.targetRoot, 'files': m.files.map((f) => f.target).toList()});

    // Game templates follow the template format.
    final fixture = Directory(p.join(serverDir, 'test', 'fixtures', 'game_template', 'Arena'));
    final templateFiles = {
      for (final f in fixture.listSync(recursive: true).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path)))
        'Arena/${p.relative(f.path, from: fixture.path).replaceAll(r'\', '/')}': f.readAsBytesSync(),
    };
    List<int> zipOf(Map<String, List<int>> files) {
      final archive = Archive();
      files.forEach((path, bytes) => archive.addFile(ArchiveFile.bytes(path, bytes)));
      return ZipEncoder().encode(archive);
    }

    final template = await step('create a game template listing (Arena, a real Lumina project)',
        () => publisher.createListing(const NewListing(
              category: ListingCategory.gameTemplate,
              title: 'Arena Smoke Template',
              description: '# Arena\n\nA first-person starter arena published by the end-to-end smoke.',
              tags: ['template', 'arena', 'smoke'],
            )),
        (Listing l) => {'id': l.id, 'slug': l.slug, 'category': l.category.wire});

    final brokenFiles = Map.of(templateFiles)
      ..removeWhere((path, _) => path.startsWith('Arena/contents/'))
      ..['Arena/linux/CMakeLists.txt'] = utf8.encode('project(arena)\n');
    final broken = zipOf(brokenFiles);
    await step('a broken game template (no contents/, a linux/ folder) is refused on upload: 422 invalid_template',
        () async {
      try {
        await publisher.upload(broken, fileName: 'arena_broken.zip', category: ListingCategory.gameTemplate);
        throw StateError('the broken template upload was accepted');
      } on MarketplaceException catch (e) {
        if (e.statusCode != 422 || e.code != 'invalid_template') rethrow;
        return e;
      }
    }, (MarketplaceException e) => e.toJson());

    await step('the same archive uploaded without the category is refused at publish: 422 invalid_template', () async {
      final upload = await publisher.upload(broken, fileName: 'arena_broken.zip');
      try {
        await publisher.publishVersion(template.id, NewVersion(version: '1.0.0', uploadId: upload.id,
            licenses: const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT'), attestation: true,
            termsVersion: terms.version));
        throw StateError('the broken template was published');
      } on MarketplaceException catch (e) {
        if (e.statusCode != 422 || e.code != 'invalid_template') rethrow;
        return e;
      }
    }, (MarketplaceException e) => e.toJson());

    final templateZip = zipOf(templateFiles);
    final templateUpload = await step('upload the valid game template (?category=game_template)',
        () => publisher.upload(templateZip, fileName: 'arena.zip', category: ListingCategory.gameTemplate),
        (UploadInfo u) => {'id': u.id, 'files': u.files.map((f) => f.path).toList(),
          'detectedLicenseKinds': u.detectedLicenseKinds.map((k) => k.wire).toList()});

    await step('publish the game template v1.0.0 under CC-BY-4.0 + MIT', () => publisher.publishVersion(template.id,
        NewVersion(version: '1.0.0', uploadId: templateUpload.id,
            licenses: const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT'), attestation: true,
            termsVersion: terms.version, releaseNotes: 'First release.')),
        (ListingVersion v) => v.toJson());

    final templateManifest = await step('Get (Free) the template and fetch its install manifest', () async {
      await buyer.getListing(template.id);
      return buyer.manifest(template.id, '1.0.0');
    }, (InstallManifest m) => m.toJson());
    if (templateManifest.targetRoot != 'templates/Arena/' ||
        !templateManifest.files.every((f) => f.target.startsWith('templates/Arena/'))) {
      throw StateError('the template manifest does not install under templates/Arena/');
    }

    await step('download every template file and verify its SHA-256', () async {
      final checked = <String>[];
      for (final f in templateManifest.files) {
        final bytes = await buyer.downloadUrl(f.url);
        if (sha256.convert(bytes).toString() != f.sha256 || !_same(bytes, templateFiles[f.path]!)) {
          throw StateError('${f.path} does not match');
        }
        checked.add('${f.path} → ${f.target} (${f.size} B, sha256 ok)');
      }
      return checked;
    }, (List<String> c) => c);

    await step('moderator suspends the publisher: listings unlisted, tokens revoked', () async {
      final mod = MarketplaceClient(baseUrl: url);
      clients.add(mod);
      await mod.logIn(login: 'moderator', password: 'smoke-moderator-password');
      await mod.suspend('smoke_publisher', reason: 'Smoke test of the penalty clause.');
      final r = await anon.search(const SearchQuery(q: 'coconut'));
      if (r.items.any((l) => l.id == listing.id)) throw StateError('still searchable');
      try {
        await publisher.me();
        throw StateError('suspended token still works');
      } on MarketplaceException catch (e) {
        if (e.statusCode != 401) rethrow;
      }
      return (await mod.auditLog(limit: 10)).map((e) => '${e.actor} ${e.action} ${e.targetType}:${e.targetId}').toList();
    }, (List<String> audit) => audit);
    ok = true;
  } catch (e, st) {
    note('smoke failed: $e\n$st');
  } finally {
    for (final c in clients) {
      c.close();
    }
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    File(p.join(artifacts.path, 'e2e_smoke.log'))
        .writeAsStringSync('${log.join('\n')}\n\n--- server log (JSON lines) ---\n${serverLog.join('\n')}\n');
    File(p.join(artifacts.path, 'e2e_smoke.json')).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'test': 'marketplace e2e smoke',
      'ok': ok,
      'date': DateTime.now().toUtc().toIso8601String(),
      'usedAssets': [
        for (final f in Directory(p.join(testAssets, 'Props', 'Coconut')).listSync()) f.path,
        for (final f in Directory(p.join(serverDir, 'test', 'fixtures', 'game_template', 'Arena')).listSync(recursive: true))
          if (f is File) f.path,
        pcgPath,
      ],
      'steps': steps,
    }));
    tmp.deleteSync(recursive: true);
    note('evidence: ${artifacts.path}/e2e_smoke.{log,json}');
  }
  exit(ok ? 0 : 1);
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
