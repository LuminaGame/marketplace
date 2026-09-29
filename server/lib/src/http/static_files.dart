import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'map': 'application/json',
  'txt': 'text/plain; charset=utf-8',
  'bin': 'application/octet-stream',
  'frag': 'text/plain; charset=utf-8',
};

String contentTypeFor(String path) =>
    _types[p.extension(path).replaceFirst('.', '').toLowerCase()] ?? 'application/octet-stream';

/// The flutter_filament WebAssembly module and its loader, copied
/// into the build under `filament/`: large and rarely rebuilt, so cached for a
/// day and revalidated by ETag after that.
bool _isRenderer(String relative) => relative.startsWith('filament/') || relative.endsWith('.wasm');

/// Serves a built Flutter web app from [root]. Unknown paths without a file
/// extension fall back to `index.html` (client-side routes); nothing outside
/// [root] is ever served.
Handler webAppHandler(String root) {
  final base = p.normalize(p.absolute(root));
  return (Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') return Response.notFound('Not found');
    final segments = request.url.pathSegments;
    if (segments.any((s) => s == '..' || s.contains('/') || s.contains('\\') || s.contains('\u0000'))) {
      return Response.notFound('Not found');
    }
    final relative = segments.isEmpty ? 'index.html' : p.joinAll(segments);
    final candidate = p.normalize(p.join(base, relative));
    if (!p.isWithin(base, candidate) && candidate != base) return Response.notFound('Not found');
    var file = File(candidate);
    if (!file.existsSync()) {
      if (p.extension(relative).isNotEmpty) return Response.notFound('Not found');
      file = File(p.join(base, 'index.html'));
      if (!file.existsSync()) return Response.notFound('Not found');
    }
    final isIndex = p.basename(file.path) == 'index.html';
    final stat = file.statSync();
    // A strong validator from size + mtime: a rebuilt file gets a new one.
    final etag = '"${stat.size.toRadixString(16)}-${stat.modified.microsecondsSinceEpoch.toRadixString(16)}"';
    final headers = {
      'etag': etag,
      'cache-control': isIndex ? 'no-cache' : (_isRenderer(segments.join('/')) ? 'public, max-age=86400' : 'public, max-age=3600'),
    };
    final match = request.headers['if-none-match'];
    if (match != null && match.split(',').map((t) => t.trim()).contains(etag)) {
      return Response.notModified(headers: headers);
    }
    return Response.ok(request.method == 'HEAD' ? null : file.openRead(), headers: {
      ...headers,
      'content-type': contentTypeFor(file.path),
      'content-length': '${stat.size}',
    });
  };
}
