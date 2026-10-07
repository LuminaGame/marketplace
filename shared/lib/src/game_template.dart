import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'package:lumina_marketplace_shared/src/install_paths.dart';

/// The game template archive format, shared by the server (which
/// refuses archives that break it), the web publish flow and Lumina Studio
/// (whose launcher reads installed templates from `<config>/templates/`).
///
/// ```
/// <Folder>/                  optional single top-level folder; it names the install folder
///   template.json            {"format": 1, "title", "description", "engine_version", "thumbnail"}
///   thumbnail.png | .jpg     optional card screenshot
///   <source>.lmproject       the source project's manifest
///   pubspec.yaml             optional; `name:` is the source package
///   contents/**              required: levels (.lmas), assets
///   lib/**                   optional: the source project's Dart code
/// ```
///
/// A template is valid when it has a file under `contents/` and either a
/// `template.json` with a non-empty title or exactly one `.lmproject` that
/// parses (every `.lmproject` at the root must parse, and `template.json`,
/// when present, must be valid). The platform folders `flutter create`
/// regenerates, `build/` and `.dart_tool/` are not part of a template. In
/// `pubspec.yaml`, `lumina` is the git dependency Studio writes
/// ([kLuminaEngineGitUrl], `path: lumina`) or, from older projects, a path
/// dependency (Studio replaces either and links the local engine); any other
/// path dependency must be a vendored copy inside the template.
const int kGameTemplateFormatVersion = 1;

/// The engine repository a project's `lumina` git dependency names.
const String kLuminaEngineGitUrl = 'https://github.com/LuminaGame/lumina.git';

/// The template manifest at the template root.
const String kGameTemplateManifestFile = 'template.json';

/// The folder levels and assets live in.
const String kGameTemplateContentsFolder = 'contents';

/// The extension of the source project's manifest.
const String kGameTemplateProjectExtension = '.lmproject';

/// The source project's pubspec.
const String kGameTemplatePubspec = 'pubspec.yaml';

/// Card screenshots the launcher looks for when `template.json` names none.
const List<String> kGameTemplateThumbnailNames = ['thumbnail.png', 'thumbnail.jpg', 'screenshot.png', 'screenshot.jpg'];

/// Image types a `template.json` `thumbnail` may name.
const Set<String> kGameTemplateThumbnailExtensions = {'png', 'jpg', 'jpeg', 'webp'};

/// Root folders `flutter create` regenerates when a project is created from
/// the template.
const Set<String> kGameTemplatePlatformFolders = {'android', 'ios', 'linux', 'macos', 'windows', 'web'};

/// Local pub overrides (`pubspec_overrides.yaml`, anywhere): machine-specific
/// paths, never part of a template.
const String kGameTemplatePubspecOverrides = 'pubspec_overrides.yaml';

/// Build output: `build/` at the template root, `.dart_tool/` anywhere.
const Set<String> kGameTemplateBuildFolders = {'build', '.dart_tool'};

/// The API error code of a refused template (`422 invalid_template`).
const String kInvalidTemplateErrorCode = 'invalid_template';

/// The largest `template.json` / `.lmproject` / `pubspec.yaml` the check reads.
const int kGameTemplateMaxManifestBytes = 1024 * 1024;

/// `template.json` keys.
abstract final class GameTemplateKeys {
  static const format = 'format';
  static const title = 'title';
  static const description = 'description';
  static const engineVersion = 'engine_version';
  static const thumbnail = 'thumbnail';
  static const publisher = 'publisher';
  static const version = 'version';

  /// Keys whose values must be strings when present.
  static const strings = [description, engineVersion, thumbnail, publisher, version];
}

/// What [GameTemplateProblem.code] can be.
abstract final class GameTemplateProblemCode {
  static const topFolderInvalid = 'top_folder_invalid';
  static const excludedPath = 'excluded_path';
  static const missingContents = 'missing_contents';
  static const noManifest = 'no_manifest';
  static const manifestInvalid = 'manifest_invalid';
  static const manifestNoTitle = 'manifest_no_title';
  static const multipleProjects = 'multiple_projects';
  static const projectInvalid = 'project_invalid';
  static const thumbnailMissing = 'thumbnail_missing';
  static const pubspecInvalid = 'pubspec_invalid';
  static const pathDependency = 'path_dependency';
}

