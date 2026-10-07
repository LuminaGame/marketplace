import 'dart:convert';

import 'package:lumina_marketplace_shared/src/game_template.dart' show singleTopFolder;
import 'package:lumina_marketplace_shared/src/licenses.dart';

/// The Lumina plugin package format as the marketplace reads it,
/// shared by the server (which refuses packages that break it) and the web
/// publish flow (which fills the listing from it).
///
/// ```
/// <name>/                    optional single top-level folder; it must be named <name>
///   <name>.lmplugin          the plugin manifest (JSON): name, friendly_name, version,
///                            description, category, authors, engine_version, modules, …
///                            and, optional for the marketplace: license, changelog
///   LICENSE | COPYING[.md|.txt]   optional license text
///   CHANGELOG.md             optional; `## <version>` sections
///   pubspec.yaml, lib/**, resources/**, …
/// ```
///
/// The manifest rules mirror lumina's `PluginRepository` (name = file
/// basename, a Dart package name, a version) and lumina_ui's Marketplace
/// installer (it loads `plugins/<name>/<name>.lmplugin`). `license` is an
/// SPDX id from the free-license allow-list, or one content and one code
/// license joined by `AND`; without it a recognised root license text
/// declares the license. `changelog` names the changelog file (default a root
/// `CHANGELOG.md`).
const String kPluginManifestExtension = '.lmplugin';

/// The API error code of a refused plugin package (`422 invalid_plugin`).
const String kInvalidPluginErrorCode = 'invalid_plugin';

/// The largest manifest / license / changelog file the check reads.
const int kPluginMaxManifestBytes = 1024 * 1024;

/// The longest changelog text / release notes kept (the API's release notes
/// limit).
const int kPluginMaxChangelogChars = 20000;

/// Root file names (lower case) that hold the license text.
const Set<String> kPluginLicenseFileNames = {'license', 'license.md', 'license.txt', 'copying', 'copying.md', 'copying.txt'};

/// Root file names (lower case) the changelog is looked for under, in order.
const List<String> kPluginChangelogFileNames = ['changelog.md', 'changelog', 'changelog.txt'];

/// `.lmplugin` keys the marketplace reads.
abstract final class PluginManifestKeys {
  static const name = 'name';
  static const friendlyName = 'friendly_name';
  static const version = 'version';
  static const description = 'description';
  static const category = 'category';
  static const authors = 'authors';
  static const engineVersion = 'engine_version';

  /// Optional: SPDX id(s) of the package's license.
  static const license = 'license';

  /// Optional: package-relative path of the changelog.
  static const changelog = 'changelog';
}

/// What [PluginPackageProblem.code] can be.
abstract final class PluginPackageProblemCode {
  static const noManifest = 'no_manifest';
  static const multipleManifests = 'multiple_manifests';
  static const manifestInvalid = 'manifest_invalid';
  static const nameInvalid = 'name_invalid';
  static const nameMismatch = 'name_mismatch';
  static const topFolderMismatch = 'top_folder_mismatch';
  static const versionInvalid = 'version_invalid';
  static const engineVersionInvalid = 'engine_version_invalid';
  static const licenseUnknown = 'license_unknown';
  static const licenseNotFree = 'license_not_free';
  static const licenseConflict = 'license_conflict';
  static const changelogMissing = 'changelog_missing';
}

/// Why an archive is not a valid plugin package. [path] is the offending
/// archive path (with the top folder), when there is one.
class PluginPackageProblem {
  const PluginPackageProblem(this.code, this.message, {this.path});

  /// One of [PluginPackageProblemCode].
  final String code;
  final String message;
  final String? path;

  Map<String, Object?> toJson() => {'code': code, 'message': message, 'path': ?path};

  factory PluginPackageProblem.fromJson(Map<String, Object?> j) =>
      PluginPackageProblem(j['code'] as String, j['message'] as String, path: j['path'] as String?);

  @override
  String toString() => message;
}

/// Where a package's license came from.
enum PluginLicenseSource {
  /// The manifest's `license` key.
  manifest('manifest'),

  /// A recognised root license text (`LICENSE`, `COPYING`, …).
  licenseFile('license_file');

  const PluginLicenseSource(this.wire);
  final String wire;

  static PluginLicenseSource parse(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => PluginLicenseSource.manifest);
}

