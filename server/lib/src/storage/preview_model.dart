import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

/// Where a preview model came from.
enum PreviewSourceKind {
  /// A `.glb` in the archive, as uploaded.
  glb,

  /// A `.gltf` (with external buffers / images) packed into one GLB.
  gltf,

  /// A Lumina mesh asset's (`.lmas`) GLB payload.
  lmas,
}

/// The model the listing page's 3D view shows for a version: one
/// self-contained glTF binary derived from the version's archive.
class PreviewModel {
  const PreviewModel(this.bytes, this.sourcePath, this.kind);
  final Uint8List bytes;

  /// The archive path it was derived from.
  final String sourcePath;
  final PreviewSourceKind kind;
}

const _glbMagic = 0x46546C67; // 'glTF'
const _jsonChunk = 0x4E4F534A; // 'JSON'
const _binChunk = 0x004E4942; // 'BIN\0'

/// Whether [bytes] is a glTF 2 binary whose header matches its size.
bool isGlb(List<int> bytes) {
  if (bytes.length < 20) return false;
  final data = ByteData.sublistView(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  return data.getUint32(0, Endian.little) == _glbMagic &&
      data.getUint32(4, Endian.little) == 2 &&
      data.getUint32(8, Endian.little) == bytes.length &&
      data.getUint32(16, Endian.little) == _jsonChunk;
}

/// The preview model of an archive given as path → bytes: the largest
/// candidate no bigger than [maxBytes] (ties go to the first path), or null.
///
/// Candidates are every valid `.glb`, every `.gltf` whose buffers and images
/// resolve (data URIs, or safe relative paths inside the archive) packed into
/// a GLB, and every mesh `.lmas` whose payload is a GLB — unless the import's
/// `.entity.glb` companion sits next to it (that one is a candidate already).
PreviewModel? derivePreviewModel(Map<String, List<int>> files, {required int maxBytes}) {
  final paths = files.keys.toList()..sort();
  final lower = {for (final p in paths) p.toLowerCase()};
  PreviewModel? best;
  void consider(PreviewModel candidate) {
    if (candidate.bytes.length > maxBytes || !isGlb(candidate.bytes)) return;
    if (best == null || candidate.bytes.length > best!.bytes.length) best = candidate;
  }

  for (final path in paths) {
    final name = path.toLowerCase();
    final bytes = files[path]!;
    if (name.endsWith('.glb')) {
      consider(PreviewModel(Uint8List.fromList(bytes), path, PreviewSourceKind.glb));
    } else if (name.endsWith('.gltf')) {
      final packed = _packGltf(path, bytes, (p) => files[p]);
      if (packed != null) consider(PreviewModel(packed, path, PreviewSourceKind.gltf));
    } else if (name.endsWith('.lmas')) {
      final companion = '${name.substring(0, name.length - '.lmas'.length)}.entity.glb';
      if (lower.contains(companion)) continue;
      final payload = _lmasMeshPayload(bytes);
      if (payload != null) consider(PreviewModel(payload, path, PreviewSourceKind.lmas));
    }
  }
  return best;
}

/// [derivePreviewModel] over a zip archive's files.
PreviewModel? derivePreviewModelFromZip(List<int> zip, {required int maxBytes}) {
  final archive = ZipDecoder().decodeBytes(zip);
  final files = <String, List<int>>{};
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.toLowerCase();
    // Only what a candidate can be made of.
    if (!(name.endsWith('.glb') || name.endsWith('.gltf') || name.endsWith('.lmas') || name.endsWith('.bin') ||
        _imageTypes.keys.any(name.endsWith))) {
      continue;
    }
    final bytes = entry.readBytes();
    if (bytes != null) files[entry.name] = bytes;
  }
  return derivePreviewModel(files, maxBytes: maxBytes);
}

/// A mesh `.lmas` (`LMAS` + JSON, type `filamesh` / `filameshSk`) payload
/// that is a GLB, else null.
Uint8List? _lmasMeshPayload(List<int> bytes) {
  try {
    final hasMagic = bytes.length >= 4 && ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'LMAS';
    final doc = jsonDecode(utf8.decode(hasMagic ? bytes.sublist(4) : bytes));
    if (doc is! Map || (doc['type'] != 'filamesh' && doc['type'] != 'filameshSk')) return null;
    final payload = doc['raw_payload'];
    if (payload is! String || payload.isEmpty) return null;
    final glb = base64Decode(payload);
    return isGlb(glb) ? glb : null;
  } catch (_) {
    return null;
  }
}

const _imageTypes = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.ktx2': 'image/ktx2'};

