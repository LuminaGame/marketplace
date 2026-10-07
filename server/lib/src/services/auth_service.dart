import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:lumina_marketplace_server/src/db/database.dart';
import 'package:lumina_marketplace_server/src/errors.dart';
import 'package:lumina_marketplace_server/src/repositories/records.dart';
import 'package:lumina_marketplace_server/src/repositories/repositories.dart';
import 'package:lumina_marketplace_server/src/storage/blob_store.dart';
import 'package:lumina_marketplace_server/src/storage/zip_validator.dart';
import 'package:lumina_marketplace_server/src/util.dart';
import 'package:lumina_marketplace_server/src/services/crypto.dart';

/// Who is calling: the IP hash (never the raw IP) and user agent.
class ClientInfo {
  const ClientInfo({required this.ipHash, this.userAgent});
  final String ipHash;
  final String? userAgent;
}

/// The authenticated caller of a request.
class AuthContext {
  const AuthContext(this.user, this.sessionId);
  final UserRecord user;
  final String sessionId;

  bool get canModerate => user.role.canModerate;
  bool get isAdmin => user.role == UserRole.admin;
}

/// A new or refreshed session: the tokens to hand to the client.
class IssuedSession {
  const IssuedSession(this.user, this.sessionId, this.accessToken, this.refreshToken, this.expiresIn);
  final UserRecord user;
  final String sessionId;
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  AuthSession toDto() => AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresIn: expiresIn,
        user: user.toDto(includeEmail: true),
      );
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _usernamePattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{2,31}$');

/// Accounts and sessions. Refresh tokens are random, stored only as SHA-256
/// hashes, rotated on every refresh; access tokens carry the session id and
/// are checked against the session on every request, so log-out, password
/// change and suspension revoke them immediately.
class AuthService {
  AuthService({
    required this.db,
    required this.users,
    required this.sessions,
    required this.media,
    required this.blobs,
    required this.tokens,
    required this.hasher,
    required this.refreshTtl,
    required this.maxImageBytes,
  });

  final Database db;
  final UserRepository users;
  final SessionRepository sessions;
  final MediaRepository media;
  final BlobStore blobs;
  final TokenService tokens;
  final PasswordHasher hasher;
  final Duration refreshTtl;
  final int maxImageBytes;

  static const minPasswordLength = 10;

  void _validatePassword(String password) {
    if (password.length < minPasswordLength) {
      throw ApiException.validation('The password needs at least $minPasswordLength characters.', {'field': 'password'});
    }
    if (password.length > 256) throw ApiException.validation('The password is too long.', {'field': 'password'});
  }

  Future<IssuedSession> signUp({
    required String email,
    required String username,
    required String password,
    String? displayName,
    required ClientInfo client,
    UserRole role = UserRole.user,
  }) async {
    email = email.trim();
    username = username.trim();
    if (!_emailPattern.hasMatch(email) || email.length > 254) {
      throw ApiException.validation('Enter a valid email address.', {'field': 'email'});
    }
    if (!_usernamePattern.hasMatch(username)) {
      throw ApiException.validation(
          'Usernames are 3–32 letters, digits, "_", "." or "-", starting with a letter, digit or "_".', {'field': 'username'});
    }
    _validatePassword(password);
    final name = (displayName ?? '').trim().isEmpty ? username : displayName!.trim();
    if (name.length > 64) throw ApiException.validation('The display name is too long.', {'field': 'displayName'});
    if (users.findByEmail(email) != null) throw ApiException.conflict('An account with this email already exists.');
    if (users.findByUsername(username) != null) throw ApiException.conflict('This username is taken.');

    final hash = await hasher.hash(password);
    final now = nowIso();
    final user = UserRecord(
      id: newId(),
      email: email,
      username: username,
      displayName: name,
      passwordHash: hash,
      role: role,
      status: UserStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    try {
      users.create(user);
    } on SqliteException {
      throw ApiException.conflict('An account with this email or username already exists.');
    }
    return _openSession(user, client);
  }

  /// Verifies [login] (email or username) and [password]. Throws 401
  /// `invalid_credentials` (the same for an unknown account and a wrong
  /// password) or 403 `account_suspended`.
  Future<IssuedSession> logIn({required String login, required String password, required ClientInfo client}) async {
    final user = users.findByLogin(login.trim());
    if (user == null) {
      await hasher.hash(password); // same work as a real check: no user-enumeration timing
      throw const ApiException(401, 'invalid_credentials', 'Wrong email/username or password.');
    }
    if (!await hasher.verify(password, user.passwordHash)) {
      throw const ApiException(401, 'invalid_credentials', 'Wrong email/username or password.');
    }
    if (user.status == UserStatus.suspended) {
      throw ApiException(403, 'account_suspended', 'This account is suspended.',
          details: {'reason': ?user.suspendedReason});
    }
    return _openSession(user, client);
  }

  IssuedSession _openSession(UserRecord user, ClientInfo client) {
    final refresh = newToken();
    final now = nowIso();
    final session = SessionRecord(
      id: newId(),
      userId: user.id,
      refreshHash: sha256OfString(refresh),
      createdAt: now,
      lastUsedAt: now,
      expiresAt: DateTime.now().toUtc().add(refreshTtl).toIso8601String(),
      userAgent: client.userAgent,
      ipHash: client.ipHash,
    );
    sessions.create(session);
    return _issue(user, session.id, refresh);
  }

  IssuedSession _issue(UserRecord user, String sessionId, String refreshToken) => IssuedSession(
        user,
        sessionId,
        tokens.issue(userId: user.id, sessionId: sessionId, role: user.role.wire),
        refreshToken,
        tokens.ttl.inSeconds,
      );

  /// Rotates [refreshToken]. A revoked, rotated-out, expired or unknown token
  /// is refused with 401 `invalid_refresh_token`; presenting a rotated-out
  /// token is treated as theft and revokes nothing further (it is simply
  /// unknown).
  IssuedSession refresh(String? refreshToken) {
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException(401, 'invalid_refresh_token', 'No refresh token.');
    }
    return transaction(db, () {
      final session = sessions.findByRefreshHash(sha256OfString(refreshToken));
      if (session == null || session.isRevoked || session.isExpired) {
        throw const ApiException(401, 'invalid_refresh_token', 'The session has ended; sign in again.');
      }
      final user = users.findById(session.userId)!;
      if (user.status == UserStatus.suspended) {
        sessions.revoke(session.id, 'suspended');
        throw const ApiException(403, 'account_suspended', 'This account is suspended.');
      }
      final next = newToken();
      sessions.rotate(session.id,
          refreshHash: sha256OfString(next), expiresAt: DateTime.now().toUtc().add(refreshTtl).toIso8601String());
      return _issue(user, session.id, next);
    });
  }