/// A parsed `template.json`.
class GameTemplateManifest {
  const GameTemplateManifest({
    required this.title,
    this.format = kGameTemplateFormatVersion,
    this.description = '',
    this.engineVersion = '',
    this.thumbnail,
    this.publisher = '',
    this.version = '',
  });

  final int format;
  final String title;
  final String description;
  final String engineVersion;

  /// A template-relative image path, or null.
  final String? thumbnail;

  /// For hand-copied templates; Marketplace installs use the listing's.
  final String publisher;
  final String version;

  Map<String, Object?> toJson() => {
        GameTemplateKeys.format: format,
        GameTemplateKeys.title: title,
        if (description.isNotEmpty) GameTemplateKeys.description: description,
        if (engineVersion.isNotEmpty) GameTemplateKeys.engineVersion: engineVersion,
        GameTemplateKeys.thumbnail: ?thumbnail,
        if (publisher.isNotEmpty) GameTemplateKeys.publisher: publisher,
        if (version.isNotEmpty) GameTemplateKeys.version: version,
      };

  /// Reads a `template.json` object; throws [FormatException] with the
  /// launcher's wording when it breaks the format.
  factory GameTemplateManifest.fromJson(Map<String, Object?> j) {
    final title = j[GameTemplateKeys.title];
    if (title is! String || title.trim().isEmpty) throw const _NoTitle();
    for (final key in GameTemplateKeys.strings) {
      if (j.containsKey(key) && j[key] is! String) throw FormatException('"$key" is not a string');
    }
    final format = j[GameTemplateKeys.format] ?? kGameTemplateFormatVersion;
    if (format != kGameTemplateFormatVersion) {
      throw FormatException('"format" is $format; this format is version $kGameTemplateFormatVersion');
    }
    final thumbnail = j[GameTemplateKeys.thumbnail] as String?;
    return GameTemplateManifest(
      format: kGameTemplateFormatVersion,
      title: title.trim(),
      description: j[GameTemplateKeys.description] as String? ?? '',
      engineVersion: j[GameTemplateKeys.engineVersion] as String? ?? '',
      thumbnail: thumbnail == null || thumbnail.isEmpty ? null : thumbnail,
      publisher: j[GameTemplateKeys.publisher] as String? ?? '',
      version: j[GameTemplateKeys.version] as String? ?? '',
    );
  }
}

class _NoTitle implements Exception {
  const _NoTitle();
}

/// Why an archive is not a valid game template. [path] is the offending
/// archive path (with the top folder), when there is one.
class GameTemplateProblem {
  const GameTemplateProblem(this.code, this.message, {this.path});

  /// One of [GameTemplateProblemCode].
  final String code;
  final String message;
  final String? path;

  Map<String, Object?> toJson() => {'code': code, 'message': message, 'path': ?path};

  factory GameTemplateProblem.fromJson(Map<String, Object?> j) =>
      GameTemplateProblem(j['code'] as String, j['message'] as String, path: j['path'] as String?);

  @override
  String toString() => message;
}

/// The result of [checkGameTemplate].
class GameTemplateCheck {
  const GameTemplateCheck({required this.problems, this.topFolder, this.manifest, this.projectPath});

  /// Empty when the archive is a valid template.
  final List<GameTemplateProblem> problems;

  /// The single top-level folder that was stripped (it names the install
  /// folder), or null when the archive root is the template.
  final String? topFolder;

  /// The parsed `template.json`, when it is valid.
  final GameTemplateManifest? manifest;

  /// The archive path of the source project's `.lmproject`, when there is
  /// exactly one.
  final String? projectPath;

  bool get isValid => problems.isEmpty;
}

/// The single top-level folder every one of [paths] lives in, or null (a file
/// at the root, or several top folders). Plugin and game template installs
/// strip it and name their folder after it.
String? singleTopFolder(Iterable<String> paths) {
  String? top;
  for (final p in paths) {
    final slash = p.indexOf('/');
    if (slash <= 0) return null;
    final t = p.substring(0, slash);
    if (top != null && t != top) return null;
    top = t;
  }
  return top;
}

