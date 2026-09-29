import 'dart:convert';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:sqlite3/sqlite3.dart';

import '../util.dart';
import 'records.dart';
import 'repositories.dart';

Map<String, Object?>? _one(ResultSet rows) => rows.isEmpty ? null : Map<String, Object?>.from(rows.first);

class SqliteUserRepository implements UserRepository {
  SqliteUserRepository(this.db);
  final Database db;

  @override
  void create(UserRecord u) => db.execute(
        'INSERT INTO users (id, email, username, display_name, avatar_sha256, password_hash, role, status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [u.id, u.email, u.username, u.displayName, u.avatarSha256, u.passwordHash, u.role.wire, u.status.wire, u.createdAt, u.updatedAt],
      );

  UserRecord? _where(String clause, List<Object?> args) {
    final row = _one(db.select('SELECT * FROM users WHERE $clause', args));
    return row == null ? null : UserRecord.fromRow(row);
  }

  @override
  UserRecord? findById(String id) => _where('id = ?', [id]);
  @override
  UserRecord? findByUsername(String username) => _where('username = ?', [username]);
  @override
  UserRecord? findByEmail(String email) => _where('email = ?', [email]);
  @override
  UserRecord? findByLogin(String login) => _where('email = ?1 OR username = ?1', [login]);

  @override
  UserRecord update(String id, {String? displayName, String? avatarSha256, String? passwordHash, UserRole? role}) {
    final sets = <String>[];
    final args = <Object?>[];
    void set(String column, Object? value) {
      sets.add('$column = ?');
      args.add(value);
    }

    if (displayName != null) set('display_name', displayName);
    if (avatarSha256 != null) set('avatar_sha256', avatarSha256);
    if (passwordHash != null) set('password_hash', passwordHash);
    if (role != null) set('role', role.wire);
    set('updated_at', nowIso());
    db.execute('UPDATE users SET ${sets.join(', ')} WHERE id = ?', [...args, id]);
    return findById(id)!;
  }

  @override
  UserRecord setStatus(String id, UserStatus status, {String? reason}) {
    db.execute('UPDATE users SET status = ?, suspended_reason = ?, updated_at = ? WHERE id = ?',
        [status.wire, status == UserStatus.suspended ? reason : null, nowIso(), id]);
    return findById(id)!;
  }
}

class SqliteSessionRepository implements SessionRepository {
  SqliteSessionRepository(this.db);
  final Database db;

  @override
  void create(SessionRecord s) => db.execute(
        'INSERT INTO sessions (id, user_id, refresh_hash, created_at, last_used_at, expires_at, user_agent, ip_hash) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [s.id, s.userId, s.refreshHash, s.createdAt, s.lastUsedAt, s.expiresAt, s.userAgent, s.ipHash],
      );

  @override
  SessionRecord? findById(String id) {
    final row = _one(db.select('SELECT * FROM sessions WHERE id = ?', [id]));
    return row == null ? null : SessionRecord.fromRow(row);
  }

  @override
  SessionRecord? findByRefreshHash(String refreshHash) {
    final row = _one(db.select('SELECT * FROM sessions WHERE refresh_hash = ?', [refreshHash]));
    return row == null ? null : SessionRecord.fromRow(row);
  }

  @override
  void rotate(String id, {required String refreshHash, required String expiresAt}) => db.execute(
        'UPDATE sessions SET refresh_hash = ?, expires_at = ?, last_used_at = ? WHERE id = ?',
        [refreshHash, expiresAt, nowIso(), id],
      );

  @override
  void revoke(String id, String reason) => db.execute(
        'UPDATE sessions SET revoked_at = ?, revoked_reason = ? WHERE id = ? AND revoked_at IS NULL',
        [nowIso(), reason, id],
      );

  @override
  int revokeAllForUser(String userId, String reason, {String? exceptSessionId}) {
    db.execute(
      'UPDATE sessions SET revoked_at = ?, revoked_reason = ? WHERE user_id = ? AND revoked_at IS NULL AND id IS NOT ?',
      [nowIso(), reason, userId, exceptSessionId],
    );
    return db.updatedRows;
  }
}

class SqliteMediaRepository implements MediaRepository {
  SqliteMediaRepository(this.db);
  final Database db;

