import 'dart:async';

import 'package:shelf/shelf.dart';

import 'package:lumina_marketplace_server/src/errors.dart';

typedef RouteHandler<C> = FutureOr<Response> Function(C context, Request request, Map<String, String> params);

/// One API route. [path] uses `<name>` segments; `<name|.*>` matches the rest
/// of the path (slashes included).
class ApiRoute<C> {
  ApiRoute(this.method, this.path, this.handler) : _pattern = _compile(path), _names = _paramNames(path);

  final String method;
  final String path;
  final RouteHandler<C> handler;
  final RegExp _pattern;
  final List<String> _names;

  /// The OpenAPI spelling: `/listings/<id>` → `/api/v1/listings/{id}`.
  String get openApiPath => '/api/v1${path.replaceAllMapped(RegExp(r'<(\w+)(\|[^>]*)?>'), (m) => '{${m[1]}}')}';

  static List<String> _paramNames(String path) =>
      [for (final m in RegExp(r'<(\w+)(\|[^>]*)?>').allMatches(path)) m[1]!];

  static RegExp _compile(String path) {
    final buffer = StringBuffer('^');
    var last = 0;
    for (final m in RegExp(r'<(\w+)(\|([^>]*))?>').allMatches(path)) {
      buffer.write(RegExp.escape(path.substring(last, m.start)));
      buffer.write('(${m[3] ?? '[^/]+'})');
      last = m.end;
    }
    buffer.write(RegExp.escape(path.substring(last)));
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  Map<String, String>? match(String requestPath) {
    final m = _pattern.firstMatch(requestPath);
    if (m == null) return null;
    return {for (var i = 0; i < _names.length; i++) _names[i]: Uri.decodeComponent(m[i + 1]!)};
  }
}

/// Dispatches `/api/v1/...` requests to [routes]; 404 / 405 as API errors.
Handler apiRouter<C>(C context, List<ApiRoute<C>> routes) => (Request request) {
      final path = '/${request.url.path}'.replaceFirst('/api/v1', '');
      var pathMatched = false;
      for (final route in routes) {
        final params = route.match(path);
        if (params == null) continue;
        pathMatched = true;
        if (route.method == request.method || (request.method == 'HEAD' && route.method == 'GET')) {
          return route.handler(context, request, params);
        }
      }
      if (pathMatched) throw const ApiException(405, 'method_not_allowed', 'Method not allowed.');
      throw ApiException.notFound('No such API route.');
    };