/// The license a package declares: at most one per kind.
class PluginLicense {
  const PluginLicense({this.content, this.code, required this.source, required this.path});

  final String? content;
  final String? code;
  final PluginLicenseSource source;

  /// The archive path it was read from (the manifest or the license file).
  final String path;

  LicenseSelection get selection => LicenseSelection(content: content, code: code);

  /// The declared id of [kind], or null.
  String? operator [](LicenseKind kind) => kind == LicenseKind.content ? content : code;

  /// "lumina_plugin_pcg.lmplugin" / "LICENSE": the file name, for the UI.
  String get fileName => path.split('/').last;

  Map<String, Object?> toJson() => {'content': ?content, 'code': ?code, 'source': source.wire, 'path': path};

  factory PluginLicense.fromJson(Map<String, Object?> j) => PluginLicense(
        content: j['content'] as String?,
        code: j['code'] as String?,
        source: PluginLicenseSource.parse(j['source'] as String?),
        path: j['path'] as String,
      );
}

/// What a license text was recognised as.
enum LicenseTextVerdict {
  /// A license on the free-license allow-list ([LicenseTextMatch.id]).
  free('free'),

  /// A license the marketplace does not accept ("All rights reserved",
  /// NonCommercial, NoDerivatives, an id off the allow-list).
  notFree('not_free'),

  /// Not recognised: the publisher decides.
  unrecognised('unrecognised');

  const LicenseTextVerdict(this.wire);
  final String wire;

  static LicenseTextVerdict? tryParse(String? wire) {
    for (final v in values) {
      if (v.wire == wire) return v;
    }
    return null;
  }
}

/// The result of [detectLicenseText].
class LicenseTextMatch {
  const LicenseTextMatch(this.verdict, {this.id, this.evidence});

  final LicenseTextVerdict verdict;

  /// The SPDX id, for [LicenseTextVerdict.free] (and a named id that is not
  /// on the allow-list).
  final String? id;

  /// What gave a non-free text away ("All rights reserved", …).
  final String? evidence;
}

/// The parsed package: everything the publish flow fills the listing with.
class PluginPackageInfo {
  const PluginPackageInfo({
    required this.name,
    required this.version,
    required this.manifestPath,
    this.friendlyName,
    this.description = '',
    this.category,
    this.authors = const [],
    this.engineVersionConstraint,
    this.topFolder,
    this.license,
    this.licenseFile,
    this.licenseFileVerdict,
    this.changelogPath,
    this.changelog,
    this.releaseNotes,
  });

  /// The Dart package name (= the manifest's basename = the install folder).
  final String name;
  final String? friendlyName;

  /// `X.Y.Z`: the marketplace version of this upload.
  final String version;
  final String description;

  /// The plugin category (`Procedural`, …), not the listing category.
  final String? category;
  final List<String> authors;

  /// `engine_version` as written (`>=0.0.1 <1.0.0`).
  final String? engineVersionConstraint;

  /// The archive path of the `.lmplugin`.
  final String manifestPath;

  /// The single top folder (= [name]) or null.
  final String? topFolder;

  /// The declared license, or null when the publisher picks.
  final PluginLicense? license;

  /// The archive path of the root license text, and what it was recognised as.
  final String? licenseFile;
  final LicenseTextVerdict? licenseFileVerdict;

  /// The archive path and (capped) text of the changelog.
  final String? changelogPath;
  final String? changelog;

  /// The changelog section of [version], or null.
  final String? releaseNotes;

  /// The listing title: `friendly_name`, else `name`.
  String get title => (friendlyName ?? '').trim().isNotEmpty ? friendlyName!.trim() : name;

  /// The listing's minimum engine version: the lower bound of
  /// [engineVersionConstraint], or null.
  String? get minEngineVersion => engineVersionConstraint == null ? null : minimumEngineVersion(engineVersionConstraint!);

