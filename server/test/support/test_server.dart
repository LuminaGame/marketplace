import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

/// This repository's root (tests run in `server/`), so the suite runs
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

/// The plugin package [name] in the plugins checkout.
String pluginDir(String name) => '$pluginsDir/$name';

/// A skip reason when the plugin [name] is not checked out (null when it is).
String? skipUnlessPlugin(String name) => File('${pluginDir(name)}/$name.lmplugin').existsSync()
    ? null
    : '$name is not checked out at ${pluginDir(name)}: clone LuminaGame/plugins next to this repository '
        '(../plugins) or set LUMINA_PLUGINS_DIR';

/// The checkout of the engine repository (LuminaGame/lumina, with
/// `flutter_filament/`), read-only: `LUMINA_ENGINE_DIR`, else `../lumina`
/// next to this repository.
final engineDir = Platform.environment['LUMINA_ENGINE_DIR'] ?? '${Directory(repoDir).parent.path}/lumina';

/// A real marketplace server on an ephemeral port with a temp database and
/// storage dir, torn down after the test/group that started it.
class TestServer {
  TestServer._(this.server, this.root);

  final MarketplaceServer server;
  final Directory root;

  Uri get url => server.url;

  /// A new client with its own session.
  MarketplaceClient client() {
    final c = MarketplaceClient(baseUrl: url);
    addTearDown(c.close);
    return c;
  }

  static Future<TestServer> start({
    int loginFailuresPerMinute = 10,
    int authRequestsPerMinute = 1000,
    Duration accessTokenTtl = const Duration(minutes: 15),
    int maxUploadBytes = 256 * 1024 * 1024,
    String? webDir,
  }) async {
    final root = Directory.systemTemp.createTempSync('mkt_server_test_');
    final server = await MarketplaceServer.start(
      MarketplaceConfig(
        port: 0,
        databasePath: '${root.path}/marketplace.db',
        storageDir: '${root.path}/storage',
        jwtSecret: 'test-secret-that-is-at-least-32-characters-long',
        loginFailuresPerMinute: loginFailuresPerMinute,
        authRequestsPerMinute: authRequestsPerMinute,
        accessTokenTtl: accessTokenTtl,
        maxUploadBytes: maxUploadBytes,
        webDir: webDir,
      ),
      log: MarketplaceLog.silent(),
    );
    final t = TestServer._(server, root);
    addTearDown(() async {
      await server.close();
      root.deleteSync(recursive: true);
    });
    return t;
  }

  /// Seeds the sample CC0 listings made from `test-assets/`.
  Future<SeedResult> seed() => seedSampleContent(
        server.services,
        testAssetsDir: testAssetsDir,
        adminPassword: 'seed-admin-password',
        moderatorPassword: 'seed-moderator-password',
      );
}

var _userCounter = 0;

/// Signs up a fresh user on [client].
Future<AuthSession> signUp(MarketplaceClient client, {String? username, String password = 'correct horse battery'}) {
  final name = username ?? 'user${++_userCounter}_${DateTime.now().microsecondsSinceEpoch % 100000}';
  return client.signUp(email: '$name@example.test', username: name, password: password, displayName: 'User $name');
}

/// A zip made from real files under `test-assets/Props/<folder>`.
List<int> propsZip(String folder, {int? limit}) {
  final archive = Archive();
  final files = Directory('$testAssetsDir/Props/$folder')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.glb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files.take(limit ?? files.length)) {
    final bytes = f.readAsBytesSync();
    archive.addFile(ArchiveFile.bytes(f.uri.pathSegments.last, bytes));
  }
  return ZipEncoder().encode(archive);
}

/// The game template fixture: a real Lumina project scaffolded by
/// lumina's `ProjectRepository` from the first-person template (a level, the
/// generated game mode / character / level code and `main.dart`, the
/// `.lmproject` and `pubspec.yaml`), renamed to `arena`, with a
/// `template.json` and the level's editor thumbnail as `thumbnail.png`.
/// Read-only.
const gameTemplateFixtureDir = 'test/fixtures/game_template/Arena';

