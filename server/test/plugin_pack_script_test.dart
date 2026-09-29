import 'dart:io';

import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

/// The zip a plugin's `tool/pack_plugin.dart` writes is
/// what the marketplace takes as it is — [ZipValidator] skips nothing and
/// repacks nothing, the package check passes, and a real upload through the
/// plugin publish flow returns the manifest. Runs the real script of the
/// plugins checkout ([pluginsDir], read-only; the zips go to a temp dir).
void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('mkt_pack_script_test_'));
  tearDown(() => out.deleteSync(recursive: true));

  /// Packs the workspace plugin [name] with its own script; the zip's bytes.
  Future<List<int>> packed(String name) async {
    final dir = pluginDir(name);
    final res = await Process.run(Platform.resolvedExecutable, ['tool/pack_plugin.dart', '--out', out.path],
        workingDirectory: dir);
    expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
    final zip = out.listSync().whereType<File>().singleWhere((f) => f.path.endsWith('.zip') && f.path.contains(name));
    return zip.readAsBytesSync();
  }

  for (final name in ['lumina_plugin_pcg', 'lumina_plugin_miniai']) {
    test('$name: the packed zip is accepted without skipping anything', () async {
      final bytes = await packed(name);

      final validated = const ZipValidator(maxUnpackedBytes: 2 * 1024 * 1024 * 1024).validate(bytes, skipGenerated: true);
      expect(validated.skipped, isEmpty);
      expect(validated.repacked, isNull);
      expect(validated.files.map((f) => f.path), everyElement(startsWith('$name/')));
      expect(validated.files.map((f) => f.path), contains('$name/$name.lmplugin'));
      // The strict check (no generated folders skipped) passes as well.
      const ZipValidator(maxUnpackedBytes: 2 * 1024 * 1024 * 1024).validate(bytes);

      final info = const PluginPackageValidator().validate(bytes);
      expect(info.name, name);
      expect(info.topFolder, name);
      expect(info.license?.code, 'MIT');
      expect(info.releaseNotes, isNotEmpty);

      // A real upload through the plugin publish flow.
      final server = await TestServer.start();
      final publisher = server.client();
      await signUp(publisher);
      final upload = await publisher.upload(bytes, fileName: '$name-${info.version}.zip', category: ListingCategory.plugin);
      expect(upload.skippedPaths, isEmpty);
      expect(upload.skippedFileCount, 0);
      expect(upload.plugin!.name, name);
      expect(upload.plugin!.version, info.version);
    }, timeout: const Timeout(Duration(minutes: 2)), skip: skipUnlessPlugin(name));
  }

  test("the script's allow-list is the marketplace's", () {
    final script = File('${pluginDir('lumina_plugin_pcg')}/tool/pack_plugin.dart');
    final text = script.readAsStringSync();
    final block = text.substring(
        text.indexOf('// marketplace-allow-list:start'), text.indexOf('// marketplace-allow-list:end'));
    Set<String> set(String constName) {
      final start = block.indexOf('const $constName = {');
      final body = block.substring(start, block.indexOf('};', start));
      return {for (final m in RegExp(r"'([^']*)'").allMatches(body)) m.group(1)!};
    }

    expect(set('_allowedExtensions'), {...contentExtensions, ...codeExtensions, ...neutralExtensions});
    expect(set('_allowedBareNames'), allowedBareNames);
    expect(set('_allowedDotNames'), allowedDotNames);
  }, skip: skipUnlessPlugin('lumina_plugin_pcg'));
}
