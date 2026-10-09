import 'package:lumina_marketplace_shared/src/categories.dart';
import 'package:lumina_marketplace_shared/src/licenses.dart';
import 'package:lumina_marketplace_shared/src/plugin_package.dart';

part 'dto/listings.dart';
part 'dto/moderation.dart';
part 'dto/search_and_install.dart';

// Every DTO here is what the API sends and receives as JSON. Timestamps are
// ISO-8601 UTC strings on the wire; URLs are server-relative
// (`/api/v1/media/<sha256>`) and resolved by `MarketplaceClient.resolve`.

DateTime _date(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);
List<String> _strings(Object? v) => [for (final e in (v as List? ?? const [])) e as String];
Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();

enum UserRole {
  user('user'),
  moderator('moderator'),
  admin('admin');

  const UserRole(this.wire);
  final String wire;

  bool get canModerate => this != UserRole.user;

  static UserRole parse(String? wire) =>
      values.firstWhere((r) => r.wire == wire, orElse: () => UserRole.user);
}

enum UserStatus {
  active('active'),
  suspended('suspended');

  const UserStatus(this.wire);
  final String wire;

  static UserStatus parse(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => UserStatus.active);
}

/// An account. [email] is only present when the account is the caller's own
/// (or the caller is a moderator).
class MarketplaceUser {
  const MarketplaceUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.status,
    required this.createdAt,
    this.email,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final UserRole role;
  final UserStatus status;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        if (email != null) 'email': email,
        'avatarUrl': avatarUrl,
        'role': role.wire,
        'status': status.wire,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MarketplaceUser.fromJson(Map<String, Object?> j) => MarketplaceUser(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['displayName'] as String,
        email: j['email'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        role: UserRole.parse(j['role'] as String?),
        status: UserStatus.parse(j['status'] as String?),
        createdAt: _date(j['createdAt']),
      );
}

/// What sign-up, log-in and refresh return. [refreshToken] is also set as an
/// httpOnly cookie (`lm_refresh`) for browsers; native clients keep it from
/// the body.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;

  /// Seconds until [accessToken] expires.
  final int expiresIn;
  final MarketplaceUser user;

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresIn': expiresIn,
        'tokenType': 'Bearer',
        'user': user.toJson(),
      };

  factory AuthSession.fromJson(Map<String, Object?> j) => AuthSession(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresIn: j['expiresIn'] as int,
        user: MarketplaceUser.fromJson(_map(j['user'])),
      );
}

/// A listing's publisher as shown on cards and listing pages.
class PublisherSummary {
  const PublisherSummary({required this.id, required this.username, required this.displayName, this.avatarUrl});

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  Map<String, Object?> toJson() =>
      {'id': id, 'username': username, 'displayName': displayName, 'avatarUrl': avatarUrl};

  factory PublisherSummary.fromJson(Map<String, Object?> j) => PublisherSummary(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['displayName'] as String,
        avatarUrl: j['avatarUrl'] as String?,
      );
}
