import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../errors.dart';
import '../log.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response jsonResponse(Object? body, {int status = 200, Map<String, Object> headers = const {}}) =>
    Response(status, body: jsonEncode(body), headers: {..._jsonHeaders, ...headers});

Response errorResponse(ApiException e) => jsonResponse(e.toJson(), status: e.status, headers: e.headers);

/// Renders [ApiException]s (and malformed JSON) as the error envelope; logs
/// and hides anything else behind a 500.
Middleware errorHandling(MarketplaceLog log) => (inner) => (request) async {
      try {
        return await inner(request);
      } on ApiException catch (e) {
        return errorResponse(e);
      } on FormatException catch (e) {
        return errorResponse(ApiException(400, 'bad_request', 'Malformed request: ${e.message}'));
      } catch (e, st) {
        log.error('unhandled error', {'error': '$e', 'stack': '$st', 'path': request.url.path});
        return errorResponse(const ApiException(500, 'internal_error', 'Something went wrong on the server.'));
      }
    };

/// One structured log line per request.
Middleware requestLogging(MarketplaceLog log) => (inner) => (request) async {
      final sw = Stopwatch()..start();
      final response = await inner(request);
      log.info('request', {
        'method': request.method,
        'path': '/${request.url.path}',
        'status': response.statusCode,
        'ms': sw.elapsedMilliseconds,
      });
      return response;
    };

/// Whether [origin] matches one of [allowed] (`*` as the port matches any).
bool originAllowed(String origin, List<String> allowed) {
  for (final pattern in allowed) {
    if (pattern == origin) return true;
    if (pattern.endsWith(':*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      if (origin.startsWith(prefix) && RegExp(r'^\d+$').hasMatch(origin.substring(prefix.length))) return true;
    }
  }
  return false;
}

/// CORS with credentials for the allowed origins (the web front end in
/// development; in production it is served same-origin).
Middleware cors(List<String> allowed) => (inner) => (request) async {
      final origin = request.headers['origin'];
      final ok = origin != null && originAllowed(origin, allowed);
      final headers = <String, String>{
        if (ok) ...{
          'access-control-allow-origin': origin,
          'access-control-allow-credentials': 'true',
          'access-control-expose-headers': 'retry-after, content-length, content-disposition',
        },
        'vary': 'Origin',
      };
      if (request.method == 'OPTIONS') {
        return Response(204, headers: {
          ...headers,
          if (ok) ...{
            'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
            'access-control-allow-headers': 'authorization, content-type, x-file-name',
            'access-control-max-age': '600',
          },
        });
      }
      final response = await inner(request);
      return response.change(headers: headers);
    };

/// Sliding one-minute windows per key.
class RateLimiter {
  RateLimiter(this.limit, {this.window = const Duration(minutes: 1), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int limit;
  final Duration window;
  final DateTime Function() _clock;
  final _events = <String, List<DateTime>>{};

  List<DateTime> _live(String key) {
    final cutoff = _clock().subtract(window);
    final list = _events.putIfAbsent(key, () => []);
    list.removeWhere((t) => t.isBefore(cutoff));
    if (list.isEmpty) _events.remove(key);
    return list;
  }

  bool exceeded(String key) => _live(key).length >= limit;

  void record(String key) => _events.putIfAbsent(key, () => []).add(_clock());

  /// Records an event; false when the key was already at its limit.
  bool tryAcquire(String key) {
    if (exceeded(key)) return false;
    record(key);
    return true;
  }

  /// Seconds until the oldest event in the window expires.
  int retryAfter(String key) {
    final list = _live(key);
    if (list.isEmpty) return 1;
    final wait = list.first.add(window).difference(_clock()).inSeconds + 1;
    return wait.clamp(1, window.inSeconds);
  }
}

ApiException rateLimited(int retryAfter) => ApiException(429, 'rate_limited',
    'Too many attempts; try again in $retryAfter s.', headers: {'retry-after': '$retryAfter'}, details: {'retryAfter': retryAfter});
