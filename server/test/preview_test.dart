import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

/// The preview model each model version gets at publish time, and
/// the public route that serves it to the listing page's 3D view.

Uint8List _asset(String path) => File('$testAssetsDir/Props/$path').readAsBytesSync();

Map<String, List<int>> _folder(String folder) => {
      for (final f in Directory('$testAssetsDir/Props/$folder').listSync().whereType<File>())
        if (f.path.endsWith('.glb')) f.uri.pathSegments.last: f.readAsBytesSync(),
    };

/// The JSON and BIN chunks of a GLB.
(Map<String, Object?>, Uint8List) _chunks(List<int> glb) {
  final data = ByteData.sublistView(Uint8List.fromList(glb));
  expect(data.getUint32(0, Endian.little), 0x46546C67, reason: 'glTF magic');
  expect(data.getUint32(4, Endian.little), 2);
  expect(data.getUint32(8, Endian.little), glb.length, reason: 'declared length');
  final jsonLength = data.getUint32(12, Endian.little);
  expect(data.getUint32(16, Endian.little), 0x4E4F534A, reason: 'JSON chunk');
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength))) as Map<String, Object?>;
  var bin = Uint8List(0);
  final binAt = 20 + jsonLength;
  if (binAt < glb.length) {
    final binLength = data.getUint32(binAt, Endian.little);
    expect(data.getUint32(binAt + 4, Endian.little), 0x004E4942, reason: 'BIN chunk');
    bin = Uint8List.fromList(glb.sublist(binAt + 8, binAt + 8 + binLength));
  }
  return (json, bin);
}

/// A real mesh (the seeded short banana bunch) unpacked into a `.gltf` with
/// an external `.bin` and its texture as a separate `.webp`, the way many
/// exporters write glTF.
Map<String, List<int>> _unpackedGltf(String dir) {
  final (json, bin) = _chunks(_asset('Banana Bunch/banana_bunch_short.glb'));
  final views = (json['bufferViews'] as List).cast<Map<String, Object?>>();
  final files = <String, List<int>>{};
  final images = (json['images'] as List).cast<Map<String, Object?>>();
  for (var i = 0; i < images.length; i++) {
    final view = views[images[i]['bufferView'] as int];
    final offset = view['byteOffset'] as int? ?? 0;
    final name = 'textures/banana_$i.webp';
    files['$dir/$name'] = bin.sublist(offset, offset + (view['byteLength'] as int));
    images[i]
      ..remove('bufferView')
      ..remove('mimeType')
      ..['uri'] = name;
  }
  (json['buffers'] as List).cast<Map<String, Object?>>().single['uri'] = 'banana.bin';
  files['$dir/banana.bin'] = bin;
  files['$dir/banana.gltf'] = utf8.encode(jsonEncode(json));
  return files;
}

