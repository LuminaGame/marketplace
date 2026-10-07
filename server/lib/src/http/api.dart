import 'dart:convert';
import 'dart:io';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shelf/shelf.dart';

import 'package:lumina_marketplace_server/src/errors.dart';
import 'package:lumina_marketplace_server/src/repositories/records.dart';
import 'package:lumina_marketplace_server/src/services/auth_service.dart';
import 'package:lumina_marketplace_server/src/services/crash_report_store.dart';
import 'package:lumina_marketplace_server/src/services/services.dart';
import 'package:lumina_marketplace_server/src/terms.dart';
import 'package:lumina_marketplace_server/src/http/middleware.dart';
import 'package:lumina_marketplace_server/src/http/router.dart';

const refreshCookie = 'lm_refresh';
const _maxJsonBytes = 1024 * 1024;

/// Per-server state the route handlers share.
class ApiContext {
  ApiContext(this.services)
      : loginFailures = RateLimiter(services.config.loginFailuresPerMinute),
        authRequests = RateLimiter(services.config.authRequestsPerMinute),
        crashReports = RateLimiter(services.config.crashReportsPerMinute),
        crashReportStore = CrashReportStore(services.config.storageDir);

  final MarketplaceServices services;
  final RateLimiter loginFailures;
  final RateLimiter authRequests;

  /// Per-IP limit on crash reports (the editor sends one per crash).
  final RateLimiter crashReports;
  final CrashReportStore crashReportStore;

  String clientIp(Request request) {
    if (services.config.trustProxy) {
      final forwarded = request.headers['x-forwarded-for'];
      if (forwarded != null && forwarded.isNotEmpty) return forwarded.split(',').first.trim();
    }
    final info = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    return info?.remoteAddress.address ?? 'unknown';
  }

  ClientInfo client(Request request) =>
      ClientInfo(ipHash: services.hashIp(clientIp(request)), userAgent: request.headers['user-agent']);

  AuthContext? optionalAuth(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return services.auth.authenticate(header.substring(7).trim());
  }

  AuthContext requireAuth(Request request) => optionalAuth(request) ?? (throw ApiException.unauthorized());

  /// Per-IP limit on every `/auth/*` request.
  void limitAuth(Request request) {
    final key = 'auth:${clientIp(request)}';
    if (!authRequests.tryAcquire(key)) throw rateLimited(authRequests.retryAfter(key));
  }

  bool get secureCookies => services.config.baseUrl?.scheme == 'https';

  String cookieHeader(String token, {bool clear = false}) {
    final maxAge = clear ? 0 : services.config.refreshTokenTtl.inSeconds;
    return '$refreshCookie=${clear ? '' : token}; Max-Age=$maxAge; Path=/api/v1/auth; HttpOnly; SameSite=Lax'
        '${secureCookies ? '; Secure' : ''}';
  }

  Response sessionResponse(IssuedSession s, {int status = 200}) =>
      jsonResponse(s.toDto().toJson(), status: status, headers: {'set-cookie': cookieHeader(s.refreshToken)});
}

Future<Map<String, Object?>> readJson(Request request) async {
  final length = request.contentLength;
  if (length != null && length > _maxJsonBytes) throw const ApiException(413, 'payload_too_large', 'JSON body too large.');
  final text = await request.readAsString(utf8);
  if (text.trim().isEmpty) return {};
  if (text.length > _maxJsonBytes) throw const ApiException(413, 'payload_too_large', 'JSON body too large.');
  final decoded = jsonDecode(text);
  if (decoded is! Map) throw const FormatException('the body must be a JSON object');
  return decoded.cast<String, Object?>();
}

String? cookie(Request request, String name) {
  final header = request.headers['cookie'];
  if (header == null) return null;
  for (final part in header.split(';')) {
    final i = part.indexOf('=');
    if (i > 0 && part.substring(0, i).trim() == name) return part.substring(i + 1).trim();
  }
  return null;
}

Object? _user(UserRecord u, {bool self = false}) => u.toDto(includeEmail: self).toJson();

Response _listing(ApiContext c, ListingRecord r) => jsonResponse(c.services.listingService.toDto(r).toJson());

