import 'dart:io';

/// Server configuration. [MarketplaceConfig.fromEnvironment] reads it from
/// `MARKETPLACE_*` environment variables; the JWT secret comes from the
/// environment only and is never defaulted.
class MarketplaceConfig {
  MarketplaceConfig({
    this.host = '127.0.0.1',
    this.port = 8787,
    required this.databasePath,
    required this.storageDir,
    required this.jwtSecret,
    this.baseUrl,
    this.webDir,
    this.corsOrigins = defaultCorsOrigins,
    this.maxUploadBytes = 256 * 1024 * 1024,
    this.maxImageBytes = 8 * 1024 * 1024,
    this.maxPreviewBytes = 32 * 1024 * 1024,
    this.maxUnpackedBytes = 2 * 1024 * 1024 * 1024,
    this.accessTokenTtl = const Duration(minutes: 15),
    this.refreshTokenTtl = const Duration(days: 30),
    this.loginFailuresPerMinute = 10,
    this.authRequestsPerMinute = 60,
    this.crashReportsPerMinute = 10,
    this.trustProxy = false,
  }) {
    if (jwtSecret.length < 32) {
      throw ArgumentError.value('<hidden>', 'jwtSecret', 'must be at least 32 characters');
    }
  }

  /// Local development origins: any port on localhost / 127.0.0.1.
  static const defaultCorsOrigins = ['http://localhost:*', 'http://127.0.0.1:*'];

  final String host;

  /// 0 picks an ephemeral port (tests).
  final int port;
  final String databasePath;
  final String storageDir;
  final String jwtSecret;

  /// The public URL, used for the `Secure` cookie flag and logs. Defaults to
  /// `http://<host>:<port>`.
  final Uri? baseUrl;

  /// A built web front end (`flutter build web` output) to serve at `/`.
  final String? webDir;

  /// Allowed browser origins; `*` in the port position matches any port.
  final List<String> corsOrigins;
  final int maxUploadBytes;
  final int maxImageBytes;

  /// The largest preview model a version gets; bigger models get no
  /// 3D view.
  final int maxPreviewBytes;

  /// Zip-bomb guard: the total uncompressed size of an archive.
  final int maxUnpackedBytes;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  /// Failed log-ins per client IP (and per login name) per minute before
  /// `429`.
  final int loginFailuresPerMinute;

  /// Requests to `/auth/*` per client IP per minute before `429`.
  final int authRequestsPerMinute;

  /// Per-IP limit on `POST /crash-reports`.
  final int crashReportsPerMinute;

  /// Take the client IP from `X-Forwarded-For` (behind a reverse proxy).
  final bool trustProxy;

  /// `MARKETPLACE_HOST`, `MARKETPLACE_PORT`, `MARKETPLACE_DB`,
  /// `MARKETPLACE_STORAGE`, `MARKETPLACE_JWT_SECRET` (required),
  /// `MARKETPLACE_BASE_URL`, `MARKETPLACE_WEB_DIR`, `MARKETPLACE_CORS_ORIGINS`
  /// (comma-separated), `MARKETPLACE_MAX_UPLOAD_MB`, `MARKETPLACE_TRUST_PROXY`,
  /// `MARKETPLACE_CRASH_REPORTS_PER_MINUTE`.
  factory MarketplaceConfig.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final secret = env['MARKETPLACE_JWT_SECRET'];
    if (secret == null || secret.isEmpty) {
      throw StateError('MARKETPLACE_JWT_SECRET is not set (use at least 32 random characters)');
    }
    final dataDir = env['MARKETPLACE_DATA_DIR'] ?? 'data';
    return MarketplaceConfig(
      host: env['MARKETPLACE_HOST'] ?? '127.0.0.1',
      port: int.parse(env['MARKETPLACE_PORT'] ?? '8787'),
      databasePath: env['MARKETPLACE_DB'] ?? '$dataDir/marketplace.db',
      storageDir: env['MARKETPLACE_STORAGE'] ?? '$dataDir/storage',
      jwtSecret: secret,
      baseUrl: env['MARKETPLACE_BASE_URL'] == null ? null : Uri.parse(env['MARKETPLACE_BASE_URL']!),
      webDir: env['MARKETPLACE_WEB_DIR'],
      corsOrigins: env['MARKETPLACE_CORS_ORIGINS']?.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList() ??
          defaultCorsOrigins,
      maxUploadBytes: int.parse(env['MARKETPLACE_MAX_UPLOAD_MB'] ?? '256') * 1024 * 1024,
      maxPreviewBytes: int.parse(env['MARKETPLACE_MAX_PREVIEW_MB'] ?? '32') * 1024 * 1024,
      trustProxy: env['MARKETPLACE_TRUST_PROXY'] == 'true',
      crashReportsPerMinute: int.parse(env['MARKETPLACE_CRASH_REPORTS_PER_MINUTE'] ?? '10'),
    );
  }
}