/// The rules that need only the archive's file paths: the top folder and
/// the folders a template leaves out. The server runs these on upload before
/// anything else, so a stray `build/` is named as such.
List<GameTemplateProblem> gameTemplatePathProblems(Iterable<String> paths) {
  final all = paths.toList();
  final top = singleTopFolder(all);
  final problems = <GameTemplateProblem>[];
  if (top != null && top.startsWith('.')) {
    problems.add(GameTemplateProblem(GameTemplateProblemCode.topFolderInvalid,
        'the top-level folder $top/ starts with a dot, and Lumina Studio skips such folders; rename it',
        path: '$top/'));
  }
  final reported = <String>{};
  for (final path in all) {
    final rel = top == null ? path : path.substring(top.length + 1);
    final segments = rel.split('/');
    if (segments.last == kGameTemplatePubspecOverrides) {
      problems.add(GameTemplateProblem(
          GameTemplateProblemCode.excludedPath,
          '$rel must be left out: it points packages at folders on the publisher\'s machine (local engine '
          'checkout paths), and Lumina Studio writes a new one for each machine: $path',
          path: path));
      continue;
    }
    String? folder;
    String why = '';
    if (segments.length > 1 && kGameTemplatePlatformFolders.contains(segments.first)) {
      folder = segments.first;
      why = 'flutter create regenerates it when a project is created from the template';
    } else if (segments.length > 1 && segments.first == 'build') {
      folder = 'build';
      why = 'build output is not part of a template';
    } else {
      final i = segments.indexOf('.dart_tool');
      if (i >= 0 && i < segments.length - 1) {
        folder = segments.take(i + 1).join('/');
        why = 'build output is not part of a template';
      }
    }
    if (folder == null || !reported.add(folder)) continue;
    problems.add(GameTemplateProblem(GameTemplateProblemCode.excludedPath, '$folder/ must be left out ($why): $path',
        path: path));
  }
  return problems;
}

