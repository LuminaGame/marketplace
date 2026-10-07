import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

import 'package:lumina_marketplace_server/src/util.dart';

class InvalidArchiveException implements Exception {
  const InvalidArchiveException(this.message, [this.path, this.paths = const []]);
  final String message;

  /// The (first) offending archive path.
  final String? path;

  /// Every offending archive path, when there are several.
  final List<String> paths;
  @override
  String toString() => 'InvalidArchiveException: $message${path == null ? '' : ' ($path)'}';
}

/// A validated file of an upload.
class ValidatedFile {
  const ValidatedFile(this.path, this.size, this.sha256);
  final String path;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => {'path': path, 'size': size, 'sha256': sha256};

  factory ValidatedFile.fromJson(Map<String, Object?> j) =>
      ValidatedFile(j['path'] as String, j['size'] as int, j['sha256'] as String);
}

class ValidatedArchive {
  const ValidatedArchive(this.files, this.detectedKinds, {this.skipped = const {}, this.repacked});
  final List<ValidatedFile> files;
  final Set<LicenseKind> detectedKinds;

  /// Generated folders left out (`<folder>/` → file count).
  final Map<String, int> skipped;

  /// The archive without the [skipped] folders (what is stored), or null when
  /// nothing was left out.
  final List<int>? repacked;
}

/// Folders a plugin package's tools generate: left out of a plugin
/// upload anywhere in the package, and `build/` at the package root.
const generatedFolderNames = {'.dart_tool', '.git', '.idea', '.vscode'};

/// The generated folder (archive path ending in `/`) [path] lives in, or
/// null. [top] is the archive's single top folder, if any.
String? generatedFolderOf(String path, String? top) {
  final prefix = top == null ? '' : '$top/';
  final segments = path.substring(prefix.length).split('/');
  for (var i = 0; i < segments.length - 1; i++) {
    if (generatedFolderNames.contains(segments[i]) || (i == 0 && segments[i] == 'build')) {
      return '$prefix${segments.take(i + 1).join('/')}/';
    }
  }
  return null;
}

/// At most ten [paths], then how many more.
String listPaths(List<String> paths) =>
    paths.length <= 10 ? paths.join(', ') : '${paths.take(10).join(', ')} and ${paths.length - 10} more';

/// Extensions that make an upload need a content license.
const contentExtensions = {
  'glb', 'gltf', 'bin', 'obj', 'mtl', 'fbx', 'dae', 'lmas', 'filamesh', //
  'png', 'jpg', 'jpeg', 'tga', 'webp', 'ktx', 'ktx2', 'hdr', 'exr', 'svg',
  'wav', 'ogg', 'mp3', 'flac', 'ttf', 'otf',
};

/// Extensions that make an upload need a code license.
const codeExtensions = {'dart', 'c', 'cc', 'cpp', 'h', 'hpp', 'js', 'glsl', 'vert', 'frag', 'comp', 'mat'};

/// Allowed, but neither content nor code on their own (`.lmplugin` is a
/// Lumina plugin's JSON manifest, which every plugin listing carries).
const neutralExtensions = {'json', 'yaml', 'yml', 'md', 'txt', 'lmproject', 'lmplugin', 'csv', 'lock'};

/// Extensionless file names that are allowed.
const allowedBareNames = {'license', 'licence', 'readme', 'notice', 'changelog', 'copying', 'authors'};

/// Package housekeeping dot files that are allowed: a plugin or
/// project folder carries them.
const allowedDotNames = {'.gitignore', '.gitattributes', '.metadata', '.pubignore'};

/// Validates version archives: every entry must be a regular file with a safe
/// relative path (no `..`, no absolute paths, no drive letters, no
/// backslashes, no symlinks) and an allowed extension; the total uncompressed
/// size is capped (zip-bomb guard) and CRCs are verified. A refusal names every
/// offending path.
class ZipValidator {
  const ZipValidator({required this.maxUnpackedBytes, this.maxEntries = 10000});

  final int maxUnpackedBytes;
  final int maxEntries;

