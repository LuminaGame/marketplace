import 'package:archive/archive.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

import '../errors.dart';

/// Checks `plugin` archives against the Lumina plugin package format (
/// the rules live in the shared package's [checkPluginPackage], so the web
/// publish flow sees exactly what the server decides). Runs on archives
/// [ZipValidator] already accepted (safe paths, size limits).
class PluginPackageValidator {
  const PluginPackageValidator();

  /// The package check of a zip archive.
  PluginPackageCheck check(List<int> zip) {
    final archive = ZipDecoder().decodeBytes(zip);
    final files = {for (final entry in archive) if (entry.isFile) entry.name: entry};
    return checkPluginPackage(files.keys, read: (path) => files[path]?.readBytes());
  }

  /// The parsed package; throws `422 invalid_plugin` unless [zip] is a valid
  /// plugin package.
  PluginPackageInfo validate(List<int> zip) {
    final result = check(zip);
    if (!result.isValid) throw invalidPlugin(result.problems);
    return result.info!;
  }
}

/// The `422 invalid_plugin` error for [problems]: the message names the
/// first; `details` carries its code and archive path and the full list.
ApiException invalidPlugin(List<PluginPackageProblem> problems) {
  final first = problems.first;
  return ApiException(422, kInvalidPluginErrorCode, 'The plugin package was refused: ${first.message}.', details: {
    'problem': first.code,
    'path': ?first.path,
    'problems': [for (final p in problems) p.toJson()],
  });
}