  @override
  void add(MediaRecord m, {String? ownerId}) => db.execute(
        'INSERT OR IGNORE INTO media (sha256, content_type, size, owner_id, created_at) VALUES (?, ?, ?, ?, ?)',
        [m.sha256, m.contentType, m.size, ownerId, nowIso()],
      );

  @override
  MediaRecord? find(String sha256) {
    final row = _one(db.select('SELECT * FROM media WHERE sha256 = ?', [sha256]));
    return row == null ? null : MediaRecord(row['sha256'] as String, row['content_type'] as String, row['size'] as int);
  }
}

class SqliteUploadRepository implements UploadRepository {
  SqliteUploadRepository(this.db);
  final Database db;

  @override
  void create(UploadRecord u) => db.execute(
        'INSERT INTO uploads (id, user_id, blob_sha256, file_name, kind, size, files_json, detected_kinds, created_at, '
        'preview_sha256, preview_size, preview_source) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [u.id, u.userId, u.blobSha256, u.fileName, u.kind, u.size, encodeFiles(u.files),
         u.detectedKinds.map((k) => k.wire).join(','), u.createdAt, u.preview?.sha256, u.preview?.size, u.preview?.source],
      );

  @override
  UploadRecord? find(String id) {
    final row = _one(db.select('SELECT * FROM uploads WHERE id = ?', [id]));
    return row == null ? null : UploadRecord.fromRow(row);
  }

  @override
  void markConsumed(String id) => db.execute('UPDATE uploads SET consumed_at = ? WHERE id = ?', [nowIso(), id]);
}

class SqliteListingRepository implements ListingRepository {
  SqliteListingRepository(this.db);
  final Database db;