/// The fixture's files, template-relative path → bytes.
Map<String, List<int>> arenaTemplateFiles() {
  final root = Directory(gameTemplateFixtureDir);
  final files = root.listSync(recursive: true).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
  return {for (final f in files) f.path.substring(root.path.length + 1).replaceAll(r'\', '/'): f.readAsBytesSync()};
}

/// [files] zipped under the single top-level folder [top] (none when null).
List<int> templateZip(Map<String, List<int>> files, {String? top = 'Arena'}) =>
    rawZip({for (final e in files.entries) top == null ? e.key : '$top/${e.key}': e.value});

/// The example plugin `lumina_plugin_pcg` of the plugins checkout
/// ([pluginsDir], read-only; see [skipUnlessPlugin]), as
/// a package: its `.lmplugin` (plus [manifestExtra] keys), CHANGELOG.md,
/// README.md, pubspec.yaml, `lib/**` and `resources/icon128.png`, under the
/// top folder [top] (none when null). [license] replaces its LICENSE text
/// (the real one is MIT since lumina_plugin_pcg 7d66ca2); null keeps the real one.
Map<String, List<int>> pcgPluginFiles({
  Map<String, Object?> manifestExtra = const {},
  String? license,
  String? top = 'lumina_plugin_pcg',
}) {
  final root = Directory(pluginDir('lumina_plugin_pcg'));
  final files = <String, List<int>>{};
  void add(String rel, List<int> bytes) => files[top == null ? rel : '$top/$rel'] = bytes;
  final manifest = (jsonDecode(File('${root.path}/lumina_plugin_pcg.lmplugin').readAsStringSync()) as Map).cast<String, Object?>();
  add('lumina_plugin_pcg.lmplugin', utf8.encode(const JsonEncoder.withIndent('  ').convert({...manifest, ...manifestExtra})));
  for (final name in ['CHANGELOG.md', 'README.md', 'pubspec.yaml', 'resources/icon128.png']) {
    add(name, File('${root.path}/$name').readAsBytesSync());
  }
  add('LICENSE', license == null ? File('${root.path}/LICENSE').readAsBytesSync() : utf8.encode(license));
  final lib = Directory('${root.path}/lib').listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in lib) {
    add(f.path.substring(root.path.length + 1).replaceAll('\\', '/'), f.readAsBytesSync());
  }
  return files;
}

/// A non-free license text (what lumina_plugin_pcg's LICENSE read before its
/// commit 7d66ca2).
const allRightsReservedText = 'Copyright (c) 2026 Lumina. All rights reserved.\n';

/// The MIT license text (what lumina_plugin_pcg's LICENSE reads since 7d66ca2).
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

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
''';

/// A zip with the given entries (name → bytes), names written verbatim.
List<int> rawZip(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)));
  return ZipEncoder().encode(archive);
}

/// Creates a listing, uploads [zip] and publishes version [version] with
/// [licenses] and the attestation ticked.
Future<(Listing, ListingVersion)> publish(
  MarketplaceClient client, {
  required String title,
  ListingCategory category = ListingCategory.model,
  required List<int> zip,
  LicenseSelection licenses = const LicenseSelection(content: 'CC0-1.0'),
  String version = '1.0.0',
  List<String> tags = const [],
  String description = '',
}) async {
  final terms = await client.terms();
  final listing = await client.createListing(
      NewListing(category: category, title: title, tags: tags, description: description));
  final upload = await client.upload(zip, fileName: '${installFolderName(title)}.zip');
  final v = await client.publishVersion(
    listing.id,
    NewVersion(
      version: version,
      uploadId: upload.id,
      licenses: licenses,
      attestation: true,
      termsVersion: terms.version,
    ),
  );
  return (await client.listing(listing.id), v);
}

Matcher throwsApi(int status, [String? code]) => throwsA(isA<MarketplaceException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.code, 'code', code ?? anything));
