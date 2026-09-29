import 'package:archive/archive.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

import '../errors.dart';

/// Checks `game_template` archives against the game template format (v1;
/// the rules live in the shared package's [checkGameTemplate] so
/// the web publish flow and Lumina Studio apply the same ones). Runs on
/// archives [ZipValidator] already accepted (safe paths, size limits).
class GameTemplateValidator {
  const GameTemplateValidator();

  /// The format check of a zip archive.
  GameTemplateCheck check(List<int> zip) {
    final archive = ZipDecoder().decodeBytes(zip);
    final files = {for (final entry in archive) if (entry.isFile) entry.name: entry};
    return checkGameTemplate(files.keys, read: (path) => files[path]?.readBytes());
  }

  /// Throws `422 invalid_template` unless [zip] is a valid game template.
  void validate(List<int> zip) {
    final result = check(zip);
    if (!result.isValid) throw invalidTemplate(result.problems);
  }

  /// Throws `422 invalid_template` when the file [paths] alone break the
  /// format (a platform folder, `build/`, a dot top folder).
  void validatePaths(List<String> paths) {
    final problems = gameTemplatePathProblems(paths);
    if (problems.isNotEmpty) throw invalidTemplate(problems);
  }
}

/// The `422 invalid_template` error for [problems]: the message names the
/// first; `details` carries its code and archive path and the full list.
ApiException invalidTemplate(List<GameTemplateProblem> problems) {
  final first = problems.first;
  return ApiException(422, kInvalidTemplateErrorCode, 'The game template was refused: ${first.message}.', details: {
    'problem': first.code,
    'path': ?first.path,
    'problems': [for (final p in problems) p.toJson()],
    'formatVersion': kGameTemplateFormatVersion,
  });
}