/// Every API route, in one table so `openapi.yaml` can be checked against it.
final List<ApiRoute<ApiContext>> apiRoutes = [
  ApiRoute('GET', '/health', (c, r, p) => jsonResponse({'status': 'ok', 'termsVersion': publishingTerms.version})),

  // --- Accounts -----------------------------------------------------------------
  ApiRoute('POST', '/auth/signup', (c, r, p) async {
    c.limitAuth(r);
    final body = await readJson(r);
    final s = await c.services.auth.signUp(
      email: body['email'] as String? ?? '',
      username: body['username'] as String? ?? '',
      password: body['password'] as String? ?? '',
      displayName: body['displayName'] as String?,
      client: c.client(r),
    );
    c.services.log.info('signup', {'user': s.user.username});
    return c.sessionResponse(s, status: 201);
  }),
  ApiRoute('POST', '/auth/login', (c, r, p) async {
    c.limitAuth(r);
    final body = await readJson(r);
    final login = (body['login'] as String? ?? '').trim().toLowerCase();
    final ipKey = 'ip:${c.clientIp(r)}';
    final loginKey = 'login:$login';
    for (final key in [ipKey, loginKey]) {
      if (c.loginFailures.exceeded(key)) throw rateLimited(c.loginFailures.retryAfter(key));
    }
    try {
      final s = await c.services.auth.logIn(login: login, password: body['password'] as String? ?? '', client: c.client(r));
      return c.sessionResponse(s);
    } on ApiException catch (e) {
      if (e.code == 'invalid_credentials') {
        c.loginFailures
          ..record(ipKey)
          ..record(loginKey);
        c.services.log.warn('login failed', {'login': login});
      }
      rethrow;
    }
  }),
  ApiRoute('POST', '/auth/refresh', (c, r, p) async {
    c.limitAuth(r);
    final body = await readJson(r);
    final token = body['refreshToken'] as String? ?? cookie(r, refreshCookie);
    try {
      return c.sessionResponse(c.services.auth.refresh(token));
    } on ApiException catch (e) {
      throw ApiException(e.status, e.code, e.message, headers: {'set-cookie': c.cookieHeader('', clear: true)});
    }
  }),
  ApiRoute('POST', '/auth/logout', (c, r, p) async {
    final body = await readJson(r);
    AuthContext? auth;
    try {
      auth = c.optionalAuth(r);
    } on ApiException {
      auth = null;
    }
    c.services.auth.logOut(auth: auth, refreshToken: body['refreshToken'] as String? ?? cookie(r, refreshCookie));
    return Response(204, headers: {'set-cookie': c.cookieHeader('', clear: true)});
  }),
  ApiRoute('GET', '/me', (c, r, p) => jsonResponse(_user(c.requireAuth(r).user, self: true))),
  ApiRoute('PATCH', '/me', (c, r, p) async {
    final auth = c.requireAuth(r);
    final body = await readJson(r);
    return jsonResponse(_user(c.services.auth.updateProfile(auth, displayName: body['displayName'] as String?), self: true));
  }),
  ApiRoute('POST', '/me/avatar', (c, r, p) async {
    final auth = c.requireAuth(r);
    return jsonResponse(_user(await c.services.auth.setAvatar(auth, r.read()), self: true));
  }),
  ApiRoute('POST', '/me/password', (c, r, p) async {
    final auth = c.requireAuth(r);
    final body = await readJson(r);
    await c.services.auth.changePassword(auth,
        currentPassword: body['currentPassword'] as String? ?? '', newPassword: body['newPassword'] as String? ?? '');
    return jsonResponse({'status': 'ok'});
  }),
  ApiRoute('GET', '/me/listings', (c, r, p) {
    final auth = c.requireAuth(r);
    return jsonResponse({'items': [for (final l in c.services.listingService.mine(auth)) l.toJson()]});
  }),
  ApiRoute('GET', '/users/<username>', (c, r, p) => jsonResponse(c.services.listingService.profile(p['username']!).toJson())),

  // --- Catalogue ------------------------------------------------------------------
  ApiRoute('GET', '/categories', (c, r, p) => jsonResponse({
        'items': [
          for (final cat in ListingCategory.values)
            {
              'id': cat.wire,
              'label': cat.label,
              'pluralLabel': cat.pluralLabel,
              'installKind': cat.installKind.wire,
              'licenseKinds': [for (final k in cat.baseLicenseKinds) k.wire],
              'upload': cat.acceptsJson ? 'json' : 'zip',
            },
        ],
      })),
  ApiRoute('GET', '/licenses', (c, r, p) => jsonResponse({'items': [for (final l in licenseCatalogue) l.toJson()]})),
  ApiRoute('GET', '/licenses/<id>', (c, r, p) {
    final l = licenseById(p['id']);
    if (l == null) throw ApiException.notFound('Not a license on the free allow-list.');
    return jsonResponse(l.toJson());
  }),
  ApiRoute('GET', '/terms', (c, r, p) => jsonResponse(publishingTerms.toJson())),
  ApiRoute('GET', '/media/<sha256>', (c, r, p) async {
    final media = c.services.media.find(p['sha256']!);
    if (media == null) throw ApiException.notFound();
    return Response.ok(c.services.blobs.openRead(media.sha256), headers: {
      'content-type': media.contentType,
      'content-length': '${media.size}',
      'cache-control': 'public, max-age=31536000, immutable',
      'x-content-type-options': 'nosniff',
    });
  }),

  // --- Listings -------------------------------------------------------------------
  ApiRoute('GET', '/listings', (c, r, p) {
    final page = c.services.listingService.search(r.url.queryParameters);
    return jsonResponse(page.toJson((l) => l.toJson()));
  }),
  ApiRoute('POST', '/listings', (c, r, p) async {
    final auth = c.requireAuth(r);
    final listing = c.services.listingService.create(auth, await readJson(r));
    return jsonResponse(c.services.listingService.toDto(listing).toJson(), status: 201);
  }),
  ApiRoute('GET', '/listings/<id>', (c, r, p) =>
      jsonResponse(c.services.listingService.detail(p['id']!, c.optionalAuth(r)).toJson())),
  ApiRoute('PATCH', '/listings/<id>', (c, r, p) async {
    final auth = c.requireAuth(r);
    return _listing(c, c.services.listingService.update(auth, p['id']!, await readJson(r)));
  }),
  ApiRoute('POST', '/listings/<id>/screenshots', (c, r, p) async {
    final auth = c.requireAuth(r);
    return _listing(c, await c.services.listingService.addScreenshot(auth, p['id']!, r.read()));
  }),
  ApiRoute('DELETE', '/listings/<id>/screenshots/<index>', (c, r, p) {
    final auth = c.requireAuth(r);
    final index = int.tryParse(p['index']!) ?? -1;
    return _listing(c, c.services.listingService.removeScreenshot(auth, p['id']!, index));
  }),
  ApiRoute('POST', '/listings/<id>/unlist', (c, r, p) => _listing(c, c.services.listingService.ownerUnlist(c.requireAuth(r), p['id']!))),
  ApiRoute('POST', '/listings/<id>/relist', (c, r, p) => _listing(c, c.services.listingService.ownerRelist(c.requireAuth(r), p['id']!))),
  ApiRoute('POST', '/uploads', (c, r, p) async {
    final auth = c.requireAuth(r);
    final fileName = r.url.queryParameters['fileName'] ?? r.headers['x-file-name'] ?? '';
    final length = r.contentLength;
    if (length != null && length > c.services.config.maxUploadBytes) {
      await r.read().drain<void>();
      throw ApiException(413, 'payload_too_large',
          'Uploads are limited to ${c.services.config.maxUploadBytes ~/ (1024 * 1024)} MB.');
    }
    final rawCategory = r.url.queryParameters['category'];
    final category = ListingCategory.tryParse(rawCategory);
    if (rawCategory != null && category == null) {
      await r.read().drain<void>();
      throw ApiException.validation('Unknown category.', {'field': 'category'});
    }
    final upload = await c.services.listingService
        .upload(auth, r.read(), fileName: fileName, contentType: r.mimeType, category: category);
    return jsonResponse(upload.toDto().toJson(), status: 201);
  }),
  ApiRoute('POST', '/listings/<id>/versions', (c, r, p) async {
    final auth = c.requireAuth(r);
    final v = await c.services.listingService.publishVersion(auth, p['id']!, await readJson(r), c.client(r));
    return jsonResponse(v.toDto().toJson(), status: 201);
  }),
  ApiRoute('GET', '/listings/<id>/versions/<version>', (c, r, p) {
    final listing = c.services.listingService.findVisible(p['id']!, c.optionalAuth(r));
    final v = c.services.listings.findVersion(listing.id, p['version']!);
    if (v == null) throw ApiException.notFound('No such version.');
    return jsonResponse(v.toDto().toJson());
  }),
  // The preview model the listing page's 3D view loads. Public like
  // screenshots (the listing's visibility applies); not a download.
  ApiRoute('GET', '/listings/<id>/versions/<version>/preview.glb', (c, r, p) {
    final v = c.services.listingService.previewOf(p['id']!, p['version']!, c.optionalAuth(r));
    final preview = v.preview!;
    final etag = '"${preview.sha256}"';
    final headers = {
      'etag': etag,
      'cache-control': 'public, max-age=86400',
      'x-content-type-options': 'nosniff',
    };
    final match = r.headers['if-none-match'];
    if (match != null && match.split(',').map((t) => t.trim()).any((t) => t == etag || t == '*' || t == 'W/$etag')) {
      return Response.notModified(headers: headers);
    }
    return Response.ok(r.method == 'HEAD' ? null : c.services.blobs.openRead(preview.sha256), headers: {
      ...headers,
      'content-type': 'model/gltf-binary',
      'content-length': '${preview.size}',
      'x-content-sha256': preview.sha256,
    });
  }),
  ApiRoute('GET', '/listings/<id>/versions/<version>/manifest', (c, r, p) =>
      jsonResponse(c.services.listingService.manifest(c.requireAuth(r), p['id']!, p['version']!).toJson())),
  ApiRoute('GET', '/listings/<id>/versions/<version>/download', (c, r, p) {
    final (v, stream) = c.services.listingService.download(c.requireAuth(r), p['id']!, p['version']!);
    return Response.ok(stream, headers: {
      'content-type': v.archiveKind == 'json' ? 'application/json' : 'application/zip',
      'content-length': '${v.size}',
      'content-disposition': 'attachment; filename="${v.fileName.replaceAll('"', '')}"',
      'x-content-sha256': v.blobSha256,
    });
  }),
  ApiRoute('GET', '/listings/<id>/versions/<version>/files/<path|.*>', (c, r, p) async {
    final bytes = await c.services.listingService.file(c.requireAuth(r), p['id']!, p['version']!, p['path']!);
    return Response.ok(bytes, headers: {'content-type': 'application/octet-stream', 'content-length': '${bytes.length}'});
  }),

  // --- Library ----------------------------------------------------------------------
  ApiRoute('POST', '/listings/<id>/get', (c, r, p) =>
      jsonResponse(c.services.listingService.getListing(c.requireAuth(r), p['id']!).toJson())),
  ApiRoute('GET', '/library', (c, r, p) => jsonResponse({
        'items': [for (final e in c.services.listingService.libraryOf(c.requireAuth(r))) e.toJson()],
      })),

  // --- Crash reports --------------------------------------------------------------------
  // Lumina Studio's crash report screen posts here, with or without an account.
  ApiRoute('POST', '/crash-reports', (c, r, p) async {
    final key = 'crash:${c.clientIp(r)}';
    if (!c.crashReports.tryAcquire(key)) throw rateLimited(c.crashReports.retryAfter(key));
    final receipt = await c.crashReportStore.store(await readJson(r), c.client(r));
    c.services.log.info('crash report stored', {'id': receipt.id, 'file': receipt.file.path});
    return jsonResponse(receipt.toJson(), status: 201);
  }),

  // --- Reports & moderation -----------------------------------------------------------
  ApiRoute('POST', '/listings/<id>/reports', (c, r, p) async {
    final auth = c.requireAuth(r);
    final report = c.services.moderation.report(auth, p['id']!, await readJson(r));
    return jsonResponse(c.services.moderation.toDto(report).toJson(), status: 201);
  }),
  ApiRoute('GET', '/moderation/reports', (c, r, p) {
    final auth = c.requireAuth(r);
    final status = r.url.queryParameters['status'];
    final items = c.services.moderation.queue(auth, status: status == null ? null : ReportStatus.parse(status));
    return jsonResponse({'items': [for (final i in items) i.toJson()]});
  }),
  ApiRoute('POST', '/moderation/reports/<id>/resolve', (c, r, p) async {
    final auth = c.requireAuth(r);
    final report = c.services.moderation.resolve(auth, p['id']!, await readJson(r));
    return jsonResponse(c.services.moderation.toDto(report).toJson());
  }),
  ApiRoute('POST', '/moderation/listings/<id>/unlist', (c, r, p) async {
    final auth = c.requireAuth(r);
    return _listing(c, c.services.moderation.unlist(auth, p['id']!, await readJson(r)));
  }),
  ApiRoute('POST', '/moderation/listings/<id>/restore', (c, r, p) =>
      _listing(c, c.services.moderation.restore(c.requireAuth(r), p['id']!))),
  ApiRoute('POST', '/moderation/listings/<id>/feature', (c, r, p) async {
    final auth = c.requireAuth(r);
    return _listing(c, c.services.moderation.feature(auth, p['id']!, await readJson(r)));
  }),
  ApiRoute('POST', '/moderation/users/<username>/suspend', (c, r, p) async {
    final auth = c.requireAuth(r);
    return jsonResponse(_user(c.services.moderation.suspend(auth, p['username']!, await readJson(r)), self: true));
  }),
  ApiRoute('POST', '/moderation/users/<username>/unsuspend', (c, r, p) =>
      jsonResponse(_user(c.services.moderation.unsuspend(c.requireAuth(r), p['username']!), self: true))),
  ApiRoute('GET', '/moderation/audit', (c, r, p) {
    final auth = c.requireAuth(r);
    final limit = int.tryParse(r.url.queryParameters['limit'] ?? '') ?? 100;
    return jsonResponse({'items': [for (final e in c.services.moderation.auditLog(auth, limit: limit)) e.toJson()]});
  }),
  ApiRoute('POST', '/admin/users/<username>/role', (c, r, p) async {
    final auth = c.requireAuth(r);
    return jsonResponse(_user(c.services.moderation.setRole(auth, p['username']!, await readJson(r)), self: true));
  }),
];