  /// Revokes the session of [auth] or the one [refreshToken] belongs to.
  void logOut({AuthContext? auth, String? refreshToken}) {
    if (auth != null) sessions.revoke(auth.sessionId, 'logout');
    if (refreshToken != null) {
      final s = sessions.findByRefreshHash(sha256OfString(refreshToken));
      if (s != null) sessions.revoke(s.id, 'logout');
    }
  }

  /// Resolves a bearer token to its caller. Throws 401 `token_expired` for an
  /// expired token (the client refreshes) and 401 `unauthorized` for anything
  /// invalid or revoked.
  AuthContext authenticate(String accessToken) {
    final AccessClaims claims;
    try {
      claims = tokens.verify(accessToken);
    } on TokenExpiredException {
      throw const ApiException(401, 'token_expired', 'The access token expired.');
    } on TokenInvalidException {
      throw ApiException.unauthorized('Invalid access token.');
    }
    final session = sessions.findById(claims.sessionId);
    if (session == null || session.isRevoked || session.userId != claims.userId) {
      throw ApiException.unauthorized('The session was revoked; sign in again.');
    }
    final user = users.findById(claims.userId);
    if (user == null) throw ApiException.unauthorized();
    if (user.status == UserStatus.suspended) {
      throw const ApiException(401, 'account_suspended', 'This account is suspended.');
    }
    return AuthContext(user, session.id);
  }

  Future<void> changePassword(AuthContext auth, {required String currentPassword, required String newPassword}) async {
    if (!await hasher.verify(currentPassword, auth.user.passwordHash)) {
      throw const ApiException(401, 'invalid_credentials', 'The current password is wrong.');
    }
    _validatePassword(newPassword);
    final hash = await hasher.hash(newPassword);
    transaction(db, () {
      users.update(auth.user.id, passwordHash: hash);
      sessions.revokeAllForUser(auth.user.id, 'password_change', exceptSessionId: auth.sessionId);
    });
  }

  UserRecord updateProfile(AuthContext auth, {String? displayName}) {
    if (displayName != null) {
      final name = displayName.trim();
      if (name.isEmpty || name.length > 64) {
        throw ApiException.validation('The display name must be 1–64 characters.', {'field': 'displayName'});
      }
      return users.update(auth.user.id, displayName: name);
    }
    return auth.user;
  }

  Future<UserRecord> setAvatar(AuthContext auth, Stream<List<int>> body) async {
    final ref = await storeImage(body, ownerId: auth.user.id);
    return users.update(auth.user.id, avatarSha256: ref.sha256);
  }

  /// Stores a PNG/JPEG/WebP in the blob store and the media table (served at
  /// `/api/v1/media/<sha256>`).
  Future<MediaRecord> storeImage(Stream<List<int>> body, {String? ownerId}) async {
    final List<int> bytes;
    try {
      bytes = await collectLimited(body, maxImageBytes);
    } on BlobTooLargeException {
      throw ApiException(413, 'payload_too_large', 'Images are limited to ${maxImageBytes ~/ (1024 * 1024)} MB.');
    }
    final type = sniffImageType(bytes);
    if (type == null) throw const ApiException(422, 'invalid_image', 'Upload a PNG, JPEG or WebP image.');
    final ref = await blobs.put(Stream.value(bytes));
    final record = MediaRecord(ref.sha256, type, ref.size);
    media.add(record, ownerId: ownerId);
    return record;
  }
}