/// The archive path [uri] names relative to the `.gltf` at [gltfPath], or
/// null when it escapes the archive.
String? _resolve(String gltfPath, String uri) {
  final String decoded;
  try {
    decoded = Uri.decodeComponent(uri);
  } catch (_) {
    return null;
  }
  if (decoded.contains('://') || decoded.startsWith('/') || decoded.contains('\\')) return null;
  final dir = gltfPath.contains('/') ? gltfPath.substring(0, gltfPath.lastIndexOf('/') + 1) : '';
  final parts = <String>[];
  for (final part in '$dir$decoded'.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  final path = parts.join('/');
  return isSafeRelativePath(path) ? path : null;
}

/// Bytes of a `data:` URI, else null.
Uint8List? _dataUri(String uri) {
  if (!uri.startsWith('data:')) return null;
  final comma = uri.indexOf(',');
  if (comma < 0 || !uri.substring(0, comma).endsWith(';base64')) return null;
  try {
    return base64Decode(uri.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// Packs the `.gltf` at [path] into a GLB: its buffers become one BIN chunk
/// (each 4-byte aligned) and URI images become buffer views in it. Null when
/// anything it references cannot be resolved.
Uint8List? _packGltf(String path, List<int> source, List<int>? Function(String path) read) {
  try {
    return _pack(path, source, read);
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

Uint8List? _pack(String path, List<int> source, List<int>? Function(String path) read) {
  final Map<String, Object?> json;
  try {
    final decoded = jsonDecode(utf8.decode(source));
    if (decoded is! Map<String, Object?>) return null;
    json = decoded;
  } catch (_) {
    return null;
  }
  final asset = json['asset'];
  if (asset is! Map || '${asset['version']}'.split('.').first != '2') return null;

  final bin = BytesBuilder(copy: false);
  void align() {
    while (bin.length % 4 != 0) {
      bin.addByte(0);
    }
  }

  final buffers = (json['buffers'] as List? ?? const []).cast<Object?>();
  final offsets = <int>[];
  for (final b in buffers) {
    if (b is! Map) return null;
    final uri = b['uri'];
    Uint8List? data;
    if (uri is String) {
      data = _dataUri(uri);
      if (data == null) {
        final resolved = _resolve(path, uri);
        final bytes = resolved == null ? null : read(resolved);
        if (bytes == null) return null;
        data = Uint8List.fromList(bytes);
      }
    } else {
      return null; // a GLB-only buffer inside a .gltf is malformed
    }
    final length = b['byteLength'];
    if (length is! int || data.length < length) return null;
    align();
    offsets.add(bin.length);
    bin.add(data.sublist(0, length));
  }

  final views = (json['bufferViews'] as List? ?? const []).cast<Object?>().map((v) {
    if (v is! Map) throw const FormatException();
    final view = Map<String, Object?>.from(v);
    final buffer = view['buffer'];
    if (buffer is! int || buffer < 0 || buffer >= offsets.length) throw const FormatException();
    view['buffer'] = 0;
    view['byteOffset'] = offsets[buffer] + ((view['byteOffset'] as int?) ?? 0);
    return view;
  }).toList();

  final images = <Object?>[];
  for (final image in (json['images'] as List? ?? const []).cast<Object?>()) {
    if (image is! Map) return null;
    final copy = Map<String, Object?>.from(image);
    final uri = copy['uri'];
    if (uri is String) {
      var data = _dataUri(uri);
      String? mime = data == null ? null : uri.substring(5, uri.indexOf(';'));
      if (data == null) {
        final resolved = _resolve(path, uri);
        final bytes = resolved == null ? null : read(resolved);
        if (bytes == null) return null;
        data = Uint8List.fromList(bytes);
        final ext = resolved!.contains('.') ? resolved.substring(resolved.lastIndexOf('.')).toLowerCase() : '';
        mime = _imageTypes[ext];
      }
      if (mime == null) return null;
      align();
      views.add({'buffer': 0, 'byteOffset': bin.length, 'byteLength': data.length});
      bin.add(data);
      copy
        ..remove('uri')
        ..['bufferView'] = views.length - 1
        ..['mimeType'] = mime;
    }
    images.add(copy);
  }
  align();

  final packed = Map<String, Object?>.from(json)
    ..['bufferViews'] = views
    ..remove('images');
  if (images.isNotEmpty) packed['images'] = images;
  final binBytes = bin.takeBytes();
  if (binBytes.isEmpty) {
    packed.remove('buffers');
  } else {
    packed['buffers'] = [
      {'byteLength': binBytes.length},
    ];
  }
  if (views.isEmpty) packed.remove('bufferViews');
  return _glb(packed, binBytes);
}

/// A GLB container for [json] and [bin].
Uint8List _glb(Map<String, Object?> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json)).toList();
  while (jsonBytes.length % 4 != 0) {
    jsonBytes.add(0x20);
  }
  final total = 12 + 8 + jsonBytes.length + (bin.isEmpty ? 0 : 8 + bin.length);
  final out = ByteData(total);
  out
    ..setUint32(0, _glbMagic, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, total, Endian.little)
    ..setUint32(12, jsonBytes.length, Endian.little)
    ..setUint32(16, _jsonChunk, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  if (bin.isNotEmpty) {
    final at = 20 + jsonBytes.length;
    out
      ..setUint32(at, bin.length, Endian.little)
      ..setUint32(at + 4, _binChunk, Endian.little);
    bytes.setRange(at + 8, at + 8 + bin.length, bin);
  }
  return bytes;
}
