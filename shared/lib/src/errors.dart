/// An API error: `{"error": {"code": ..., "message": ..., "details": ...}}`
/// with the HTTP [statusCode].
class MarketplaceException implements Exception {
  const MarketplaceException(this.statusCode, this.code, this.message, {this.details = const {}});

  final int statusCode;

  /// Machine-readable: `validation_failed`, `license_required`,
  /// `attestation_required`, `price_not_supported`, `invalid_archive`,
  /// `invalid_template` (details: `problem`, `path`, `problems`),
  /// `invalid_plugin` (same details), `version_mismatch`, `license_mismatch`,
  /// `rate_limited`, `unauthorized`, `forbidden`, `not_found`, `conflict`,
  /// `account_suspended`, …
  final String code;
  final String message;
  final Map<String, Object?> details;

  factory MarketplaceException.fromJson(int statusCode, Map<String, Object?> json) {
    final error = (json['error'] as Map?)?.cast<String, Object?>() ?? const {};
    return MarketplaceException(
      statusCode,
      error['code'] as String? ?? 'error',
      error['message'] as String? ?? 'HTTP $statusCode',
      details: (error['details'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  Map<String, Object?> toJson() => {
        'error': {'code': code, 'message': message, if (details.isNotEmpty) 'details': details},
      };

  @override
  String toString() => 'MarketplaceException($statusCode $code): $message';
}