/// Checks the archive whose files are [paths] (forward-slash archive paths,
/// files only) against the game template format. [read] returns a file's
/// bytes by its archive path; only `template.json`, the root `.lmproject`
/// files and the `pubspec.yaml` files the root pubspec reaches are read.
GameTemplateCheck checkGameTemplate(Iterable<String> paths, {required List<int>? Function(String path) read}) {
  final all = paths.toList();
  final top = singleTopFolder(all);
  final problems = gameTemplatePathProblems(all);
  String archivePath(String rel) => top == null ? rel : '$top/$rel';
  final rels = <String>{for (final p in all) top == null ? p : p.substring(top.length + 1)};

  String? text(String rel, String label) {
    final bytes = read(archivePath(rel));
    if (bytes == null) return null;
    if (bytes.length > kGameTemplateMaxManifestBytes) {
      throw FormatException('$label is larger than ${kGameTemplateMaxManifestBytes ~/ 1024} KB');
    }
    return utf8.decode(bytes);
  }

  if (!rels.any((r) => r.startsWith('$kGameTemplateContentsFolder/'))) {
    problems.add(const GameTemplateProblem(GameTemplateProblemCode.missingContents,
        'it has no contents/ folder with files; levels (.lmas) and assets go in contents/'));
  }

  // The source project's manifest: every root .lmproject must parse, and a
  // template is one project.
  final projects = [for (final r in rels) if (!r.contains('/') && r.endsWith(kGameTemplateProjectExtension)) r]..sort();
  var projectOk = false;
  if (projects.length > 1) {
    problems.add(GameTemplateProblem(GameTemplateProblemCode.multipleProjects,
        'it has ${projects.length} .lmproject files (${projects.join(', ')}); a template is one project',
        path: archivePath(projects[1])));
  } else if (projects.length == 1) {
    final rel = projects.single;
    try {
      final j = jsonDecode(text(rel, rel) ?? '');
      if (j is! Map || j['project_name'] is! String) throw const FormatException('no project_name');
      projectOk = true;
    } on FormatException catch (e) {
      problems.add(GameTemplateProblem(GameTemplateProblemCode.projectInvalid,
          '$rel is not a Lumina project manifest (${_reason(e)})', path: archivePath(rel)));
    }
  }

  // template.json.
  GameTemplateManifest? manifest;
  final manifestPath = archivePath(kGameTemplateManifestFile);
  if (rels.contains(kGameTemplateManifestFile)) {
    try {
      final j = jsonDecode(text(kGameTemplateManifestFile, kGameTemplateManifestFile) ?? '');
      if (j is! Map) throw const FormatException('not a JSON object');
      manifest = GameTemplateManifest.fromJson(j.cast<String, Object?>());
    } on _NoTitle {
      problems.add(GameTemplateProblem(GameTemplateProblemCode.manifestNoTitle, 'template.json has no title',
          path: manifestPath));
    } on FormatException catch (e) {
      problems.add(GameTemplateProblem(GameTemplateProblemCode.manifestInvalid,
          'template.json is not a valid template manifest (${_reason(e)})', path: manifestPath));
    }
    final thumbnail = manifest?.thumbnail;
    if (thumbnail != null) {
      final ext = thumbnail.contains('.') ? thumbnail.split('.').last.toLowerCase() : '';
      if (!isSafeRelativePath(thumbnail) || !rels.contains(thumbnail)) {
        problems.add(GameTemplateProblem(GameTemplateProblemCode.thumbnailMissing,
            'template.json "thumbnail" names $thumbnail, which is not a file in the archive', path: manifestPath));
        manifest = null;
      } else if (!kGameTemplateThumbnailExtensions.contains(ext)) {
        problems.add(GameTemplateProblem(GameTemplateProblemCode.manifestInvalid,
            'template.json "thumbnail" names $thumbnail; use a .png or .jpg image', path: manifestPath));
        manifest = null;
      }
    }
  } else if (projects.isEmpty) {
    problems.add(const GameTemplateProblem(GameTemplateProblemCode.noManifest,
        'it has neither a template.json with a title nor a .lmproject manifest'));
  }

  // pubspec.yaml and the vendored packages it reaches.
  if (rels.contains(kGameTemplatePubspec)) {
    problems.addAll(_PubspecCheck(rels, archivePath, text).run());
  }

  return GameTemplateCheck(
    problems: problems,
    topFolder: top,
    manifest: manifest,
    projectPath: projectOk ? archivePath(projects.single) : null,
  );
}

String _reason(FormatException e) => e.message;

final _packageName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// The engine dependency as lumina_ui's `TemplateProjectCreator.rewritePubspec`
/// finds it to point it at the local engine.
final _luminaBlock = RegExp(r'^( +)lumina:[ \t]*\n( +)path:[^\n]*$', multiLine: true);

/// Path dependencies: `lumina` in the root `dependencies:` (the engine's git
/// dependency, or a path Studio repoints); every other one a vendored package
/// inside the template, whose own
/// pubspec follows the same rules (without lumina).
class _PubspecCheck {
  _PubspecCheck(this.rels, this.archivePath, this.text);

  final Set<String> rels;
  final String Function(String rel) archivePath;
  final String? Function(String rel, String label) text;
  final _visited = <String>{};
  final _problems = <GameTemplateProblem>[];

  List<GameTemplateProblem> run() {
    _check(kGameTemplatePubspec, root: true);
    return _problems;
  }

  void _fail(String code, String pubspec, String message) =>
      _problems.add(GameTemplateProblem(code, '$pubspec: $message', path: archivePath(pubspec)));

