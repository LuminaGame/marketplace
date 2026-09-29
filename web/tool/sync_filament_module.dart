// Copies flutter_filament's WebAssembly module and its loader into
// `web/filament/` (gitignored), so `flutter build web` ships them at
// `build/web/filament/` for the listing page's 3D view.
//
//   dart run tool/sync_filament_module.dart     # then: flutter build web …
//
// The module is built in the flutter_filament repo
// (`tool/web/build_module.sh`); this never builds it.
import 'dart:convert';
import 'dart:io';

void main() {
  final source = _moduleDir();
  if (source == null) {
    stderr.writeln('flutter_filament/web/flutter_filament.wasm is not built: run tool/web/build_module.sh in flutter_filament.');
    exit(1);
  }
  final target = Directory('web/filament')..createSync(recursive: true);
  for (final name in ['flutter_filament.js', 'flutter_filament.wasm']) {
    final from = File('${source.path}/$name');
    final to = File('${target.path}/$name');
    if (to.existsSync() && to.lengthSync() == from.lengthSync() && !from.lastModifiedSync().isAfter(to.lastModifiedSync())) {
      continue;
    }
    from.copySync(to.path);
    stdout.writeln('copied ${from.path} → ${to.path} (${from.lengthSync()} bytes)');
  }
}

/// `<flutter_filament>/web`, found through the resolved dependencies (the pub
/// workspace's `../.dart_tool/package_config.json`, or this package's own when
/// it is resolved on its own); null when the module is not built.
Directory? _moduleDir() {
  final config = [File('.dart_tool/package_config.json'), File('../.dart_tool/package_config.json')]
      .where((f) => f.existsSync())
      .firstOrNull;
  if (config == null) return null;
  final packages = (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final entry = packages.cast<Map>().where((p) => p['name'] == 'flutter_filament').firstOrNull;
  if (entry == null) return null;
  final rootUri = entry['rootUri'] as String;
  final root = config.absolute.parent.uri.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
  final web = Directory.fromUri(root.resolve('web/'));
  return File('${web.path}/flutter_filament.wasm').existsSync() ? web : null;
}