  /// Listing tags: the plugin category (as a tag) and `plugin`.
  List<String> get tags {
    final c = (category ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return [if (c.isNotEmpty && c != 'other' && c != 'plugin') c.length > 32 ? c.substring(0, 32) : c, 'plugin'];
  }

  /// The manifest's file name (`lumina_plugin_pcg.lmplugin`).
  String get manifestFileName => manifestPath.split('/').last;

  Map<String, Object?> toJson() => {
        'name': name,
        'friendlyName': ?friendlyName,
        'title': title,
        'version': version,
        'description': description,
        'category': ?category,
        'authors': authors,
        'engineVersionConstraint': ?engineVersionConstraint,
        'minEngineVersion': ?minEngineVersion,
        'tags': tags,
        'manifestPath': manifestPath,
        'topFolder': ?topFolder,
        'license': ?license?.toJson(),
        'licenseFile': ?licenseFile,
        'licenseFileVerdict': ?licenseFileVerdict?.wire,
        'changelogPath': ?changelogPath,
        'changelog': ?changelog,
        'releaseNotes': ?releaseNotes,
      };

  factory PluginPackageInfo.fromJson(Map<String, Object?> j) => PluginPackageInfo(
        name: j['name'] as String,
        friendlyName: j['friendlyName'] as String?,
        version: j['version'] as String,
        description: j['description'] as String? ?? '',
        category: j['category'] as String?,
        authors: [for (final a in j['authors'] as List? ?? const []) '$a'],
        engineVersionConstraint: j['engineVersionConstraint'] as String?,
        manifestPath: j['manifestPath'] as String,
        topFolder: j['topFolder'] as String?,
        license: j['license'] == null ? null : PluginLicense.fromJson((j['license'] as Map).cast<String, Object?>()),
        licenseFile: j['licenseFile'] as String?,
        licenseFileVerdict: LicenseTextVerdict.tryParse(j['licenseFileVerdict'] as String?),
        changelogPath: j['changelogPath'] as String?,
        changelog: j['changelog'] as String?,
        releaseNotes: j['releaseNotes'] as String?,
      );
}

/// The result of [checkPluginPackage].
class PluginPackageCheck {
  const PluginPackageCheck({required this.problems, this.info});

  /// Empty when the archive is a valid plugin package.
  final List<PluginPackageProblem> problems;

  /// The parsed package, when the manifest itself is valid (license or
  /// changelog problems still leave it set, so the flow can show it).
  final PluginPackageInfo? info;

