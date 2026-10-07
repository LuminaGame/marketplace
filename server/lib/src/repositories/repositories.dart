import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

import 'package:lumina_marketplace_server/src/repositories/records.dart';

// The persistence seams. `sqlite_repositories.dart` implements them on SQLite;
// a PostgreSQL implementation can replace it for hosting without touching the
// services.

abstract interface class UserRepository {
  void create(UserRecord user);
  UserRecord? findById(String id);
  UserRecord? findByUsername(String username);
  UserRecord? findByEmail(String email);

  /// By email or username, case-insensitively.
  UserRecord? findByLogin(String login);
  UserRecord update(String id, {String? displayName, String? avatarSha256, String? passwordHash, UserRole? role});
  UserRecord setStatus(String id, UserStatus status, {String? reason});
}

abstract interface class SessionRepository {
  void create(SessionRecord session);
  SessionRecord? findById(String id);
  SessionRecord? findByRefreshHash(String refreshHash);

  /// Replaces the refresh token hash (rotation) and extends the expiry.
  void rotate(String id, {required String refreshHash, required String expiresAt});
  void revoke(String id, String reason);

  /// Revokes every active session of [userId] except [exceptSessionId];
  /// returns how many were revoked.
  int revokeAllForUser(String userId, String reason, {String? exceptSessionId});
}

abstract interface class MediaRepository {
  void add(MediaRecord media, {String? ownerId});
  MediaRecord? find(String sha256);
}

abstract interface class UploadRepository {
  void create(UploadRecord upload);
  UploadRecord? find(String id);
  void markConsumed(String id);
}

/// Search filters as the repository sees them (already validated).
class ListingSearch {
  const ListingSearch({
    this.ftsQuery,
    this.category,
    this.licenseKind,
    this.license,
    this.engineVersionCode,
    this.free,
    this.publisherId,
    this.featured,
    this.sort = SearchSort.newest,
    this.offset = 0,
    this.limit = 24,
  });

  final String? ftsQuery;
  final ListingCategory? category;
  final LicenseKind? licenseKind;
  final String? license;
  final int? engineVersionCode;
  final bool? free;
  final String? publisherId;
  final bool? featured;
  final SearchSort sort;
  final int offset;
  final int limit;
}

abstract interface class ListingRepository {
  void create(ListingRecord listing, {required int engineVersionCode});
  ListingRecord? findById(String id);
  ListingRecord? findBySlug(String slug);
  bool slugExists(String slug);

  /// Updates the given columns (snake_case) and `updated_at`.
  ListingRecord update(String id, Map<String, Object?> columns);
  List<ListingRecord> byPublisher(String publisherId, {Set<ListingStatus>? statuses});

  /// Published listings matching [search], plus the total match count.
  (List<ListingRecord>, int) search(ListingSearch search);

  void createVersion(VersionRecord version);

  /// Versions whose preview model was never derived (the start-up backfill).
  List<VersionRecord> versionsWithoutPreviewState();

  /// Records [preview] (null: the version has none) and marks it derived.
  void setVersionPreview(String versionId, PreviewInfo? preview);
  VersionRecord? findVersion(String listingId, String version);
  VersionRecord? findVersionById(String id);

  /// Newest first.
  List<VersionRecord> versionsOf(String listingId);
  void recordDownload(String listingId, String versionId);
}

abstract interface class AttestationRepository {
  /// Stores an attestation. Attestations cannot be updated or deleted.
  void create(AttestationRecord attestation);
  AttestationRecord? forVersion(String versionId);
}

abstract interface class LibraryRepository {
  /// Idempotent; returns the acquisition time.
  String add(String userId, String listingId);
  String? acquiredAt(String userId, String listingId);

  /// (listing id, acquired at), newest first.
  List<(String, String)> list(String userId);
}

abstract interface class ReportRepository {
  void create(ReportRecord report);
  ReportRecord? find(String id);
  List<ReportRecord> list({ReportStatus? status});
  ReportRecord resolve(String id, {required ReportStatus status, required String resolvedBy, required String note});
}

/// An audit row with the actor's username resolved.
class AuditRecord {
  const AuditRecord(this.id, this.actorUsername, this.action, this.targetType, this.targetId, this.details, this.createdAt);
  final int id;
  final String actorUsername;
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, Object?> details;
  final String createdAt;
}

abstract interface class AuditRepository {
  /// Appends an entry; [actorId] null means the system.
  void append(String? actorId, String action, String targetType, String targetId, [Map<String, Object?> details]);

  /// Newest first.
  List<AuditRecord> list({int limit = 100});
}
