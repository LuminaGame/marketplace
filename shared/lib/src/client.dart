import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:lumina_marketplace_shared/src/categories.dart';
import 'package:lumina_marketplace_shared/src/dto.dart';
import 'package:lumina_marketplace_shared/src/errors.dart';
import 'package:lumina_marketplace_shared/src/licenses.dart';

/// The Lumina Marketplace API client, shared by the web front end and Lumina
/// Studio.
///
/// Session handling: sign-up / log-in return an access token (kept in memory,
/// sent as `Authorization: Bearer`) and a refresh token. Native clients keep
/// the refresh token from the response body ([keepRefreshToken], the default)
/// and may persist it through [refreshToken] / [restoreSession]. Browsers pass
/// `keepRefreshToken: false` and an `http.Client` that sends credentials
/// (`BrowserClient()..withCredentials = true`): the refresh token then lives
/// only in the server's httpOnly `lm_refresh` cookie. An expired access token
/// is refreshed once, transparently, on a 401.
class MarketplaceClient {
  MarketplaceClient({required Uri baseUrl, http.Client? httpClient, this.keepRefreshToken = true})
      : baseUrl = baseUrl.path.endsWith('/') ? baseUrl : baseUrl.replace(path: '${baseUrl.path}/'),
        _http = httpClient ?? http.Client();

  /// The server root, e.g. `http://127.0.0.1:8787/`. The API lives under
  /// [apiPrefix].
  final Uri baseUrl;
  final http.Client _http;
  final bool keepRefreshToken;

  static const apiPrefix = 'api/v1';

  String? _accessToken;
  String? _refreshToken;
  MarketplaceUser? _user;
  final _sessionChanges = StreamController<MarketplaceUser?>.broadcast();

  /// The signed-in user, or null.
  MarketplaceUser? get currentUser => _user;
  bool get isSignedIn => _accessToken != null;
  String? get accessToken => _accessToken;

  /// The refresh token (native clients only), for persisting a session.
  String? get refreshToken => _refreshToken;

  /// Emits the user on sign-in/refresh/profile change and null on sign-out
  /// (including a refused refresh).
  Stream<MarketplaceUser?> get sessionChanges => _sessionChanges.stream;

  /// Resolves a server-relative URL (`/api/v1/media/…`) against [baseUrl].
  Uri resolve(String url) => baseUrl.resolve(url.startsWith('/') ? url.substring(1) : url);

