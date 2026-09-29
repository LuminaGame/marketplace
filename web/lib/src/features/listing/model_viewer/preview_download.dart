import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

/// The largest preview the 3D view downloads (the server caps previews at
/// `MARKETPLACE_MAX_PREVIEW_MB`, 32 MB by default).
const int maxPreviewDownloadBytes = 64 * 1024 * 1024;

class PreviewDownloadException implements Exception {
  const PreviewDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads a listing version's preview model through [client]
/// (a streamed response: the browser's `fetch` on the web, `dart:io`
/// natively), reporting `received / total` to [onProgress].
///
/// Refuses a preview whose declared size is over [maxBytes] before
/// downloading, stops once more than the declared size arrives, and checks
/// the SHA-256 against [expectedSha256].
Future<Uint8List> downloadPreviewModel(
  MarketplaceClient client,
  String url, {
  String? expectedSha256,
  int? expectedSize,
  int maxBytes = maxPreviewDownloadBytes,
  void Function(double fraction)? onProgress,
}) async {
  if (expectedSize != null && expectedSize > maxBytes) {
    throw PreviewDownloadException(
        'This model is too large to preview (${(expectedSize / (1024 * 1024)).toStringAsFixed(1)} MB).');
  }
  final response = await client.openDownload(url);
  final total = expectedSize ?? response.contentLength;
  final limit = expectedSize ?? maxBytes;
  final builder = BytesBuilder(copy: false);
  onProgress?.call(0);
  await for (final chunk in response.stream) {
    builder.add(chunk);
    if (builder.length > limit) {
      throw const PreviewDownloadException('The preview is larger than the server said; it was not loaded.');
    }
    if (total != null && total > 0) onProgress?.call((builder.length / total).clamp(0.0, 1.0));
  }
  final bytes = builder.takeBytes();
  if (expectedSize != null && bytes.length != expectedSize) {
    throw PreviewDownloadException('The preview download was cut short (${bytes.length} of $expectedSize bytes).');
  }
  if (expectedSha256 != null && sha256.convert(bytes).toString() != expectedSha256) {
    throw const PreviewDownloadException('The preview failed its checksum; it was not loaded.');
  }
  onProgress?.call(1);
  return bytes;
}
