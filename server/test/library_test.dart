import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  test('GET /library lists a listing after "get"; its install manifest lists every file under contents/Marketplace/<Publisher>/<Listing>/', () async {
    final server = await TestServer.start();
    await server.seed();
    final user = server.client();
    await signUp(user, username: 'gamer');

    final barrel = await user.listing('barrel');
    expect(barrel.inLibrary, isFalse);
    await expectLater(user.manifest(barrel.id, '1.0.0'), throwsApi(403, 'not_in_library'));
    await expectLater(user.downloadArchive(barrel.id, '1.0.0'), throwsApi(403, 'not_in_library'));
    await expectLater(server.client().getListing(barrel.id), throwsApi(401));

    final entry = await user.getListing(barrel.id);
    expect(entry.listing.id, barrel.id);
    await user.getListing(barrel.id); // idempotent
    final library = await user.library();
    expect(library.map((e) => e.listing.title), ['Barrel']);
    expect((await user.listing('barrel')).inLibrary, isTrue);

    final manifest = await user.manifest(barrel.id, '1.0.0');
    expect(manifest.formatVersion, 1);
    expect(manifest.installKind, InstallKind.projectContents);
    expect(manifest.publisher.username, 'lumina');
    expect(manifest.folderName, 'Barrel');
    expect(manifest.targetRoot, 'contents/Marketplace/lumina/Barrel/');
    expect(manifest.licenses.single.id, 'CC0-1.0');

    final meshes = Directory('$testAssetsDir/Props/Barrels').listSync().whereType<File>().where((f) => f.path.endsWith('.glb')).toList();
    expect(manifest.files, hasLength(meshes.length));
    for (final mesh in meshes) {
      final name = mesh.uri.pathSegments.last;
      final f = manifest.files.singleWhere((f) => f.path == name);
      expect(f.target, 'contents/Marketplace/lumina/Barrel/$name');
      expect(f.target, startsWith(manifest.targetRoot));
      expect(isSafeRelativePath(f.target), isTrue);
      final bytes = mesh.readAsBytesSync();
      expect(f.size, bytes.length);
      expect(f.sha256, sha256.convert(bytes).toString());
      expect(await user.downloadUrl(f.url), bytes, reason: 'each file downloads individually');
    }

    final archive = await user.downloadUrl(manifest.archiveUrl);
    expect(sha256.convert(archive).toString(), manifest.archiveSha256);
    expect(ZipDecoder().decodeBytes(archive).files.where((f) => f.isFile), hasLength(meshes.length));

    // Themes and plugins get their own install kinds.
    final theme = (await user.search(const SearchQuery(category: ListingCategory.theme))).items.single;
    await user.getListing(theme.id);
    final themeManifest = await user.manifest(theme.id, '1.0.0');
    expect(themeManifest.installKind, InstallKind.theme);
    expect(themeManifest.targetRoot, 'themes/');
    expect(themeManifest.files.single.target, 'themes/lumina_ember.json');
  });
}
