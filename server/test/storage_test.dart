import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('mkt_blob_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('FileSystemBlobStore is content-addressed and enforces a size limit', () async {
    final store = FileSystemBlobStore(root.path);
    final bytes = File('$testAssetsDir/Props/Barrels/radbarrel.glb').readAsBytesSync();
    final ref = await store.put(Stream.value(bytes), maxBytes: bytes.length);
    expect(ref.sha256, sha256.convert(bytes).toString());
    expect(ref.size, bytes.length);
    expect(File('${root.path}/blobs/${ref.sha256.substring(0, 2)}/${ref.sha256}').existsSync(), isTrue);
    expect(await store.readAll(ref.sha256), bytes);
    final again = await store.put(Stream.value(bytes));
    expect(again.sha256, ref.sha256, reason: 'same content, same blob');
    await expectLater(store.put(Stream.value(bytes), maxBytes: bytes.length - 1), throwsA(isA<BlobTooLargeException>()));
    expect(root.listSync(recursive: true).whereType<File>(), hasLength(1), reason: 'no temp file left behind');
    await expectLater(store.readAll('../../etc/passwd'), throwsA(isA<ArgumentError>()));
  });

  test('ZipValidator lists files, detects license kinds and rejects unsafe archives', () {
    const v = ZipValidator(maxUnpackedBytes: 10 * 1024 * 1024);
    final ok = v.validate(rawZip({
      'meshes/barrel.glb': [1, 2, 3],
      'LICENSE': utf8.encode('CC0'),
      'lib/spin.dart': utf8.encode('//'),
    }));
    expect(ok.files.map((f) => f.path), ['LICENSE', 'lib/spin.dart', 'meshes/barrel.glb']);
    expect(ok.detectedKinds, {LicenseKind.content, LicenseKind.code});

    // A Lumina plugin package: its `.lmplugin` manifest is JSON, neither
    // content nor code on its own.
    final plugin = v.validate(rawZip({
      'my_plugin/my_plugin.lmplugin': utf8.encode('{"name": "my_plugin", "version": "0.1.0"}'),
      'my_plugin/pubspec.yaml': utf8.encode('name: my_plugin'),
      'my_plugin/lib/my_plugin.dart': utf8.encode('//'),
    }));
    expect(plugin.files.map((f) => f.path), contains('my_plugin/my_plugin.lmplugin'));
    expect(plugin.detectedKinds, {LicenseKind.code});

    for (final bad in ['../evil.glb', 'a/../../evil.glb', '/abs.glb', r'..\evil.glb', 'C:/x.glb', 'virus.exe', 'x.sh']) {
      expect(() => v.validate(rawZip({bad: [1]})), throwsA(isA<InvalidArchiveException>()), reason: bad);
    }
    expect(() => v.validate(rawZip({})), throwsA(isA<InvalidArchiveException>()), reason: 'empty');
    const tiny = ZipValidator(maxUnpackedBytes: 4);
    expect(() => tiny.validate(rawZip({'a.glb': List.filled(10, 0)})), throwsA(isA<InvalidArchiveException>()),
        reason: 'zip bomb guard');
  });
}
