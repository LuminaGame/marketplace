import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:lumina_marketplace_web/src/app.dart';
import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/platform/files.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// This repository's root (widget tests run in `web/`), so the tests run
/// wherever the repository is checked out (Linux or Windows).
final repoDir = Directory.current.parent.path;

/// The shared test assets (real CC0 meshes), read-only: `LUMINA_TEST_ASSETS`,
/// else the repository's `test-assets/` (a link to the shared assets folder).
final testAssetsDir = Platform.environment['LUMINA_TEST_ASSETS'] ?? '$repoDir/test-assets';

/// A real PNG of the repository (the marketplace logo). Read-only.
final logoPng = '$repoDir/web/assets/lumina_logo.png';

/// The checkout of the plugins repository (LuminaGame/plugins, with
/// `lumina_plugin_pcg/` and `lumina_plugin_miniai/`), read-only:
/// `LUMINA_PLUGINS_DIR`, else `../plugins` next to this repository.
final pluginsDir = Platform.environment['LUMINA_PLUGINS_DIR'] ?? '${Directory(repoDir).parent.path}/plugins';

/// A skip reason when the plugin [name] is not checked out (null when it is).
String? skipUnlessPlugin(String name) => File('$pluginsDir/$name/$name.lmplugin').existsSync()
    ? null
    : '$name is not checked out at $pluginsDir/$name: clone LuminaGame/plugins next to this repository '
        '(../plugins) or set LUMINA_PLUGINS_DIR';

/// A skip reason when the plugin [name] is not checked out or has not been
/// built (its folder zips carry its real generated `.dart_tool/`
/// and `build/native_assets/windows/` files); null when it is ready.
String? skipUnlessPluginBuilt(String name) =>
    skipUnlessPlugin(name) ??
    (['.dart_tool/version', 'build/native_assets/windows/flutter_assimp.dll']
            .every((rel) => File('$pluginsDir/$name/$rel').existsSync())
        ? null
        : '$name at $pluginsDir/$name has not been built (needs .dart_tool/ and build/native_assets/windows/: '
            'run `flutter pub get` and a Windows build in it)');
/// The plugins checkout's example plugin, `lumina_plugin_pcg` (read-only),
/// as a package under `lumina_plugin_pcg/`: its `.lmplugin` (plus
/// [manifestExtra] keys; a null value removes a key), CHANGELOG.md, README.md,
/// pubspec.yaml, `lib/**` and `resources/icon128.png`. [license] replaces its
/// LICENSE text (the real one is MIT since lumina_plugin_pcg 7d66ca2); null
/// keeps the real one. [asFolder] zips it the way a user zips the
/// folder: also `.gitignore`, `.metadata`, `pubspec.lock`,
/// `analysis_options.yaml`, `test/**` and real generated files from `build/`
/// and `.dart_tool/`.
Map<String, List<int>> pcgPluginFiles({Map<String, Object?> manifestExtra = const {}, String? license, bool asFolder = false}) {
  final root = Directory('$pluginsDir/lumina_plugin_pcg');
  const top = 'lumina_plugin_pcg';
  final manifest = (jsonDecode(File('${root.path}/lumina_plugin_pcg.lmplugin').readAsStringSync()) as Map).cast<String, Object?>()
    ..addAll(manifestExtra)
    ..removeWhere((_, v) => v == null);
  final files = <String, List<int>>{
    '$top/lumina_plugin_pcg.lmplugin': utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    for (final name in ['CHANGELOG.md', 'README.md', 'pubspec.yaml', 'resources/icon128.png'])
      '$top/$name': File('${root.path}/$name').readAsBytesSync(),
    '$top/LICENSE': license == null ? File('${root.path}/LICENSE').readAsBytesSync() : utf8.encode(license),
    if (asFolder)
      for (final name in [
        '.gitignore', '.metadata', 'pubspec.lock', 'analysis_options.yaml', //
        '.dart_tool/version', '.dart_tool/package_config.json', 'build/native_assets/windows/native_assets.json',
        'build/native_assets/windows/flutter_assimp.dll',
      ])
        if (File('${root.path}/$name').existsSync()) '$top/$name': File('${root.path}/$name').readAsBytesSync(),
  };
  for (final folder in ['lib', if (asFolder) 'test']) {
    for (final f in Directory('${root.path}/$folder').listSync(recursive: true).whereType<File>()) {
      files['$top/${f.path.substring(root.path.length + 1).replaceAll(r'\', '/')}'] = f.readAsBytesSync();
    }
  }
  return files;
}

