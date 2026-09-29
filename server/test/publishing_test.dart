import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  late TestServer server;
  late MarketplaceClient publisher;
  late Terms terms;

  setUp(() async {
    server = await TestServer.start();
    publisher = server.client();
    await signUp(publisher, username: 'maker');
    terms = await publisher.terms();
  });

  Future<(Listing, UploadInfo)> draft({ListingCategory category = ListingCategory.model, List<int>? zip}) async {
    final listing = await publisher.createListing(NewListing(category: category, title: 'Barrels ${category.wire}'));
    final upload = await publisher.upload(zip ?? propsZip('Barrels', limit: 2), fileName: 'barrels.zip');
    return (listing, upload);
  }

  NewVersion version(UploadInfo upload, {LicenseSelection licenses = const LicenseSelection(content: 'CC0-1.0'), bool attest = true}) =>
      NewVersion(version: '1.0.0', uploadId: upload.id, licenses: licenses, attestation: attest, termsVersion: terms.version);

  test('publishing a model version with CC0-1.0 and the attestation succeeds', () async {
    final (listing, upload) = await draft();
    expect(listing.status, ListingStatus.draft);
    expect(upload.files.map((f) => f.path), ['bent_barrel.glb', 'dented_barrel.glb']);
    expect(upload.detectedLicenseKinds, {LicenseKind.content});

    final v = await publisher.publishVersion(listing.id, version(upload));
    expect(v.version, '1.0.0');
    expect(v.licenses.content, 'CC0-1.0');
    expect(v.fileCount, 2);
    final page = await publisher.listing(listing.id);
    expect(page.status, ListingStatus.published);
    expect(page.latestVersion!.id, v.id);
    expect(page.licenses.content, 'CC0-1.0');
    expect(page.versions!.single.version, '1.0.0');

    // The attestation is stored with who, when, an IP hash and the terms version.
    final attestation = server.server.services.attestations.forVersion(v.id)!;
    expect(attestation.userId, page.publisher.id);
    expect(attestation.termsVersion, terms.version);
    expect(attestation.listingId, listing.id);
    expect(attestation.ipHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(attestation.ipHash, isNot(contains('127.0.0.1')));
    expect(attestation.statement, terms.attestationStatement);
  });

  test('without the attestation → 422', () async {
    final (listing, upload) = await draft();
    await expectLater(publisher.publishVersion(listing.id, version(upload, attest: false)),
        throwsApi(422, 'attestation_required'));
    final stale = NewVersion(
        version: '1.0.0', uploadId: upload.id, licenses: const LicenseSelection(content: 'CC0-1.0'),
        attestation: true, termsVersion: '1999-01-01');
    await expectLater(publisher.publishVersion(listing.id, stale), throwsApi(422, 'attestation_required'),
        reason: 'the attestation must be against the current terms');
    expect((await publisher.listing(listing.id)).status, ListingStatus.draft);
  });

  test('with "Proprietary" → 422; a code license in the content slot → 422', () async {
    final (listing, upload) = await draft();
    await expectLater(
        publisher.publishVersion(listing.id, version(upload, licenses: const LicenseSelection(content: 'Proprietary'))),
        throwsApi(422, 'license_unknown'));
    await expectLater(
        publisher.publishVersion(listing.id, version(upload, licenses: const LicenseSelection(content: 'MIT'))),
        throwsApi(422, 'license_wrong_kind'));
    await expectLater(publisher.publishVersion(listing.id, version(upload, licenses: const LicenseSelection())),
        throwsApi(422, 'license_required'));
  });

  test('a plugin with only a content license → 422 (needs a code license); with both it publishes', () async {
    final pluginZip = rawZip({
      // A plugin version needs its package manifest.
      'my_plugin/my_plugin.lmplugin': utf8.encode('{"name": "my_plugin", "version": "1.0.0"}'),
      'my_plugin/pubspec.yaml': utf8.encode('name: my_plugin\n'),
      'my_plugin/lib/my_plugin.dart': utf8.encode('void main() {}\n'),
      'my_plugin/assets/icon.png': File(logoPng).readAsBytesSync(),
    });
    final (listing, upload) = await draft(category: ListingCategory.plugin, zip: pluginZip);
    expect(upload.detectedLicenseKinds, {LicenseKind.code, LicenseKind.content});
    final err = publisher.publishVersion(listing.id, version(upload, licenses: const LicenseSelection(content: 'CC0-1.0')));
    await expectLater(err, throwsA(isA<MarketplaceException>()
        .having((e) => e.code, 'code', 'license_required')
        .having((e) => (e.details['problems'] as List).single['kind'], 'kind', 'code')));
    final v = await publisher.publishVersion(
        listing.id, version(upload, licenses: const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT')));
    expect(v.licenses.code, 'MIT');
    expect(v.licenses.content, 'CC-BY-4.0');
  });

  test('a model zip that contains code needs a code license too', () async {
    final mixed = rawZip({
      'barrel.glb': File('$testAssetsDir/Props/Barrels/radbarrel.glb').readAsBytesSync(),
      'scripts/spin.dart': utf8.encode('// spins the barrel\n'),
    });
    final (listing, upload) = await draft(zip: mixed);
    await expectLater(publisher.publishVersion(listing.id, version(upload)), throwsApi(422, 'license_required'));
    await publisher.publishVersion(listing.id, version(upload, licenses: const LicenseSelection(content: 'CC0-1.0', code: 'Zlib')));
  });

  test('a listing with priceCents: 500 is refused (free-only for now)', () async {
    await expectLater(
      publisher.createListing(const NewListing(category: ListingCategory.model, title: 'Paid barrels', priceCents: 500)),
      throwsApi(422, 'price_not_supported'),
    );
    final free = await publisher.createListing(const NewListing(category: ListingCategory.model, title: 'Free barrels'));
    expect(free.priceCents, 0);
    expect(free.isFree, isTrue);
  });

  test('upload of a zip containing ../evil is rejected; download returns the exact bytes uploaded', () async {
    for (final evil in ['../evil.glb', 'meshes/../../evil.glb', '/etc/evil.glb', r'..\evil.glb']) {
      await expectLater(publisher.upload(rawZip({evil: [1, 2, 3]}), fileName: 'evil.zip'), throwsApi(422, 'invalid_archive'),
          reason: evil);
    }
    await expectLater(publisher.upload(rawZip({'run.exe': [1, 2, 3]}), fileName: 'x.zip'), throwsApi(422, 'invalid_archive'),
        reason: 'disallowed extension');
    await expectLater(publisher.upload(utf8.encode('this is not a zip'), fileName: 'x.zip'), throwsApi(422, 'invalid_archive'));

    final zip = propsZip('Barrels');
    final (listing, _) = await draft();
    final upload = await publisher.upload(zip, fileName: 'barrels.zip');
    expect(upload.size, zip.length);
    await publisher.publishVersion(listing.id, version(upload));
    await publisher.getListing(listing.id);
    final downloaded = await publisher.downloadArchive(listing.id, '1.0.0');
    expect(downloaded, zip);

    // Blobs are content-addressed on disk.
    final blob = File('${server.root.path}/storage/blobs/${upload.sha256.substring(0, 2)}/${upload.sha256}');
    expect(blob.readAsBytesSync(), zip);
  });

  test('uploads over the size limit are refused with 413', () async {
    final small = await TestServer.start(maxUploadBytes: 1024);
    final c = small.client();
    await signUp(c);
    await expectLater(c.upload(propsZip('Barrels', limit: 1), fileName: 'big.zip'), throwsApi(413, 'payload_too_large'));
  });

  test('versions, screenshots, owner-only edits and unlist/relist', () async {
    final (listing, upload) = await draft();
    await publisher.publishVersion(listing.id, version(upload));
    await expectLater(publisher.publishVersion(listing.id, version(upload)), throwsApi(409),
        reason: 'the upload was consumed');
    final upload2 = await publisher.upload(propsZip('Barrels', limit: 3), fileName: 'barrels.zip');
    await expectLater(
        publisher.publishVersion(listing.id, NewVersion(
            version: '1.0.0', uploadId: upload2.id, licenses: const LicenseSelection(content: 'CC0-1.0'),
            attestation: true, termsVersion: terms.version)),
        throwsApi(409, 'conflict'), reason: 'duplicate version number');
    await publisher.publishVersion(listing.id, NewVersion(
        version: '1.1.0', uploadId: upload2.id, licenses: const LicenseSelection(content: 'CC-BY-4.0'),
        attestation: true, termsVersion: terms.version, releaseNotes: 'Adds the empty barrel.'));
    final page = await publisher.listing(listing.id);
    expect(page.versions!.map((v) => v.version), ['1.1.0', '1.0.0']);
    expect(page.latestVersion!.releaseNotes, 'Adds the empty barrel.');
    expect(page.licenses.content, 'CC-BY-4.0');

    final shot = File(logoPng).readAsBytesSync();
    final withShot = await publisher.addScreenshot(listing.id, shot);
    expect(withShot.screenshots, hasLength(1));
    expect((await http.get(publisher.resolve(withShot.screenshots.single))).bodyBytes, shot);
    expect((await publisher.removeScreenshot(listing.id, 0)).screenshots, isEmpty);

    final edited = await publisher.updateListing(listing.id, title: 'Barrel Collection', tags: ['barrel', 'prop']);
    expect(edited.title, 'Barrel Collection');
    expect(edited.tags, ['barrel', 'prop']);

    final stranger = server.client();
    await signUp(stranger);
    await expectLater(stranger.updateListing(listing.id, title: 'Mine now'), throwsApi(403, 'forbidden'));
    await expectLater(stranger.publishVersion(listing.id, version(upload2)), throwsApi(403, 'forbidden'));
    await expectLater(server.client().createListing(const NewListing(category: ListingCategory.model, title: 'x')),
        throwsApi(401, 'unauthorized'));

    expect((await publisher.unlist(listing.id)).status, ListingStatus.unlisted);
    await expectLater(stranger.listing(listing.id), throwsApi(404));
    expect((await publisher.listing(listing.id)).status, ListingStatus.unlisted, reason: 'the owner still sees it');
    expect((await publisher.relist(listing.id)).status, ListingStatus.published);
    expect((await publisher.myListings()).map((l) => l.id), contains(listing.id));
  });

  test('theme listings take a .json file', () async {
    final listing = await publisher.createListing(const NewListing(category: ListingCategory.theme, title: 'Ember'));
    final theme = utf8.encode(jsonEncode({'name': 'Ember', 'version': 1, 'colors': {'primary': '#FB7C01'}}));
    final upload = await publisher.upload(theme, fileName: 'ember.json');
    expect(upload.kind, 'json');
    expect(upload.files.single.path, 'ember.json');
    await publisher.publishVersion(listing.id, version(upload));
    await expectLater(publisher.upload(utf8.encode('{not json'), fileName: 'bad.json'), throwsApi(422, 'invalid_archive'));
  });

  test('attestations are stored immutably', () async {
    final (listing, upload) = await draft();
    final v = await publisher.publishVersion(listing.id, version(upload));
    final db = server.server.services.database;
    expect(() => db.execute("UPDATE attestations SET terms_version = 'forged' WHERE version_id = ?", [v.id]),
        throwsA(anything));
    expect(() => db.execute('DELETE FROM attestations WHERE version_id = ?', [v.id]), throwsA(anything));
    expect(server.server.services.attestations.forVersion(v.id)!.termsVersion, terms.version);
  });
}
