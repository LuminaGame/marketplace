import 'dart:convert';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

/// Plugin versions are read from the package's `.lmplugin` manifest
/// (the workspace's real lumina_plugin_pcg), its license and its changelog —
/// on upload (`?category=plugin`, the web publish flow) and again at publish.
void main() {
  final pcgSkip = skipUnlessPlugin('lumina_plugin_pcg');
  late TestServer server;
  late MarketplaceClient publisher;
  late Terms terms;

  setUp(() async {
    server = await TestServer.start();
    publisher = server.client();
    await signUp(publisher, username: 'pcg_maker');
    terms = await publisher.terms();
  });

  NewVersion version(UploadInfo upload, {String version = '0.1.0', LicenseSelection? licenses, String releaseNotes = ''}) =>
      NewVersion(
        version: version,
        uploadId: upload.id,
        licenses: licenses ?? const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT'),
        attestation: true,
        termsVersion: terms.version,
        releaseNotes: releaseNotes,
      );

  Matcher refusedPlugin(String problem, {String? path}) => throwsA(isA<MarketplaceException>()
      .having((e) => e.statusCode, 'statusCode', 422)
      .having((e) => e.code, 'code', kInvalidPluginErrorCode)
      .having((e) => e.details['problem'], 'problem', problem)
      .having((e) => e.details['path'], 'path', path ?? anything));

  test('an upload with ?category=plugin returns what the package declares', () async {
    final zip = rawZip(pcgPluginFiles(manifestExtra: {'license': 'MIT'}, license: mitLicenseText));
    final upload = await publisher.upload(zip, fileName: 'lumina_plugin_pcg.zip', category: ListingCategory.plugin);
    final plugin = upload.plugin!;
    expect(plugin.name, 'lumina_plugin_pcg');
    expect(plugin.title, 'Procedural Content Generation');
    expect(plugin.version, '0.1.0');
    expect(plugin.description, startsWith('PCG Graph assets and PCG Volume actors'));
    expect(plugin.tags, ['procedural', 'plugin']);
    expect(plugin.minEngineVersion, '0.0.1');
    expect(plugin.license!.code, 'MIT');
    expect(plugin.license!.source, PluginLicenseSource.manifest);
    expect(plugin.license!.fileName, 'lumina_plugin_pcg.lmplugin');
    expect(plugin.releaseNotes, startsWith('- Initial release'));
    expect(plugin.changelog, startsWith('## Unreleased'));
    expect(upload.detectedLicenseKinds, {LicenseKind.code, LicenseKind.content}, reason: 'resources/icon128.png is content');

    // Without the category the upload is plain (older clients).
    final plain = await publisher.upload(zip, fileName: 'lumina_plugin_pcg.zip');
    expect(plain.plugin, isNull);
  }, skip: pcgSkip);

  test('broken packages are refused on upload with 422 invalid_plugin naming the problem', () async {
    // The package as it was before 7d66ca2: no "license" key, LICENSE "All rights reserved".
    final nonFree = pcgPluginFiles(manifestExtra: {'license': null}, license: allRightsReservedText);
    await expectLater(
        publisher.upload(rawZip(nonFree), fileName: 'pcg.zip', category: ListingCategory.plugin),
        refusedPlugin('license_not_free', path: 'lumina_plugin_pcg/LICENSE'));
    try {
      await publisher.upload(rawZip(nonFree), fileName: 'pcg.zip', category: ListingCategory.plugin);
    } on MarketplaceException catch (e) {
      expect(e.message, startsWith('The plugin package was refused: LICENSE reads "All rights reserved"'));
    }
    final noManifest = pcgPluginFiles(license: mitLicenseText)..remove('lumina_plugin_pcg/lumina_plugin_pcg.lmplugin');
    await expectLater(publisher.upload(rawZip(noManifest), fileName: 'pcg.zip', category: ListingCategory.plugin),
        refusedPlugin('no_manifest'));
  }, skip: pcgSkip);

  test('publish re-checks the package: no manifest, another version, a replaced license → 422', () async {
    final listing = await publisher.createListing(const NewListing(category: ListingCategory.plugin, title: 'PCG'));

    // Uploaded without the category, refused at publish.
    final noManifest = pcgPluginFiles(license: mitLicenseText)..remove('lumina_plugin_pcg/lumina_plugin_pcg.lmplugin');
    final bare = await publisher.upload(rawZip(noManifest), fileName: 'pcg.zip');
    await expectLater(publisher.publishVersion(listing.id, version(bare)), refusedPlugin('no_manifest'));

    final upload = await publisher.upload(rawZip(pcgPluginFiles(manifestExtra: {'license': 'MIT'}, license: mitLicenseText)),
        fileName: 'pcg.zip', category: ListingCategory.plugin);
    await expectLater(
        publisher.publishVersion(listing.id, version(upload, version: '2.0.0')),
        throwsA(isA<MarketplaceException>()
            .having((e) => e.code, 'code', 'version_mismatch')
            .having((e) => e.message, 'message', contains('0.1.0'))));
    await expectLater(
        publisher.publishVersion(listing.id, version(upload, licenses: const LicenseSelection(content: 'CC0-1.0', code: 'Apache-2.0'))),
        throwsA(isA<MarketplaceException>()
            .having((e) => e.code, 'code', 'license_mismatch')
            .having((e) => e.message, 'message', contains('MIT'))));
    expect((await publisher.listing(listing.id)).status, ListingStatus.draft);
  }, skip: pcgSkip);

  test('the package publishes: release notes from the changelog, engine version from the manifest, '
      'installed under plugins/<name>/ with or without a top folder', () async {
    final listing = await publisher.createListing(const NewListing(
        category: ListingCategory.plugin, title: 'Procedural Content Generation', engineVersion: '0.0.1'));
    final upload = await publisher.upload(rawZip(pcgPluginFiles(manifestExtra: {'license': 'MIT'}, license: mitLicenseText)),
        fileName: 'pcg.zip', category: ListingCategory.plugin);
    final v = await publisher.publishVersion(listing.id, version(upload));
    expect(v.version, '0.1.0');
    expect(v.licenses.ids, ['CC-BY-4.0', 'MIT']);
    expect(v.releaseNotes, upload.plugin!.releaseNotes);
    expect(v.releaseNotes, contains('`pcg.generate` console command'));
    expect(v.engineVersion, '0.0.1');
    final manifest = await publisher.manifest(listing.id, '0.1.0');
    expect(manifest.targetRoot, 'plugins/lumina_plugin_pcg/');
    expect(manifest.files.map((f) => f.target), contains('plugins/lumina_plugin_pcg/lumina_plugin_pcg.lmplugin'));

    // Explicit release notes win over the changelog.
    final flat = await publisher.createListing(const NewListing(category: ListingCategory.plugin, title: 'PCG Tools'));
    final flatUpload = await publisher.upload(
        rawZip(pcgPluginFiles(manifestExtra: {'license': 'CC-BY-4.0 AND MIT'}, license: mitLicenseText, top: null)),
        fileName: 'pcg_flat.zip',
        category: ListingCategory.plugin);
    expect(flatUpload.plugin!.topFolder, isNull);
    final flatVersion = await publisher.publishVersion(flat.id, version(flatUpload, releaseNotes: 'Hand-written notes.'));
    expect(flatVersion.releaseNotes, 'Hand-written notes.');
    final flatManifest = await publisher.manifest(flat.id, '0.1.0');
    expect(flatManifest.targetRoot, 'plugins/lumina_plugin_pcg/', reason: 'named by the root .lmplugin, not the title');
    expect(flatManifest.files.map((f) => f.target), contains('plugins/lumina_plugin_pcg/lumina_plugin_pcg.lmplugin'));
    expect(jsonEncode(flatManifest.toJson()), isNot(contains('pcg_tools')));
  }, skip: pcgSkip);
}