/// A non-free license text (what lumina_plugin_pcg's LICENSE read before its
/// commit 7d66ca2).
const allRightsReservedText = 'Copyright (c) 2026 Lumina. All rights reserved.\n';

/// The MIT license text (what lumina_plugin_pcg's LICENSE would read to be
/// publishable).
const mitLicenseText = '''MIT License

Copyright (c) 2026 Lumina

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
''';

/// A real marketplace server (temp SQLite DB + storage dir, ephemeral port)
/// seeded with the sample CC0 listings, shared by a test file.
class TestBackend {
  TestBackend._(this.server, this.root);
  final MarketplaceServer server;
  final Directory root;

  Uri get url => server.url;

  static Future<TestBackend> start() async {
    final root = Directory.systemTemp.createTempSync('mkt_web_test_');
    final server = await MarketplaceServer.start(
      MarketplaceConfig(
        port: 0,
        databasePath: '${root.path}/marketplace.db',
        storageDir: '${root.path}/storage',
        jwtSecret: 'web-test-secret-that-is-at-least-32-characters',
        authRequestsPerMinute: 1000,
      ),
      log: MarketplaceLog.silent(),
    );
    await seedSampleContent(server.services,
        testAssetsDir: testAssetsDir, adminPassword: 'seed-admin-password', moderatorPassword: 'seed-moderator-password');
    return TestBackend._(server, root);
  }

  /// A client on a real `dart:io` HttpClient: flutter_test's default
  /// HttpOverrides answer every request with 400, so tests opt out of them
  /// for the marketplace API (this is a real server, not a fake).
  ///
  /// Requests run in the root zone, so dart:io's keep-alive timers are real
  /// timers rather than fake ones left pending at the end of a widget test.
  MarketplaceClient client() => MarketplaceClient(
        baseUrl: url,
        httpClient: _RootZoneClient(IOClient(HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttpOverrides()))),
      );

  Future<void> stop() async {
    await server.close();
    root.deleteSync(recursive: true);
  }
}

class _RealHttpOverrides extends HttpOverrides {}

class _RootZoneClient extends http.BaseClient {
  _RootZoneClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => Zone.root.run(() => _inner.send(request));

  @override
  void close() => Zone.root.run(_inner.close);
}

/// Hands out real files from disk in order: the widget tests' stand-in for the
/// browser's file dialog (a platform seam, not a fake server).
class QueuedFileSource implements FileSource {
  QueuedFileSource(this.paths);
  final List<String> paths;
  final picked = <String>[];

  @override
  Future<PickedFile?> pick({required List<String> extensions}) async {
    if (paths.isEmpty) return null;
    final path = paths.removeAt(0);
    picked.add(path);
    final file = File(path);
    return PickedFile(file.uri.pathSegments.last, file.readAsBytesSync());
  }
}

var _counter = 0;

/// Signs up a fresh account through the API.
Future<AuthSession> signUpUser(MarketplaceClient client, [String? name]) {
  final username = name ?? 'web${++_counter}_${DateTime.now().microsecondsSinceEpoch % 100000}';
  return client.signUp(
      email: '$username@example.test', username: username, password: 'correct horse battery', displayName: 'User $username');
}

/// Pumps the app at [location] on a desktop-sized surface.
Future<MarketplaceSession> pumpApp(
  WidgetTester tester,
  MarketplaceClient client, {
  String location = '/',
  FileSource? files,
  int searchPageSize = 24,
}) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = MarketplaceSession(client);
  await tester.pumpWidget(MarketplaceApp(
    // A fresh app (router, session) per pump, not a rebuild of the last one.
    key: UniqueKey(),
    session: session,
    initialLocation: location,
    fileSource: files,
    searchPageSize: searchPageSize,
    // The store is a desktop-first web app.
    platform: TargetPlatform.linux,
  ));
  await settle(tester);
  return session;
}

/// Lets real I/O (the HTTP round trips to the server) complete and pumps
/// frames, until [until] finds something (or, without it, for a short while).
Future<void> settle(WidgetTester tester, {Finder? until, Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  var quiet = 0;
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 16));
    if (until != null) {
      if (until.evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 300));
        return;
      }
    } else if (++quiet > 12) {
      return;
    }
  }
  if (until != null) fail('Timed out waiting for $until');
}

Future<void> tapOn(WidgetTester tester, Finder finder, {Finder? until}) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester, until: until);
}

/// Opens a shadcn Select and picks the option with [optionKey].
Future<void> choose(WidgetTester tester, Key selectKey, Key optionKey) async {
  await tapOn(tester, find.byKey(selectKey), until: find.byKey(optionKey));
  await tapOn(tester, find.byKey(optionKey));
}