  void _check(String pubspec, {required bool root}) {
    if (!_visited.add(pubspec)) return;
    final String source;
    final Object? doc;
    try {
      source = text(pubspec, pubspec) ?? '';
      doc = loadYaml(source);
    } on YamlException catch (e) {
      return _fail(GameTemplateProblemCode.pubspecInvalid, pubspec, 'not valid YAML (${e.message})');
    } on FormatException catch (e) {
      return _fail(GameTemplateProblemCode.pubspecInvalid, pubspec, e.message);
    }
    if (doc is! Map) return _fail(GameTemplateProblemCode.pubspecInvalid, pubspec, 'not a YAML map');
    final name = doc['name'];
    if (name != null && (name is! String || !_packageName.hasMatch(name))) {
      return _fail(GameTemplateProblemCode.pubspecInvalid, pubspec, '"name: $name" is not a Dart package name');
    }
    final dir = pubspec.contains('/') ? pubspec.substring(0, pubspec.lastIndexOf('/')) : '';
    for (final section in const ['dependencies', 'dev_dependencies', 'dependency_overrides']) {
      final deps = doc[section];
      if (deps is! Map) continue;
      for (final MapEntry(key: dep, value: spec) in deps.entries) {
        if (dep == 'lumina') {
          _lumina(pubspec, source, section, spec, root: root);
          continue;
        }
        if (spec is Map && spec.containsKey('path')) _vendored(pubspec, dir, '$dep', spec['path']);
      }
    }
  }

  void _lumina(String pubspec, String source, String section, Object? spec, {required bool root}) {
    final isPath = spec is Map && spec.containsKey('path');
    if (!root) {
      if (isPath) {
        _fail(GameTemplateProblemCode.pathDependency, pubspec,
            'a vendored package cannot depend on lumina by path (Lumina Studio points only the template\'s own lumina '
            'dependency at the local engine); move its engine code into the template\'s lib/');
      }
      return;
    }
    if (section != 'dependencies') {
      if (isPath) {
        _fail(GameTemplateProblemCode.pathDependency, pubspec,
            'lumina may be a path dependency only under dependencies: (Lumina Studio points that entry at the local '
            'engine), not under $section:');
      }
      return;
    }
    final git = spec is Map ? spec['git'] : null;
    if (git != null) {
      final url = git is Map ? git['url'] : git;
      final path = git is Map ? git['path'] : null;
      if (url != kLuminaEngineGitUrl || path != 'lumina') {
        _fail(GameTemplateProblemCode.pathDependency, pubspec,
            'lumina may be a git dependency only on the engine repository ("url: $kLuminaEngineGitUrl" with '
            '"path: lumina"), as Lumina Studio writes it');
      }
    } else if (!isPath) {
      _fail(GameTemplateProblemCode.pathDependency, pubspec,
          'lumina must be the engine\'s git dependency ("git:" with "url: $kLuminaEngineGitUrl" and "path: lumina") '
          'or a path dependency (Lumina Studio links either to the local engine), or left out; '
          'it is not a published package');
    } else if (!_luminaBlock.hasMatch(source)) {
      _fail(GameTemplateProblemCode.pathDependency, pubspec,
          'write the lumina dependency as "lumina:" with "path: …" on the next line, so Lumina Studio can point it '
          'at the local engine');
    }
  }

  void _vendored(String pubspec, String dir, String dep, Object? rawPath) {
    final path = rawPath is String ? rawPath.trim() : '';
    final target = _resolve(dir, path);
    String advice() => 'vendor it into the template (for example packages/$dep/ with its pubspec.yaml, and '
        '"path: packages/$dep") or depend on a published version';
    if (target == null) {
      return _fail(GameTemplateProblemCode.pathDependency, pubspec,
          'the path dependency $dep ($path) points outside the template, at the publisher\'s machine; ${advice()}');
    }
    final targetPubspec = target.isEmpty ? kGameTemplatePubspec : '$target/$kGameTemplatePubspec';
    if (!rels.contains(targetPubspec) || targetPubspec == kGameTemplatePubspec) {
      return _fail(GameTemplateProblemCode.pathDependency, pubspec,
          'the path dependency $dep ($path) is not in the archive (no $targetPubspec); ${advice()}');
    }
    _check(targetPubspec, root: false);
  }

  /// [path] relative to the template-relative [dir], normalized; null when it
  /// is absolute or leaves the template.
  static String? _resolve(String dir, String path) {
    if (path.isEmpty || path.contains('\\') || path.startsWith('/') || path.startsWith('~')) return null;
    if (RegExp(r'^[A-Za-z]:').hasMatch(path) || path.contains('://')) return null;
    final out = dir.isEmpty ? <String>[] : dir.split('/');
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (out.isEmpty) return null;
        out.removeLast();
      } else {
        out.add(segment);
      }
    }
    return out.join('/');
  }
}