  Uri _api(String path, [Map<String, String>? query]) {
    final uri = baseUrl.resolve('$apiPrefix$path');
    return query == null || query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  void close() {
    _sessionChanges.close();
    _http.close();
  }

  // --- Transport ---------------------------------------------------------------

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? json,
    List<int>? bytes,
    String? contentType,
    bool authenticate = true,
    bool retryOnExpiry = true,
  }) async {
    final request = http.Request(method, _api(path, query));
    if (authenticate && _accessToken != null) request.headers['Authorization'] = 'Bearer $_accessToken';
    if (json != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(json);
    } else if (bytes != null) {
      request.headers['Content-Type'] = contentType ?? 'application/octet-stream';
      request.bodyBytes = bytes;
    }
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode == 401 && retryOnExpiry && authenticate && _accessToken != null) {
      final code = _errorCode(response);
      if (code == 'token_expired' && await _tryRefresh()) {
        return _send(method, path,
            query: query, json: json, bytes: bytes, contentType: contentType, retryOnExpiry: false);
      }
    }
    return response;
  }

  String? _errorCode(http.Response r) {
    try {
      return ((jsonDecode(r.body) as Map)['error'] as Map)['code'] as String?;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _decode(http.Response r) {
    if (r.statusCode >= 400) throw _error(r);
    if (r.body.isEmpty) return const {};
    return (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>();
  }

  MarketplaceException _error(http.Response r) {
    try {
      return MarketplaceException.fromJson(r.statusCode, (jsonDecode(r.body) as Map).cast<String, Object?>());
    } catch (_) {
      return MarketplaceException(r.statusCode, 'http_${r.statusCode}', r.body.isEmpty ? 'HTTP ${r.statusCode}' : r.body);
    }
  }

  Future<Map<String, Object?>> _json(String method, String path,
          {Map<String, String>? query, Object? json, List<int>? bytes, String? contentType}) async =>
      _decode(await _send(method, path, query: query, json: json, bytes: bytes, contentType: contentType));

  AuthSession _adopt(Map<String, Object?> body) {
    final session = AuthSession.fromJson(body);
    _accessToken = session.accessToken;
    _refreshToken = keepRefreshToken ? session.refreshToken : null;
    _user = session.user;
    _sessionChanges.add(_user);
    return session;
  }

  void _clearSession() {
    final had = _accessToken != null || _user != null;
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    if (had) _sessionChanges.add(null);
  }

  Future<bool> _tryRefresh() async {
    try {
      await refresh();
      return true;
    } on MarketplaceException {
      return false;
    }
  }

  // --- Accounts ----------------------------------------------------------------

  Future<AuthSession> signUp({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async =>
      _adopt(await _json('POST', '/auth/signup', json: {
        'email': email,
        'username': username,
        'password': password,
        'displayName': ?displayName,
      }));

  /// [login] is an email or a username.
  Future<AuthSession> logIn({required String login, required String password}) async =>
      _adopt(await _json('POST', '/auth/login', json: {'login': login, 'password': password}));

  /// Rotates the refresh token (from memory, or the browser cookie) and gets a
  /// new access token. Clears the session when refused.
  Future<AuthSession> refresh() async {
    final r = await _send('POST', '/auth/refresh',
        json: {if (_refreshToken != null) 'refreshToken': _refreshToken}, authenticate: false);
    if (r.statusCode >= 400) {
      _clearSession();
      throw _error(r);
    }
    return _adopt(_decode(r));
  }

  /// Signs back in with a persisted refresh token (native) or the browser's
  /// cookie (web, [refreshToken] null). Returns null when there is no valid
  /// session.
  Future<AuthSession?> restoreSession({String? refreshToken}) async {
    if (refreshToken != null) _refreshToken = refreshToken;
    try {
      return await refresh();
    } on MarketplaceException {
      return null;
    }
  }

  /// Revokes the session server-side (the refresh token and every access
  /// token issued with it) and forgets it locally.
  Future<void> logOut() async {
    try {
      final r = await _send('POST', '/auth/logout',
          json: {if (_refreshToken != null) 'refreshToken': _refreshToken}, retryOnExpiry: false);
      if (r.statusCode >= 400 && r.statusCode != 401) throw _error(r);
    } finally {
      _clearSession();
    }
  }

  Future<MarketplaceUser> me() async {
    final user = MarketplaceUser.fromJson(await _json('GET', '/me'));
    _user = user;
    return user;
  }

  Future<MarketplaceUser> updateProfile({String? displayName}) async {
    final user = MarketplaceUser.fromJson(await _json('PATCH', '/me', json: {'displayName': ?displayName}));
    _user = user;
    _sessionChanges.add(user);
    return user;
  }

  /// PNG or JPEG bytes.
  Future<MarketplaceUser> uploadAvatar(List<int> bytes, {String contentType = 'image/png'}) async {
    final user = MarketplaceUser.fromJson(await _json('POST', '/me/avatar', bytes: bytes, contentType: contentType));
    _user = user;
    _sessionChanges.add(user);
    return user;
  }

  /// Changes the password and revokes every other session.
  Future<void> changePassword({required String currentPassword, required String newPassword}) async =>
      _json('POST', '/me/password', json: {'currentPassword': currentPassword, 'newPassword': newPassword});

  Future<PublisherProfile> publisher(String username) async =>
      PublisherProfile.fromJson(await _json('GET', '/users/${Uri.encodeComponent(username)}'));

  // --- Catalogue ---------------------------------------------------------------

  Future<List<LicenseInfo>> licenses() async {
    final body = await _json('GET', '/licenses');
    return [for (final l in body['items'] as List) LicenseInfo.fromJson((l as Map).cast())];
  }

  Future<Terms> terms() async => Terms.fromJson(await _json('GET', '/terms'));

  /// Sends a Lumina Studio crash report (no account needed). [report] holds
  /// `error` (required), `kind` (`uncaught`, `previous_run` or `plugin_crash`; the last with an integer `exitCode`), `stackTrace`,
  /// `description`, `email`, `release`, `commit`, `editor`, `platform`,
  /// `osVersion`, `gpu`, `filament`, `project`, `logTail` (strings),
  /// `reportId` and `createdAt`; the server keeps it as a file.
  Future<CrashReportReceipt> submitCrashReport(Map<String, Object?> report) async =>
      CrashReportReceipt.fromJson(await _json('POST', '/crash-reports', json: report));

  Future<ResultPage<Listing>> search(SearchQuery query) async => ResultPage.fromJson(
        await _json('GET', '/listings', query: query.toQueryParameters()),
        Listing.fromJson,
      );

  /// A listing page by id or slug, with every version.
  Future<Listing> listing(String idOrSlug) async =>
      Listing.fromJson(await _json('GET', '/listings/${Uri.encodeComponent(idOrSlug)}'));

  // --- Publishing ---------------------------------------------------------------

  Future<Listing> createListing(NewListing listing) async =>
      Listing.fromJson(await _json('POST', '/listings', json: listing.toJson()));

  Future<Listing> updateListing(
    String id, {
    String? title,
    String? description,
    List<String>? tags,
    String? engineVersion,
    ListingCategory? category,
  }) async =>
      Listing.fromJson(await _json('PATCH', '/listings/$id', json: {
        'title': ?title,
        'description': ?description,
        'tags': ?tags,
        'engineVersion': ?engineVersion,
        'category': ?category?.wire,
      }));

  /// The caller's listings in every status.
  Future<List<Listing>> myListings() async {
    final body = await _json('GET', '/me/listings');
    return [for (final l in body['items'] as List) Listing.fromJson((l as Map).cast())];
  }

  Future<Listing> addScreenshot(String listingId, List<int> bytes, {String contentType = 'image/png'}) async =>
      Listing.fromJson(await _json('POST', '/listings/$listingId/screenshots', bytes: bytes, contentType: contentType));

  Future<Listing> removeScreenshot(String listingId, int index) async =>
      Listing.fromJson(await _json('DELETE', '/listings/$listingId/screenshots/$index'));

  /// Uploads a version archive (`.zip`) or a theme (`.json`); the server
  /// validates it and returns what it found. With [category], the server also
  /// checks the rules of that category that need only the archive — for
  /// [ListingCategory.gameTemplate] the game template format
  /// (`422 invalid_template`) — so a broken upload is refused before publish.
  Future<UploadInfo> upload(List<int> bytes, {required String fileName, ListingCategory? category}) async =>
      UploadInfo.fromJson(await _json(
        'POST',
        '/uploads',
        query: {'fileName': fileName, 'category': ?category?.wire},
        bytes: bytes,
        contentType: fileName.toLowerCase().endsWith('.json') ? 'application/json' : 'application/zip',
      ));

  Future<ListingVersion> publishVersion(String listingId, NewVersion version) async =>
      ListingVersion.fromJson(await _json('POST', '/listings/$listingId/versions', json: version.toJson()));

  /// The publisher hides their own listing.
  Future<Listing> unlist(String listingId) async => Listing.fromJson(await _json('POST', '/listings/$listingId/unlist'));

  /// The publisher lists again a listing they unlisted themselves.
  Future<Listing> relist(String listingId) async => Listing.fromJson(await _json('POST', '/listings/$listingId/relist'));

  // --- Library & install --------------------------------------------------------

  /// "Get (Free)": records the listing in the caller's library.
  Future<LibraryEntry> getListing(String listingId) async =>
      LibraryEntry.fromJson(await _json('POST', '/listings/$listingId/get'));

  Future<List<LibraryEntry>> library() async {
    final body = await _json('GET', '/library');
    return [for (final e in body['items'] as List) LibraryEntry.fromJson((e as Map).cast())];
  }

  Future<InstallManifest> manifest(String listingId, String version) async =>
      InstallManifest.fromJson(await _json('GET', '/listings/$listingId/versions/$version/manifest'));

  /// The whole version archive.
  Future<Uint8List> downloadArchive(String listingId, String version) async {
    final r = await _send('GET', '/listings/$listingId/versions/$version/download');
    if (r.statusCode >= 400) throw _error(r);
    return r.bodyBytes;
  }

  /// A server-relative URL from a manifest (`files[].url`, `archive.url`).
  Future<Uint8List> downloadUrl(String url) async {
    final uri = resolve(url);
    final path = uri.path.substring(baseUrl.path.length + apiPrefix.length);
    final r = await _send('GET', path, query: uri.queryParameters.isEmpty ? null : uri.queryParameters);
    if (r.statusCode >= 400) throw _error(r);
    return r.bodyBytes;
  }

  /// Streams a manifest URL, for progress and cancellation (cancel the
  /// subscription on the returned response's stream). Throws on HTTP errors.
  Future<http.StreamedResponse> openDownload(String url) async {
    final request = http.Request('GET', resolve(url));
    if (_accessToken != null) request.headers['Authorization'] = 'Bearer $_accessToken';
    var response = await _http.send(request);
    if (response.statusCode == 401 && await _tryRefresh()) {
      final retry = http.Request('GET', resolve(url))..headers['Authorization'] = 'Bearer $_accessToken';
      response = await _http.send(retry);
    }
    if (response.statusCode >= 400) throw _error(await http.Response.fromStream(response));
    return response;
  }

  // --- Reports & moderation ------------------------------------------------------

  Future<ListingReport> report(String listingId, ReportReason reason, {String details = ''}) async =>
      ListingReport.fromJson(
          await _json('POST', '/listings/$listingId/reports', json: {'reason': reason.wire, 'details': details}));

  Future<List<ListingReport>> reports({ReportStatus? status = ReportStatus.open}) async {
    final body = await _json('GET', '/moderation/reports', query: {if (status != null) 'status': status.wire});
    return [for (final r in body['items'] as List) ListingReport.fromJson((r as Map).cast())];
  }

  /// [action] is `dismiss` or `unlist`.
  Future<ListingReport> resolveReport(String reportId, {required String action, String note = ''}) async =>
      ListingReport.fromJson(
          await _json('POST', '/moderation/reports/$reportId/resolve', json: {'action': action, 'note': note}));

  Future<Listing> moderatorUnlist(String listingId, {required String reason}) async =>
      Listing.fromJson(await _json('POST', '/moderation/listings/$listingId/unlist', json: {'reason': reason}));

  Future<Listing> moderatorRestore(String listingId) async =>
      Listing.fromJson(await _json('POST', '/moderation/listings/$listingId/restore'));

  Future<Listing> setFeatured(String listingId, bool featured) async => Listing.fromJson(
      await _json('POST', '/moderation/listings/$listingId/feature', json: {'featured': featured}));

  /// Suspends the account, unlists all of its listings and revokes its tokens
  /// (the publishing terms' penalty clause).
  Future<MarketplaceUser> suspend(String username, {required String reason}) async => MarketplaceUser.fromJson(
      await _json('POST', '/moderation/users/${Uri.encodeComponent(username)}/suspend', json: {'reason': reason}));

  Future<MarketplaceUser> unsuspend(String username) async => MarketplaceUser.fromJson(
      await _json('POST', '/moderation/users/${Uri.encodeComponent(username)}/unsuspend'));

  Future<List<AuditEntry>> auditLog({int limit = 100}) async {
    final body = await _json('GET', '/moderation/audit', query: {'limit': '$limit'});
    return [for (final e in body['items'] as List) AuditEntry.fromJson((e as Map).cast())];
  }

  /// Admin only.
  Future<MarketplaceUser> setRole(String username, UserRole role) async => MarketplaceUser.fromJson(
      await _json('POST', '/admin/users/${Uri.encodeComponent(username)}/role', json: {'role': role.wire}));
}
