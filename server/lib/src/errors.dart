import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

/// Thrown by services and middleware; the HTTP layer renders it as the
/// `{"error": {...}}` envelope with [status].
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, {this.details = const {}, this.headers = const {}});

  final int status;
  final String code;
  final String message;
  final Map<String, Object?> details;
  final Map<String, String> headers;

  factory ApiException.validation(String message, [Map<String, Object?> details = const {}]) =>
      ApiException(422, 'validation_failed', message, details: details);
  factory ApiException.unauthorized([String message = 'Sign in first.']) =>
      ApiException(401, 'unauthorized', message);
  factory ApiException.forbidden([String message = 'You are not allowed to do that.']) =>
      ApiException(403, 'forbidden', message);
  factory ApiException.notFound([String message = 'Not found.']) => ApiException(404, 'not_found', message);
  factory ApiException.conflict(String message) => ApiException(409, 'conflict', message);

  Map<String, Object?> toJson() => MarketplaceException(status, code, message, details: details).toJson();

  @override
  String toString() => 'ApiException($status $code): $message';
}