List<int> _lmas(String type, List<int>? payload) => [
      ...ascii.encode('LMAS'),
      ...utf8.encode(jsonEncode({
        'asset_id': 'a1',
        'name': 'Banana',
        'type': type,
        'has_thumbnail': false,
        'raw_mat_source': '',
        'references': [],
        'metadata': {},
        'thumbnail_png': null,
        'raw_payload': payload == null ? null : base64Encode(payload),
      })),
    ];

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  group('derivePreviewModel', () {
    test('picks the largest GLB of an archive (the seeded Banana Bunch → banana_bunch_short.glb)', () {
      final preview = derivePreviewModel(_folder('Banana Bunch'), maxBytes: 32 << 20)!;
      expect(preview.sourcePath, 'banana_bunch_short.glb');
      expect(preview.kind, PreviewSourceKind.glb);
      expect(preview.bytes.length, 58364);
      expect(_sha(preview.bytes), _sha(_asset('Banana Bunch/banana_bunch_short.glb')));
    });

    test('packs a .gltf with an external .bin and texture into one self-contained GLB', () {
      final files = _unpackedGltf('pack');
      final preview = derivePreviewModel(files, maxBytes: 32 << 20)!;
      expect(preview.sourcePath, 'pack/banana.gltf');
      expect(preview.kind, PreviewSourceKind.gltf);
      final (json, bin) = _chunks(preview.bytes);
      final buffers = (json['buffers'] as List).cast<Map<String, Object?>>();
      expect(buffers, hasLength(1));
      expect(buffers.single.containsKey('uri'), isFalse, reason: 'the GLB BIN chunk holds the buffer');
      final original = files['pack/banana.bin']!;
      expect(bin.sublist(0, original.length), original, reason: 'the external buffer comes first, unchanged');
      final image = (json['images'] as List).cast<Map<String, Object?>>().single;
      expect(image.containsKey('uri'), isFalse);
      expect(image['mimeType'], 'image/webp');
      final view = (json['bufferViews'] as List).cast<Map<String, Object?>>()[image['bufferView'] as int];
      final offset = view['byteOffset'] as int;
      expect(offset % 4, 0);
      expect(bin.sublist(offset, offset + (view['byteLength'] as int)), files['pack/textures/banana_0.webp']);
    });

    test('a .gltf that points outside the archive or at a missing file is no candidate', () {
      final files = _unpackedGltf('pack')..remove('pack/banana.bin');
      expect(derivePreviewModel(files, maxBytes: 32 << 20), isNull);
      final escaping = _unpackedGltf('pack');
      final json = jsonDecode(utf8.decode(escaping['pack/banana.gltf']!)) as Map<String, Object?>;
      (json['buffers'] as List).cast<Map<String, Object?>>().single['uri'] = '../../banana.bin';
      escaping['pack/banana.gltf'] = utf8.encode(jsonEncode(json));
      expect(derivePreviewModel(escaping, maxBytes: 32 << 20), isNull);
    });

    test('a mesh .lmas carries its GLB payload; its .entity.glb companion wins when present', () {
      final glb = _asset('JerryCan/jerrycan_blue.glb');
      final lmas = derivePreviewModel({'meshes/JerryCan.lmas': _lmas('filamesh', glb)}, maxBytes: 32 << 20)!;
      expect(lmas.sourcePath, 'meshes/JerryCan.lmas');
      expect(lmas.kind, PreviewSourceKind.lmas);
      expect(lmas.bytes, glb);

      final both = derivePreviewModel({
        'meshes/JerryCan.lmas': _lmas('filamesh', glb),
        'meshes/JerryCan.entity.glb': glb,
      }, maxBytes: 32 << 20)!;
      expect(both.sourcePath, 'meshes/JerryCan.entity.glb');
      expect(derivePreviewModel({'textures/T.lmas': _lmas('texture', glb)}, maxBytes: 32 << 20), isNull,
          reason: 'only mesh assets');
      expect(derivePreviewModel({'meshes/Empty.lmas': _lmas('filamesh', null)}, maxBytes: 32 << 20), isNull);
    });

    test('no mesh, broken GLBs and the size limit', () {
      expect(derivePreviewModel({'README.md': utf8.encode('# hi'), 'tex.jpg': File('seed/screenshots/chair.jpg').readAsBytesSync()}, maxBytes: 32 << 20),
          isNull);
      expect(derivePreviewModel({'fake.glb': utf8.encode('not a glb at all, just text')}, maxBytes: 32 << 20), isNull);
      final truncated = _asset('Chair/chair.glb').sublist(0, 4000);
      expect(derivePreviewModel({'chair.glb': truncated}, maxBytes: 32 << 20), isNull, reason: 'declared length ≠ size');

      final files = _folder('Barrels'); // 29–41 KB each; lootbarrel_junk.glb is the largest
      expect(derivePreviewModel(files, maxBytes: 64 << 10)!.sourcePath, 'lootbarrel_junk.glb');
      expect(derivePreviewModel(files, maxBytes: 32 << 10)!.sourcePath, 'dented_barrel.glb',
          reason: 'the largest that fits (31 240 bytes)');
      expect(derivePreviewModel(files, maxBytes: 20 << 10), isNull, reason: 'none fits');
    });
  });

  group('publishing and serving', () {
    test('model versions carry a preview; the theme does not', () async {
      final server = await TestServer.start();
      await server.seed();
      final c = server.client();
      final banana = await c.listing('banana-bunch');
      final v = banana.latestVersion!;
      expect(v.previewModelSource, 'banana_bunch_short.glb');
      expect(v.previewModelSize, 58364);
      expect(v.previewModelSha256, _sha(_asset('Banana Bunch/banana_bunch_short.glb')));
      expect(v.previewModelUrl, '/api/v1/listings/${banana.id}/versions/1.0.0/preview.glb');
      expect(banana.previewModelUrl, v.previewModelUrl);
      expect(banana.versions!.single.previewModelUrl, v.previewModelUrl);
      // Search cards carry it too.
      final card = (await c.search(const SearchQuery(q: 'banana'))).items.single;
      expect(card.previewModelUrl, v.previewModelUrl);

      final theme = (await c.search(const SearchQuery(category: ListingCategory.theme))).items.single;
      expect(theme.previewModelUrl, isNull);
      expect(theme.latestVersion!.previewModelUrl, isNull);
    });

    test('GET …/preview.glb is public, exact, cached and revalidated; it is not a download', () async {
      final server = await TestServer.start();
      await server.seed();
      final c = server.client();
      final banana = await c.listing('banana-bunch');
      final url = c.resolve(banana.previewModelUrl!);
      final r = await http.get(url);
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'model/gltf-binary');
      expect(r.bodyBytes, _asset('Banana Bunch/banana_bunch_short.glb'));
      expect(r.headers['x-content-sha256'], banana.latestVersion!.previewModelSha256);
      expect(r.headers['etag'], '"${banana.latestVersion!.previewModelSha256}"');
      expect(r.headers['cache-control'], 'public, max-age=86400');
      expect(r.headers['x-content-type-options'], 'nosniff');

      final cached = await http.get(url, headers: {'if-none-match': r.headers['etag']!});
      expect(cached.statusCode, 304);
      expect(cached.bodyBytes, isEmpty);
      // By slug too.
      expect((await http.get(c.resolve('/api/v1/listings/banana-bunch/versions/1.0.0/preview.glb'))).statusCode, 200);

      expect((await c.listing('banana-bunch')).downloadCount, banana.downloadCount, reason: 'previews are not downloads');
      final missing = await http.get(c.resolve('/api/v1/listings/banana-bunch/versions/9.9.9/preview.glb'));
      expect(missing.statusCode, 404);
    });

    test('the listing\'s visibility applies; a version without a mesh has no preview', () async {
      final server = await TestServer.start();
      final owner = server.client();
      await signUp(owner, username: 'maker');
      final (listing, _) = await publish(owner, title: 'Cans', zip: propsZip('JerryCan'));
      final url = owner.resolve(listing.previewModelUrl!);
      expect(listing.latestVersion!.previewModelSource, 'jerrycan_yellow.glb');
      expect((await http.get(url)).statusCode, 200);

      await owner.unlist(listing.id);
      final stranger = await http.get(url);
      expect(stranger.statusCode, 404, reason: 'an unlisted listing is hidden from strangers');
      final asOwner = await http.get(url, headers: {'authorization': 'Bearer ${owner.accessToken}'});
      expect(asOwner.statusCode, 200);

      final (textures, _) = await publish(owner, title: 'Just a texture', zip: rawZip({'tex.jpg': File('seed/screenshots/chair.jpg').readAsBytesSync()}));
      expect(textures.previewModelUrl, isNull);
      final none = await http.get(owner.resolve('/api/v1/listings/${textures.id}/versions/1.0.0/preview.glb'));
      expect(none.statusCode, 404);
      expect(jsonDecode(none.body)['error']['code'], 'no_preview');

      // A plugin ships meshes too, but only model listings get a 3D view.
      final (plugin, _) = await publish(owner,
          title: 'Mesh tools',
          category: ListingCategory.plugin,
          zip: rawZip({
            'mesh_tools/mesh_tools.lmplugin': utf8.encode('{"name": "mesh_tools", "version": "1.0.0"}'),
            'mesh_tools/lib/a.dart': utf8.encode('void main() {}'),
            'mesh_tools/demo.glb': _asset('Chair/chair.glb')}),
          licenses: const LicenseSelection(content: 'CC0-1.0', code: 'MIT'));
      expect(plugin.previewModelUrl, isNull);
    });

    test('versions published before previews existed are backfilled on start-up', () async {
      final root = Directory.systemTemp.createTempSync('mkt_preview_backfill_');
      addTearDown(() => root.deleteSync(recursive: true));
      MarketplaceConfig config() => MarketplaceConfig(
            port: 0,
            databasePath: '${root.path}/marketplace.db',
            storageDir: '${root.path}/storage',
            jwtSecret: 'test-secret-that-is-at-least-32-characters-long',
          );
      var server = await MarketplaceServer.start(config(), log: MarketplaceLog.silent());
      await seedSampleContent(server.services,
          testAssetsDir: testAssetsDir, adminPassword: 'seed-admin-password', moderatorPassword: 'seed-moderator-password');
      await server.close();

      // What a database from before migration 2 holds: no preview on any version.
      final db = sqlite3.open('${root.path}/marketplace.db');
      db.execute('UPDATE listing_versions SET preview_state = NULL, preview_sha256 = NULL, preview_size = NULL, preview_source = NULL');
      db.close();

      server = await MarketplaceServer.start(config(), log: MarketplaceLog.silent());
      addTearDown(server.close);
      await server.previewBackfill;
      final c = MarketplaceClient(baseUrl: server.url);
      addTearDown(c.close);
      final barrel = await c.listing('barrel');
      expect(barrel.latestVersion!.previewModelSource, 'lootbarrel_junk.glb');
      expect((await http.get(c.resolve(barrel.previewModelUrl!))).bodyBytes, _asset('Barrels/lootbarrel_junk.glb'));
      final theme = (await c.search(const SearchQuery(category: ListingCategory.theme))).items.single;
      expect(theme.previewModelUrl, isNull);
      final states = sqlite3.open('${root.path}/marketplace.db');
      addTearDown(states.close);
      expect(states.select('SELECT COUNT(*) AS n FROM listing_versions WHERE preview_state IS NULL').single['n'], 0);
    });
  });

  test('the web app\'s flutter_filament module is served with its MIME types, an ETag and a day of caching', () async {
    final web = Directory.systemTemp.createTempSync('mkt_web_filament_');
    addTearDown(() => web.deleteSync(recursive: true));
    File('${web.path}/index.html').writeAsStringSync('<html>marketplace</html>');
    Directory('${web.path}/filament').createSync();
    // The real module when it is built; its bytes do not matter here.
    final wasm = File('$engineDir/flutter_filament/web/flutter_filament.wasm');
    final wasmBytes = wasm.existsSync() ? wasm.readAsBytesSync() : Uint8List.fromList([0, 0x61, 0x73, 0x6D, 1, 0, 0, 0]);
    File('${web.path}/filament/flutter_filament.wasm').writeAsBytesSync(wasmBytes);
    File('${web.path}/filament/flutter_filament.js').writeAsStringSync('var FlutterFilament = () => {};');
    final server = await TestServer.start(webDir: web.path);

    final r = await http.get(server.url.resolve('filament/flutter_filament.wasm'));
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'application/wasm');
    expect(r.bodyBytes.length, wasmBytes.length);
    expect(r.headers['cache-control'], 'public, max-age=86400');
    final etag = r.headers['etag'];
    expect(etag, isNotNull);
    final again = await http.get(server.url.resolve('filament/flutter_filament.wasm'), headers: {'if-none-match': etag!});
    expect(again.statusCode, 304);
    final js = await http.get(server.url.resolve('filament/flutter_filament.js'));
    expect(js.headers['content-type'], startsWith('text/javascript'));
    expect(js.headers['cache-control'], 'public, max-age=86400');
    expect((await http.get(server.url)).headers['cache-control'], 'no-cache', reason: 'index.html is always revalidated');
  });
}
