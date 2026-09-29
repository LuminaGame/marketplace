import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

/// A zip of a real plugin folder — the plugins checkout's lumina_plugin_pcg
/// as a user zips it, with its dot files, LICENSE, pubspec.lock, test/ and the
/// generated build/ and .dart_tool/ — uploads; the generated folders are left
/// out and reported; refusals name every offending path.
void main() {
  final pcgSkip = skipUnlessPlugin('lumina_plugin_pcg');
  // The folder tests zip real generated files (build/, .dart_tool/, pubspec.lock),
  // which exist only once the plugin has been built on Windows.
  final builtSkip = pcgSkip ??
      (_sampledGenerated.every((rel) => File('${pluginDir('lumina_plugin_pcg')}/$rel').existsSync()) &&
              File('${pluginDir('lumina_plugin_pcg')}/pubspec.lock').existsSync()
          ? null
          : 'lumina_plugin_pcg at ${pluginDir('lumina_plugin_pcg')} has not been built (needs pubspec.lock, .dart_tool/ '
              'and build/native_assets/windows/: run `flutter pub get` and a Windows build in it)');
  late TestServer server;
  late MarketplaceClient publisher;

  setUp(() async {
    server = await TestServer.start();
    publisher = server.client();
    await signUp(publisher, username: 'folder_zipper');
  });

  /// The real folder under `lumina_plugin_pcg/`: every file outside build/,
  /// .dart_tool/ and .git/, plus real generated files from build/ and
  /// .dart_tool/ (a native-assets DLL among them) — the full generated folders
  /// are 180 MB, which the e2e and browser smokes upload.
  Map<String, List<int>> realFolder() {
    final root = Directory(pluginDir('lumina_plugin_pcg'));
    final files = <String, List<int>>{};
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      final rel = f.path.substring(root.path.length + 1).replaceAll(r'\', '/');
      final generated = rel.startsWith('build/') || rel.startsWith('.dart_tool/');
      if (rel.startsWith('.git/')) continue;
      if (generated && !_sampledGenerated.contains(rel)) continue;
      files['lumina_plugin_pcg/$rel'] = f.readAsBytesSync();
    }
    return files;
  }

  test('the real folder zip uploads; build/ and .dart_tool/ are left out and reported', () async {
    final files = realFolder();
    expect(files.keys, containsAll(['lumina_plugin_pcg/.gitignore', 'lumina_plugin_pcg/.metadata', 'lumina_plugin_pcg/LICENSE',
        'lumina_plugin_pcg/pubspec.lock', 'lumina_plugin_pcg/.dart_tool/version',
        'lumina_plugin_pcg/build/native_assets/windows/flutter_assimp.dll']));
    final upload = await publisher.upload(rawZip(files), fileName: 'lumina_plugin_pcg.zip', category: ListingCategory.plugin);

    expect(upload.skippedPaths, ['lumina_plugin_pcg/.dart_tool/', 'lumina_plugin_pcg/build/']);
    expect(upload.skippedFileCount, files.keys.where((p) => p.contains('/build/') || p.contains('/.dart_tool/')).length);
    final paths = upload.files.map((f) => f.path).toList();
    expect(paths, containsAll(['lumina_plugin_pcg/.gitignore', 'lumina_plugin_pcg/LICENSE', 'lumina_plugin_pcg/test/pcg_graph_test.dart']));
    expect(paths.where((p) => p.contains('/build/') || p.contains('/.dart_tool/')), isEmpty);

    final plugin = upload.plugin!;
    expect(plugin.title, 'Procedural Content Generation');
    expect(plugin.tags, ['procedural', 'plugin']);
    expect(plugin.minEngineVersion, '0.0.1');
    expect(plugin.license!.code, 'MIT');
    expect(plugin.releaseNotes, startsWith('- Initial release'));

    // The stored archive is the package without the generated folders.
    final listing = await publisher.createListing(NewListing(category: ListingCategory.plugin, title: plugin.title));
    final terms = await publisher.terms();
    await publisher.publishVersion(listing.id, NewVersion(version: '0.1.0', uploadId: upload.id,
        licenses: const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT'), attestation: true, termsVersion: terms.version));
    final manifest = await publisher.manifest(listing.id, '0.1.0');
    final stored = ZipDecoder().decodeBytes(await publisher.downloadUrl(manifest.archiveUrl));
    expect(stored.files.where((f) => f.isFile).map((f) => f.name).toSet(), paths.toSet());
    expect(manifest.archiveSha256, upload.sha256);
  }, skip: builtSkip);

  test('files outside the generated folders keep the allow-list; the refusal names every offending path', () async {
    final files = realFolder()
      ..['lumina_plugin_pcg/tools/run.exe'] = [0x4D, 0x5A, 0x90, 0]
      ..['lumina_plugin_pcg/lib/native/libpcg.so'] = [0x7F, 0x45, 0x4C, 0x46]
      ..['lumina_plugin_pcg/Makefile'] = [0x61];
    try {
      await publisher.upload(rawZip(files), fileName: 'pcg.zip', category: ListingCategory.plugin);
      fail('accepted an executable');
    } on MarketplaceException catch (e) {
      expect(e.statusCode, 422);
      expect(e.code, 'invalid_archive');
      expect(e.message, contains('lumina_plugin_pcg/tools/run.exe'));
      expect(e.message, contains('lumina_plugin_pcg/lib/native/libpcg.so'));
      expect(e.message, contains('lumina_plugin_pcg/Makefile'));
      expect(e.details['paths'], unorderedEquals(
          ['lumina_plugin_pcg/Makefile', 'lumina_plugin_pcg/lib/native/libpcg.so', 'lumina_plugin_pcg/tools/run.exe']));
    }
  }, skip: pcgSkip);

  test('without the plugin category nothing is skipped, and the refusal still names the path', () async {
    try {
      await publisher.upload(rawZip(realFolder()), fileName: 'pcg.zip');
      fail('accepted build output without the plugin category');
    } on MarketplaceException catch (e) {
      expect(e.code, 'invalid_archive');
      expect(e.message, contains('lumina_plugin_pcg/build/native_assets/windows/flutter_assimp.dll'));
    }
  }, skip: builtSkip);
}

/// Real generated files of lumina_plugin_pcg's build/ and .dart_tool/.
const _sampledGenerated = {
  'build/native_assets/windows/flutter_assimp.dll',
  'build/native_assets/windows/native_assets.json',
  '.dart_tool/version',
  '.dart_tool/package_config.json',
  '.dart_tool/package_graph.json',
};