  @override
  void create(ListingRecord l, {required int engineVersionCode}) => db.execute(
        'INSERT INTO listings (id, slug, publisher_id, category, title, description, tags, tags_json, engine_version, '
        'engine_version_code, price_cents, currency, status, featured, screenshots_json, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [l.id, l.slug, l.publisherId, l.category.wire, l.title, l.description, l.tags.join(' '), jsonEncode(l.tags),
         l.engineVersion, engineVersionCode, l.priceCents, l.currency, l.status.wire, l.featured ? 1 : 0,
         jsonEncode(l.screenshots), l.createdAt, l.updatedAt],
      );

  @override
  ListingRecord? findById(String id) {
    final row = _one(db.select('SELECT * FROM listings WHERE id = ?', [id]));
    return row == null ? null : ListingRecord.fromRow(row);
  }

  @override
  ListingRecord? findBySlug(String slug) {
    final row = _one(db.select('SELECT * FROM listings WHERE slug = ?', [slug]));
    return row == null ? null : ListingRecord.fromRow(row);
  }

  @override
  bool slugExists(String slug) => db.select('SELECT 1 FROM listings WHERE slug = ?', [slug]).isNotEmpty;

  static const _updatable = {
    'title', 'description', 'tags', 'tags_json', 'engine_version', 'engine_version_code', 'category', 'status',
    'unlisted_by', 'unlisted_reason', 'featured', 'screenshots_json', 'content_license', 'code_license',
    'latest_version_id', 'published_at',
  };

  @override
  ListingRecord update(String id, Map<String, Object?> columns) {
    for (final c in columns.keys) {
      if (!_updatable.contains(c)) throw ArgumentError.value(c, 'columns', 'not updatable');
    }
    final sets = [...columns.keys.map((c) => '$c = ?'), 'updated_at = ?'];
    db.execute('UPDATE listings SET ${sets.join(', ')} WHERE id = ?', [...columns.values, nowIso(), id]);
    return findById(id)!;
  }

  @override
  List<ListingRecord> byPublisher(String publisherId, {Set<ListingStatus>? statuses}) {
    final rows = db.select('SELECT * FROM listings WHERE publisher_id = ? ORDER BY created_at DESC', [publisherId]);
    return [
      for (final r in rows)
        if (statuses == null || statuses.contains(ListingStatus.parse(r['status'] as String?))) ListingRecord.fromRow(r),
    ];
  }

  @override
  (List<ListingRecord>, int) search(ListingSearch s) {
    final where = <String>["l.status = 'published'"];
    final args = <Object?>[];
    var from = 'listings l';
    var rank = '0.0';
    if (s.ftsQuery != null) {
      from = 'listings_fts JOIN listings l ON l.rowid = listings_fts.rowid';
      where.add('listings_fts MATCH ?');
      args.add(s.ftsQuery);
      // Title matches weigh most, then tags, then the description.
      rank = 'bm25(listings_fts, 10.0, 1.0, 4.0)';
    }
    if (s.category != null) {
      where.add('l.category = ?');
      args.add(s.category!.wire);
    }
    switch (s.licenseKind) {
      case LicenseKind.content:
        where.add('l.content_license IS NOT NULL');
      case LicenseKind.code:
        where.add('l.code_license IS NOT NULL');
      case null:
    }
    if (s.license != null) {
      where.add('(l.content_license = ? OR l.code_license = ?)');
      args
        ..add(s.license)
        ..add(s.license);
    }
    if (s.engineVersionCode != null) {
      where.add('l.engine_version_code <= ?');
      args.add(s.engineVersionCode);
    }
    if (s.free != null) where.add(s.free! ? 'l.price_cents = 0' : 'l.price_cents > 0');
    if (s.publisherId != null) {
      where.add('l.publisher_id = ?');
      args.add(s.publisherId);
    }
    if (s.featured != null) where.add('l.featured = ${s.featured! ? 1 : 0}');

    final order = switch (s.sort) {
      SearchSort.relevance when s.ftsQuery != null => 'rank ASC, l.download_count DESC',
      SearchSort.downloads => 'l.download_count DESC, l.published_at DESC',
      SearchSort.name => 'l.title COLLATE NOCASE ASC, l.published_at DESC',
      _ => 'l.published_at DESC, l.rowid DESC',
    };
    final clause = where.join(' AND ');
    final total = db.select('SELECT COUNT(*) AS n FROM $from WHERE $clause', args).first['n'] as int;
    final rows = db.select(
      'SELECT l.*, $rank AS rank FROM $from WHERE $clause ORDER BY $order LIMIT ? OFFSET ?',
      [...args, s.limit, s.offset],
    );
    return ([for (final r in rows) ListingRecord.fromRow(r)], total);
  }

  @override
  void createVersion(VersionRecord v) => db.execute(
        'INSERT INTO listing_versions (id, listing_id, version, release_notes, engine_version, content_license, '
        'code_license, upload_id, blob_sha256, archive_kind, file_name, size, files_json, created_at, '
        'preview_sha256, preview_size, preview_source, preview_state) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [v.id, v.listingId, v.version, v.releaseNotes, v.engineVersion, v.contentLicense, v.codeLicense, v.uploadId,
         v.blobSha256, v.archiveKind, v.fileName, v.size, encodeFiles(v.files), v.createdAt,
         v.preview?.sha256, v.preview?.size, v.preview?.source, v.previewState],
      );

  @override
  List<VersionRecord> versionsWithoutPreviewState() => [
        for (final r in db.select('SELECT * FROM listing_versions WHERE preview_state IS NULL ORDER BY created_at'))
          VersionRecord.fromRow(r),
      ];

  @override
  void setVersionPreview(String versionId, PreviewInfo? preview) => db.execute(
        'UPDATE listing_versions SET preview_sha256 = ?, preview_size = ?, preview_source = ?, preview_state = ? '
        'WHERE id = ?',
        [preview?.sha256, preview?.size, preview?.source, preview == null ? 'none' : 'ready', versionId],
      );

  @override
  VersionRecord? findVersion(String listingId, String version) {
    final row = _one(db.select('SELECT * FROM listing_versions WHERE listing_id = ? AND version = ?', [listingId, version]));
    return row == null ? null : VersionRecord.fromRow(row);
  }

  @override
  VersionRecord? findVersionById(String id) {
    final row = _one(db.select('SELECT * FROM listing_versions WHERE id = ?', [id]));
    return row == null ? null : VersionRecord.fromRow(row);
  }

  @override
  List<VersionRecord> versionsOf(String listingId) => [
        for (final r in db.select(
            'SELECT * FROM listing_versions WHERE listing_id = ? ORDER BY created_at DESC, rowid DESC', [listingId]))
          VersionRecord.fromRow(r),
      ];

  @override
  void recordDownload(String listingId, String versionId) {
    db.execute('UPDATE listing_versions SET download_count = download_count + 1 WHERE id = ?', [versionId]);
    db.execute('UPDATE listings SET download_count = download_count + 1 WHERE id = ?', [listingId]);
  }
}

