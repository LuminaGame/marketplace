import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:lumina_marketplace_server/src/util.dart';

/// A stored blob: its SHA-256 (the address) and size.
class BlobRef {
  const BlobRef(this.sha256, this.size);
  final String sha256;
  final int size;
}

class BlobTooLargeException implements Exception {
  const BlobTooLargeException(this.maxBytes);
  final int maxBytes;
  @override
  String toString() => 'BlobTooLargeException: more than $maxBytes bytes';
}

/// Content-addressed blob storage. The filesystem implementation below is for
/// self-hosting; an S3 implementation can replace it for hosting.
abstract interface class BlobStore {
  /// Stores [bytes], refusing more than [maxBytes] (throws
  /// [BlobTooLargeException] and stores nothing).
  Future<BlobRef> put(Stream<List<int>> bytes, {int? maxBytes});

  Future<bool> exists(String sha256);

  Stream<List<int>> openRead(String sha256);

  Future<Uint8List> readAll(String sha256);

  Future<int> size(String sha256);
}

/// Reads [body] into memory, throwing [BlobTooLargeException] past [maxBytes].
Future<Uint8List> collectLimited(Stream<List<int>> body, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in body) {
    if (builder.length + chunk.length > maxBytes) throw BlobTooLargeException(maxBytes);
    builder.add(chunk);
  }
  return builder.takeBytes();
}

final _shaPattern = RegExp(r'^[0-9a-f]{64}$');

/// Blobs under `<root>/blobs/<first two hex chars>/<sha256>`, written through
/// a temp file and renamed into place once the hash is known.
class FileSystemBlobStore implements BlobStore {
  FileSystemBlobStore(this.root);

  final String root;

  File _file(String sha) {
    if (!_shaPattern.hasMatch(sha)) throw ArgumentError.value(sha, 'sha256', 'not a SHA-256 hex digest');
    return File('$root/blobs/${sha.substring(0, 2)}/$sha');
  }

  @override
  Future<BlobRef> put(Stream<List<int>> bytes, {int? maxBytes}) async {
    final tmpDir = Directory('$root/tmp')..createSync(recursive: true);
    final tmp = File('${tmpDir.path}/${newId()}');
    final sink = tmp.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var size = 0;
    try {
      await for (final chunk in bytes) {
        size += chunk.length;
        if (maxBytes != null && size > maxBytes) throw BlobTooLargeException(maxBytes);
        hasher.add(chunk);
        sink.add(chunk);
      }
      hasher.close();
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      if (tmp.existsSync()) tmp.deleteSync();
      _removeEmptyTmp(tmpDir);
      rethrow;
    }
    final sha = digestSink.value.toString();
    final target = _file(sha);
    if (target.existsSync()) {
      tmp.deleteSync();
    } else {
      target.parent.createSync(recursive: true);
      tmp.renameSync(target.path);
    }
    _removeEmptyTmp(tmpDir);
    return BlobRef(sha, size);
  }

  void _removeEmptyTmp(Directory dir) {
    try {
      if (dir.listSync().isEmpty) dir.deleteSync();
    } catch (_) {}
  }

  @override
  Future<bool> exists(String sha256) async => _file(sha256).existsSync();

  @override
  Stream<List<int>> openRead(String sha256) => _file(sha256).openRead();

  @override
  Future<Uint8List> readAll(String sha256) async => _file(sha256).readAsBytes();

  @override
  Future<int> size(String sha256) async => _file(sha256).length();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