  /// [beforeContents] sees every file path once the paths are known to be
  /// safe, before any extension check or content read; it may throw (the
  /// game template rules name a stray `build/` this way).
  ///
  /// With [skipGenerated] (plugin uploads) the folders tools generate
  /// ([generatedFolderOf]: `.dart_tool/`, `.git/`, `.idea/`, `.vscode/`, a
  /// root `build/`) are left out — never extracted or checked — and the
  /// result carries the archive repacked without them.
  ValidatedArchive validate(List<int> bytes,
      {void Function(List<String> filePaths)? beforeContents, bool skipGenerated = false}) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (e) {
      throw const InvalidArchiveException('not a valid zip archive');
    }
    if (archive.length > maxEntries) throw InvalidArchiveException('more than $maxEntries entries');
    var declared = 0;
    for (final entry in archive) {
      declared += entry.size;
      if (declared > maxUnpackedBytes) {
        throw InvalidArchiveException('unpacks to more than $maxUnpackedBytes bytes');
      }
    }
    final all = <(ArchiveFile, String)>[];
    for (final entry in archive) {
      final name = entry.name;
      final path = entry.isDirectory && name.endsWith('/') ? name.substring(0, name.length - 1) : name;
      if (!isSafeRelativePath(path)) throw InvalidArchiveException('unsafe path: $name', name);
      all.add((entry, path));
    }
    final top = skipGenerated ? singleTopFolder([for (final (e, p) in all) if (!e.isDirectory) p]) : null;
    final skipped = <String, int>{};
    final entries = <(ArchiveFile, String)>[];
    for (final (entry, path) in all) {
      final generated = skipGenerated ? generatedFolderOf(entry.isDirectory ? '$path/x' : path, top) : null;
      if (generated != null) {
        if (!entry.isDirectory) skipped[generated] = (skipped[generated] ?? 0) + 1;
        continue;
      }
      if (entry.isSymbolicLink) throw InvalidArchiveException('symbolic links are not allowed: ${entry.name}', entry.name);
      if (!entry.isDirectory) entries.add((entry, path));
    }
    beforeContents?.call([for (final (_, path) in entries) path]);

    // Every disallowed file, grouped by reason.
    final refused = <String, List<String>>{};
    final kinds = <LicenseKind>{};
    for (final (_, path) in entries) {
      final (kind, reason) = _classify(path);
      if (reason != null) {
        (refused[reason] ??= []).add(path);
      } else if (kind != null) {
        kinds.add(kind);
      }
    }
    if (refused.isNotEmpty) {
      final paths = [for (final list in refused.values) ...list];
      throw InvalidArchiveException(
          [for (final MapEntry(key: reason, value: list) in refused.entries) '$reason (${listPaths(list)})'].join('; '),
          paths.first,
          paths);
    }

    final files = <ValidatedFile>[];
    final contents = <String, List<int>>{};
    final seen = <String>{};
    var unpacked = 0;
    for (final (entry, path) in entries) {
      final name = entry.name;
      if (!seen.add(path.toLowerCase())) throw InvalidArchiveException('duplicate path: $name', name);
      final content = entry.readBytes();
      if (content == null) throw InvalidArchiveException('unreadable entry: $name', name);
      unpacked += content.length;
      if (unpacked > maxUnpackedBytes) throw InvalidArchiveException('unpacks to more than $maxUnpackedBytes bytes');
      files.add(ValidatedFile(path, content.length, sha256Hex(content)));
      if (skipped.isNotEmpty) contents[path] = content;
    }
    if (files.isEmpty) throw const InvalidArchiveException('the archive has no files');
    files.sort((a, b) => a.path.compareTo(b.path));
    List<int>? repacked;
    if (skipped.isNotEmpty) {
      final out = Archive();
      for (final f in files) {
        out.addFile(ArchiveFile.bytes(f.path, contents[f.path]!));
      }
      repacked = ZipEncoder().encode(out);
    }
    return ValidatedArchive(files, kinds,
        skipped: Map.fromEntries(skipped.entries.toList()..sort((a, b) => a.key.compareTo(b.key))), repacked: repacked);
  }

  /// Validates a theme upload: a UTF-8 JSON object.
  ValidatedArchive validateJson(List<int> bytes, String fileName) {
    try {
      if (jsonDecode(utf8.decode(bytes)) is! Map) throw const FormatException();
    } catch (_) {
      throw const InvalidArchiveException('not a JSON object');
    }
    return ValidatedArchive([ValidatedFile(fileName, bytes.length, sha256Hex(bytes))], {LicenseKind.content});
  }

  /// The license kind a file needs (null for neutral files), or why it is not
  /// allowed.
  static (LicenseKind?, String?) _classify(String path) {
    final name = path.split('/').last;
    if (allowedDotNames.contains(name.toLowerCase())) return (null, null);
    final dot = name.lastIndexOf('.');
    if (dot <= 0) {
      if (allowedBareNames.contains(name.toLowerCase())) return (null, null);
      return (null, 'files without an allowed extension are not allowed');
    }
    final ext = name.substring(dot + 1).toLowerCase();
    if (contentExtensions.contains(ext)) return (LicenseKind.content, null);
    if (codeExtensions.contains(ext)) return (LicenseKind.code, null);
    if (neutralExtensions.contains(ext)) return (null, null);
    return (null, '.$ext files are not allowed');
  }
}

/// Extracts one file from a zip, or null.
List<int>? extractZipEntry(List<int> zip, String path) {
  final archive = ZipDecoder().decodeBytes(zip);
  for (final entry in archive) {
    if (entry.isFile && entry.name == path) return entry.readBytes();
  }
  return null;
}

/// `image/png` or `image/jpeg` from magic bytes, else null.
String? sniffImageType(List<int> bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
      bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'image/jpeg';
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}