class SqliteAttestationRepository implements AttestationRepository {
  SqliteAttestationRepository(this.db);
  final Database db;

  @override
  void create(AttestationRecord a) => db.execute(
        'INSERT INTO attestations (id, user_id, listing_id, version_id, terms_version, statement, accepted_at, ip_hash) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [a.id, a.userId, a.listingId, a.versionId, a.termsVersion, a.statement, a.acceptedAt, a.ipHash],
      );

  @override
  AttestationRecord? forVersion(String versionId) {
    final row = _one(db.select('SELECT * FROM attestations WHERE version_id = ?', [versionId]));
    return row == null ? null : AttestationRecord.fromRow(row);
  }
}

class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository(this.db);
  final Database db;

  @override
  String add(String userId, String listingId) {
    db.execute('INSERT OR IGNORE INTO library (user_id, listing_id, acquired_at) VALUES (?, ?, ?)',
        [userId, listingId, nowIso()]);
    return acquiredAt(userId, listingId)!;
  }

  @override
  String? acquiredAt(String userId, String listingId) => db
      .select('SELECT acquired_at FROM library WHERE user_id = ? AND listing_id = ?', [userId, listingId])
      .firstOrNull?['acquired_at'] as String?;

  @override
  List<(String, String)> list(String userId) => [
        for (final r in db.select('SELECT listing_id, acquired_at FROM library WHERE user_id = ? ORDER BY acquired_at DESC',
            [userId]))
          (r['listing_id'] as String, r['acquired_at'] as String),
      ];
}

class SqliteReportRepository implements ReportRepository {
  SqliteReportRepository(this.db);
  final Database db;

  @override
  void create(ReportRecord r) => db.execute(
        'INSERT INTO reports (id, listing_id, reporter_id, reason, details, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [r.id, r.listingId, r.reporterId, r.reason.wire, r.details, r.status.wire, r.createdAt],
      );

  @override
  ReportRecord? find(String id) {
    final row = _one(db.select('SELECT * FROM reports WHERE id = ?', [id]));
    return row == null ? null : ReportRecord.fromRow(row);
  }

  @override
  List<ReportRecord> list({ReportStatus? status}) => [
        for (final r in status == null
            ? db.select('SELECT * FROM reports ORDER BY created_at DESC')
            : db.select('SELECT * FROM reports WHERE status = ? ORDER BY created_at DESC', [status.wire]))
          ReportRecord.fromRow(r),
      ];

  @override
  ReportRecord resolve(String id, {required ReportStatus status, required String resolvedBy, required String note}) {
    db.execute('UPDATE reports SET status = ?, resolved_by = ?, resolved_at = ?, resolution_note = ? WHERE id = ?',
        [status.wire, resolvedBy, nowIso(), note, id]);
    return find(id)!;
  }
}

class SqliteAuditRepository implements AuditRepository {
  SqliteAuditRepository(this.db);
  final Database db;

  @override
  void append(String? actorId, String action, String targetType, String targetId, [Map<String, Object?> details = const {}]) =>
      db.execute(
        'INSERT INTO audit_log (actor_id, action, target_type, target_id, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [actorId, action, targetType, targetId, jsonEncode(details), nowIso()],
      );

  @override
  List<AuditRecord> list({int limit = 100}) => [
        for (final r in db.select(
          'SELECT a.*, u.username FROM audit_log a LEFT JOIN users u ON u.id = a.actor_id ORDER BY a.id DESC LIMIT ?',
          [limit],
        ))
          AuditRecord(
            r['id'] as int,
            r['username'] as String? ?? 'system',
            r['action'] as String,
            r['target_type'] as String,
            r['target_id'] as String,
            (jsonDecode(r['details_json'] as String) as Map).cast(),
            r['created_at'] as String,
          ),
      ];
}