  bool get isValid => problems.isEmpty;
}

final _packageName = RegExp(r'^[a-z][a-z0-9_]*$');
final _marketVersion = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$');
final _constraintVersion = r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?';
final _constraintToken = RegExp('^(?:>=|<=|>|<|\\^)?$_constraintVersion\$');

/// Whether [constraint] is a pub-style version constraint (`any`, `^1.2.3`,
/// `>=0.0.1 <1.0.0`, `1.2.3`).
bool isVersionConstraint(String constraint) {
  final tokens = constraint.trim().split(RegExp(r'\s+'));
  if (tokens.length == 1 && tokens.single == 'any') return true;
  return tokens.isNotEmpty && tokens.every((t) => t.isNotEmpty && _constraintToken.hasMatch(t));
}

/// The lower bound of a version constraint as `X.Y.Z` (`>=0.0.1 <1.0.0` →
/// `0.0.1`, `^0.2.0` → `0.2.0`), or null when it has none.
String? minimumEngineVersion(String constraint) {
  if (!isVersionConstraint(constraint)) return null;
  for (final t in constraint.trim().split(RegExp(r'\s+'))) {
    final m = RegExp(r'^(>=|>|\^)?(\d+\.\d+\.\d+)').firstMatch(t);
    if (m == null || t.startsWith('<')) continue;
    return m[2];
  }
  return null;
}

/// Recognises a license text: an `SPDX-License-Identifier:` line, or the
/// standard wording of each allow-listed license; "All rights reserved",
/// NonCommercial and NoDerivatives texts are not free.
LicenseTextMatch detectLicenseText(String text) {
  final spdx = RegExp(r'SPDX-License-Identifier:\s*([A-Za-z0-9.+-]+)').firstMatch(text);
  if (spdx != null) {
    final id = spdx[1]!;
    return licenseById(id) != null
        ? LicenseTextMatch(LicenseTextVerdict.free, id: id)
        : LicenseTextMatch(LicenseTextVerdict.notFree, id: id, evidence: 'SPDX-License-Identifier: $id');
  }
  final t = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  LicenseTextMatch free(String id) => LicenseTextMatch(LicenseTextVerdict.free, id: id);
  if (t.contains('cc0 1.0 universal')) return free('CC0-1.0');
  for (final (needle, evidence) in const [
    ('noncommercial', 'NonCommercial'),
    ('noderivatives', 'NoDerivatives'),
    ('noderivs', 'NoDerivs'),
  ]) {
    if (t.contains(needle)) return LicenseTextMatch(LicenseTextVerdict.notFree, evidence: evidence);
  }
  if (t.contains('attribution-sharealike 4.0 international')) return free('CC-BY-SA-4.0');
  if (t.contains('attribution 4.0 international')) return free('CC-BY-4.0');
  if (t.contains('mozilla public license version 2.0') || t.contains('mozilla public license, v. 2.0')) return free('MPL-2.0');
  if (t.contains('apache license') && t.contains('version 2.0')) return free('Apache-2.0');
  if (t.contains('permission is hereby granted, free of charge, to any person obtaining a copy')) return free('MIT');
  if (t.contains("provided 'as-is', without any express or implied warranty") && t.contains('altered source versions must be plainly marked')) {
    return free('Zlib');
  }
  if (t.contains('redistribution and use in source and binary forms')) {
    return free(t.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause');
  }
  if (t.contains('all rights reserved')) {
    return const LicenseTextMatch(LicenseTextVerdict.notFree, evidence: 'All rights reserved');
  }
  return const LicenseTextMatch(LicenseTextVerdict.unrecognised);
}

/// The body of [version]'s section in a Markdown changelog (`## 1.0.0`,
/// `## [1.0.0] - 2026-09-01`, `## v1.0.0`), trimmed, or null.
String? changelogSection(String markdown, String version) {
  final lines = const LineSplitter().convert(markdown);
  final heading = RegExp(r'^#{1,2}\s+(.*)$');
  int? start;
  var end = lines.length;
  for (var i = 0; i < lines.length; i++) {
    final m = heading.firstMatch(lines[i]);
    if (m == null) continue;
    if (start != null) {
      end = i;
      break;
    }
    final v = RegExp(r'^\[?v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?)\]?').firstMatch(m[1]!.trim());
    if (v != null && v[1] == version) start = i + 1;
  }
  if (start == null) return null;
  final body = lines.sublist(start, end).join('\n').trim();
  return body.isEmpty ? null : _cap(body);
}

String _cap(String s) => s.length <= kPluginMaxChangelogChars ? s : '${s.substring(0, kPluginMaxChangelogChars - 1)}…';

/// Checks a plugin package given its file [paths] (forward slashes, as in the
/// zip) and a [read] callback for the manifest, license and changelog files.
PluginPackageCheck checkPluginPackage(Iterable<String> paths, {required List<int>? Function(String path) read}) {
  final all = paths.toList();
  final top = singleTopFolder(all);
  final prefix = top == null ? '' : '$top/';
  String rel(String path) => path.substring(prefix.length);
  final root = [for (final p in all) if (!rel(p).contains('/')) p];

  String? text(String path) {
    final bytes = read(path);
    if (bytes == null || bytes.length > kPluginMaxManifestBytes) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  final manifests = [for (final p in root) if (p.toLowerCase().endsWith(kPluginManifestExtension)) p];
  if (manifests.isEmpty) {
    return PluginPackageCheck(problems: [
      PluginPackageProblem(PluginPackageProblemCode.noManifest,
          'it has no <name>$kPluginManifestExtension manifest at the package root${top == null ? '' : ' ($prefix)'}; '
          'Lumina Studio loads a plugin from it',
          path: top == null ? null : prefix),
    ]);
  }
  if (manifests.length > 1) {
    return PluginPackageCheck(problems: [
      PluginPackageProblem(PluginPackageProblemCode.multipleManifests,
          'it has ${manifests.length} $kPluginManifestExtension manifests at the package root (${manifests.map(rel).join(', ')}); a package has one',
          path: manifests.first),
    ]);
  }
  final manifestPath = manifests.single;
  final basename = rel(manifestPath).substring(0, rel(manifestPath).length - kPluginManifestExtension.length);
  PluginPackageCheck fail(String code, String message) =>
      PluginPackageCheck(problems: [PluginPackageProblem(code, message, path: manifestPath)]);

  final raw = text(manifestPath);
  Object? decoded;
  try {
    if (raw == null) throw const FormatException('it is unreadable or larger than 1 MB');
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    return fail(PluginPackageProblemCode.manifestInvalid, '${rel(manifestPath)} is not valid JSON (${e.message})');
  }
  if (decoded is! Map) return fail(PluginPackageProblemCode.manifestInvalid, '${rel(manifestPath)} is not a JSON object');
  final m = decoded.cast<String, Object?>();
  for (final key in const [
    PluginManifestKeys.friendlyName,
    PluginManifestKeys.description,
    PluginManifestKeys.category,
    PluginManifestKeys.engineVersion,
    PluginManifestKeys.changelog,
    PluginManifestKeys.license,
  ]) {
    if (m[key] != null && m[key] is! String) {
      return fail(PluginPackageProblemCode.manifestInvalid, '"$key" in ${rel(manifestPath)} is not a string');
    }
  }
  final authors = m[PluginManifestKeys.authors];
  if (authors != null && (authors is! List || authors.any((a) => a is! String))) {
    return fail(PluginPackageProblemCode.manifestInvalid, '"authors" in ${rel(manifestPath)} is not a list of strings');
  }

  final name = m[PluginManifestKeys.name];
  if (name is! String || name.isEmpty) {
    return fail(PluginPackageProblemCode.manifestInvalid, '${rel(manifestPath)} has no "name"');
  }
  if (!_packageName.hasMatch(name)) {
    return fail(PluginPackageProblemCode.nameInvalid,
        'the plugin name "$name" is not a Dart package name (lowercase letters, digits and _, starting with a letter)');
  }
  final problems = <PluginPackageProblem>[];
  if (name != basename) {
    problems.add(PluginPackageProblem(PluginPackageProblemCode.nameMismatch,
        'the manifest name "$name" does not match its file name $basename$kPluginManifestExtension',
        path: manifestPath));
  }
  if (top != null && top != basename) {
    problems.add(PluginPackageProblem(PluginPackageProblemCode.topFolderMismatch,
        'the top-level folder $top/ must be named after the plugin ($basename/): Lumina Studio installs it to '
        'plugins/$top/ and looks for $top$kPluginManifestExtension there',
        path: prefix));
  }
  final version = m[PluginManifestKeys.version];
  if (version is! String || !_marketVersion.hasMatch(version)) {
    problems.add(PluginPackageProblem(PluginPackageProblemCode.versionInvalid,
        version == null
            ? '${rel(manifestPath)} has no "version"'
            : 'the manifest version ${jsonEncode(version)} is not a marketplace version (X.Y.Z, e.g. 1.0.0)',
        path: manifestPath));
  }
  final engine = m[PluginManifestKeys.engineVersion] as String?;
  if (engine != null && !isVersionConstraint(engine)) {
    problems.add(PluginPackageProblem(PluginPackageProblemCode.engineVersionInvalid,
        '"engine_version" ${jsonEncode(engine)} is not a version constraint (e.g. ">=0.0.1 <1.0.0")',
        path: manifestPath));
  }
  if (problems.isNotEmpty) return PluginPackageCheck(problems: problems);

  // The license: the manifest's `license`, else a recognised root text.
  final licenseFiles = [for (final p in root) if (kPluginLicenseFileNames.contains(rel(p).toLowerCase())) p]..sort();
  final fileMatches = {for (final p in licenseFiles) p: detectLicenseText(text(p) ?? '')};
  PluginLicense? license;
  final declared = m[PluginManifestKeys.license] as String?;
  if (declared != null && declared.trim().isNotEmpty) {
    final (parsed, problem) = _parseLicenseField(declared.trim());
    if (problem != null) {
      problems.add(PluginPackageProblem(PluginPackageProblemCode.licenseUnknown, problem, path: manifestPath));
    } else {
      license = PluginLicense(content: parsed!.content, code: parsed.code, source: PluginLicenseSource.manifest, path: manifestPath);
      for (final MapEntry(key: path, value: match) in fileMatches.entries) {
        final contradicts = switch (match.verdict) {
          LicenseTextVerdict.free => !parsed.ids.contains(match.id),
          LicenseTextVerdict.notFree => true,
          LicenseTextVerdict.unrecognised => false,
        };
        if (contradicts) {
          problems.add(PluginPackageProblem(
              PluginPackageProblemCode.licenseConflict,
              '${rel(path)} ${match.verdict == LicenseTextVerdict.free ? 'is the ${match.id} license' : 'reads "${match.evidence ?? match.id}"'}, '
              'but ${rel(manifestPath)} declares ${parsed.ids.join(' AND ')}; ship the text of the declared license',
              path: path));
        }
      }
    }
  } else {
    String? content, code, from;
    for (final MapEntry(key: path, value: match) in fileMatches.entries) {
      if (match.verdict == LicenseTextVerdict.notFree) {
        problems.add(PluginPackageProblem(
            PluginPackageProblemCode.licenseNotFree,
            '${rel(path)} reads "${match.evidence ?? match.id}", which is not a free license; the marketplace publishes '
            'free licenses only (${licenseCatalogue.map((l) => l.id).join(', ')}) — ship one of them and declare it with '
            '"license" in ${rel(manifestPath)}',
            path: path));
      } else if (match.verdict == LicenseTextVerdict.free) {
        final info = licenseById(match.id)!;
        final current = info.kind == LicenseKind.content ? content : code;
        if (current != null && current != info.id) {
          problems.add(PluginPackageProblem(PluginPackageProblemCode.licenseConflict,
              '${rel(path)} is the ${info.id} license, but another license file is $current; declare one with "license" in ${rel(manifestPath)}',
              path: path));
        }
        if (info.kind == LicenseKind.content) {
          content = info.id;
        } else {
          code = info.id;
        }
        from ??= path;
      }
    }
    if (from != null && problems.isEmpty) {
      license = PluginLicense(content: content, code: code, source: PluginLicenseSource.licenseFile, path: from);
    }
  }

  // The changelog: `changelog` in the manifest, else a root CHANGELOG.md.
  String? changelogPath;
  final named = m[PluginManifestKeys.changelog] as String?;
  if (named != null && named.trim().isNotEmpty) {
    final candidate = '$prefix${named.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '')}';
    if (all.contains(candidate)) {
      changelogPath = candidate;
    } else {
      problems.add(PluginPackageProblem(PluginPackageProblemCode.changelogMissing,
          '"changelog" in ${rel(manifestPath)} names ${named.trim()}, which is not in the package',
          path: candidate));
    }
  } else {
    for (final n in kPluginChangelogFileNames) {
      final hit = root.where((p) => rel(p).toLowerCase() == n);
      if (hit.isNotEmpty) {
        changelogPath = hit.first;
        break;
      }
    }
  }
  final changelogText = changelogPath == null ? null : text(changelogPath)?.trim();
  final v = version as String;

  return PluginPackageCheck(
    problems: problems,
    info: PluginPackageInfo(
      name: name,
      friendlyName: m[PluginManifestKeys.friendlyName] as String?,
      version: v,
      description: (m[PluginManifestKeys.description] as String? ?? '').trim(),
      category: m[PluginManifestKeys.category] as String?,
      authors: [for (final a in authors as List? ?? const []) a as String],
      engineVersionConstraint: engine,
      manifestPath: manifestPath,
      topFolder: top,
      license: license,
      licenseFile: licenseFiles.isEmpty ? null : licenseFiles.first,
      licenseFileVerdict: licenseFiles.isEmpty ? null : fileMatches[licenseFiles.first]!.verdict,
      changelogPath: changelogPath,
      changelog: changelogText == null || changelogText.isEmpty ? null : _cap(changelogText),
      releaseNotes: changelogText == null ? null : changelogSection(changelogText, v),
    ),
  );
}

/// `MIT` / `CC-BY-4.0 AND MIT` → a selection, or a problem message.
(LicenseSelection?, String?) _parseLicenseField(String value) {
  const hint = 'use an SPDX id from the free-license allow-list, or one content and one code license joined by AND';
  if (RegExp(r'\s(OR|WITH)\s', caseSensitive: false).hasMatch(value) || value.contains('(')) {
    return (null, '"license" is ${jsonEncode(value)}: $hint');
  }
  String? content, code;
  for (final id in value.split(RegExp(r'\s+AND\s+', caseSensitive: false))) {
    final info = licenseById(id.trim());
    if (info == null) {
      return (null, '"license" names ${jsonEncode(id.trim())}, which is not on the free-license allow-list '
          '(${licenseCatalogue.map((l) => l.id).join(', ')})');
    }
    if ((info.kind == LicenseKind.content ? content : code) != null) {
      return (null, '"license" is ${jsonEncode(value)}: $hint');
    }
    if (info.kind == LicenseKind.content) {
      content = info.id;
    } else {
      code = info.id;
    }
  }
  return (LicenseSelection(content: content, code: code), null);
}
