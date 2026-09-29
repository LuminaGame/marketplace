import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../util.dart';

/// Opens (creating if needed) the SQLite database at [path] and applies every
/// pending migration.
Database openMarketplaceDatabase(String path) {
  File(path).parent.createSync(recursive: true);
  final db = sqlite3.open(path);
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('PRAGMA busy_timeout = 5000');
  migrate(db);
  return db;
}

/// Runs [body] in a transaction (`BEGIN IMMEDIATE`), rolling back on error.
/// Inside an open transaction it just runs [body].
T transaction<T>(Database db, T Function() body) {
  if (!db.autocommit) return body();
  db.execute('BEGIN IMMEDIATE');
  try {
    final result = body();
    db.execute('COMMIT');
    return result;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

/// Ordered schema migrations; each runs once, recorded in `schema_migrations`.
const List<String> migrations = [
  // 1 — the initial schema.
  '''
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  display_name TEXT NOT NULL,
  avatar_sha256 TEXT,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'moderator', 'admin')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  suspended_reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  refresh_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  last_used_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  revoked_reason TEXT,
  user_agent TEXT,
  ip_hash TEXT
);
CREATE INDEX sessions_user ON sessions(user_id);

CREATE TABLE media (
  sha256 TEXT PRIMARY KEY,
  content_type TEXT NOT NULL,
  size INTEGER NOT NULL,
  owner_id TEXT REFERENCES users(id),
  created_at TEXT NOT NULL
);

CREATE TABLE uploads (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  blob_sha256 TEXT NOT NULL,
  file_name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('zip', 'json')),
  size INTEGER NOT NULL,
  files_json TEXT NOT NULL,
  detected_kinds TEXT NOT NULL,
  created_at TEXT NOT NULL,
  consumed_at TEXT
);

CREATE TABLE listings (
  id TEXT PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  publisher_id TEXT NOT NULL REFERENCES users(id),
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  tags TEXT NOT NULL DEFAULT '',
  tags_json TEXT NOT NULL DEFAULT '[]',
  engine_version TEXT NOT NULL,
  engine_version_code INTEGER NOT NULL,
  price_cents INTEGER NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'USD',
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'unlisted')),
  unlisted_by TEXT CHECK (unlisted_by IN ('owner', 'moderator')),
  unlisted_reason TEXT,
  featured INTEGER NOT NULL DEFAULT 0,
  screenshots_json TEXT NOT NULL DEFAULT '[]',
  download_count INTEGER NOT NULL DEFAULT 0,
  content_license TEXT,
  code_license TEXT,
  latest_version_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  published_at TEXT
);
CREATE INDEX listings_publisher ON listings(publisher_id);
CREATE INDEX listings_status ON listings(status, category);

CREATE VIRTUAL TABLE listings_fts USING fts5(
  title, description, tags,
  content = 'listings', content_rowid = 'rowid',
  tokenize = 'porter unicode61'
);
CREATE TRIGGER listings_fts_insert AFTER INSERT ON listings BEGIN
  INSERT INTO listings_fts(rowid, title, description, tags) VALUES (new.rowid, new.title, new.description, new.tags);
END;
CREATE TRIGGER listings_fts_delete AFTER DELETE ON listings BEGIN
  INSERT INTO listings_fts(listings_fts, rowid, title, description, tags) VALUES ('delete', old.rowid, old.title, old.description, old.tags);
END;
CREATE TRIGGER listings_fts_update AFTER UPDATE OF title, description, tags ON listings BEGIN
  INSERT INTO listings_fts(listings_fts, rowid, title, description, tags) VALUES ('delete', old.rowid, old.title, old.description, old.tags);
  INSERT INTO listings_fts(rowid, title, description, tags) VALUES (new.rowid, new.title, new.description, new.tags);
END;

CREATE TABLE listing_versions (
  id TEXT PRIMARY KEY,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  version TEXT NOT NULL,
  release_notes TEXT NOT NULL DEFAULT '',
  engine_version TEXT NOT NULL,
  content_license TEXT,
  code_license TEXT,
  upload_id TEXT NOT NULL REFERENCES uploads(id),
  blob_sha256 TEXT NOT NULL,
  archive_kind TEXT NOT NULL,
  file_name TEXT NOT NULL,
  size INTEGER NOT NULL,
  files_json TEXT NOT NULL,
  download_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  UNIQUE (listing_id, version)
);

CREATE TABLE attestations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  listing_id TEXT NOT NULL REFERENCES listings(id),
  version_id TEXT NOT NULL UNIQUE REFERENCES listing_versions(id),
  terms_version TEXT NOT NULL,
  statement TEXT NOT NULL,
  accepted_at TEXT NOT NULL,
  ip_hash TEXT NOT NULL
);
CREATE TRIGGER attestations_immutable_update BEFORE UPDATE ON attestations BEGIN
  SELECT RAISE(ABORT, 'attestations are immutable');
END;
CREATE TRIGGER attestations_immutable_delete BEFORE DELETE ON attestations BEGIN
  SELECT RAISE(ABORT, 'attestations are immutable');
END;

CREATE TABLE library (
  user_id TEXT NOT NULL REFERENCES users(id),
  listing_id TEXT NOT NULL REFERENCES listings(id),
  acquired_at TEXT NOT NULL,
  PRIMARY KEY (user_id, listing_id)
);

CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  listing_id TEXT NOT NULL REFERENCES listings(id),
  reporter_id TEXT NOT NULL REFERENCES users(id),
  reason TEXT NOT NULL,
  details TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'dismissed', 'actioned')),
  created_at TEXT NOT NULL,
  resolved_by TEXT REFERENCES users(id),
  resolved_at TEXT,
  resolution_note TEXT
);
CREATE INDEX reports_status ON reports(status, created_at);

CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id TEXT,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);
CREATE TRIGGER audit_log_immutable_update BEFORE UPDATE ON audit_log BEGIN
  SELECT RAISE(ABORT, 'the audit log is append-only');
END;
CREATE TRIGGER audit_log_immutable_delete BEFORE DELETE ON audit_log BEGIN
  SELECT RAISE(ABORT, 'the audit log is append-only');
END;
''',
  // 2 — the preview model a version's 3D view shows. NULL
  // preview_state = not derived yet (the server backfills on start-up).
  '''
ALTER TABLE uploads ADD COLUMN preview_sha256 TEXT;
ALTER TABLE uploads ADD COLUMN preview_size INTEGER;
ALTER TABLE uploads ADD COLUMN preview_source TEXT;
ALTER TABLE listing_versions ADD COLUMN preview_sha256 TEXT;
ALTER TABLE listing_versions ADD COLUMN preview_size INTEGER;
ALTER TABLE listing_versions ADD COLUMN preview_source TEXT;
ALTER TABLE listing_versions ADD COLUMN preview_state TEXT CHECK (preview_state IN ('ready', 'none'));
''',
];

void migrate(Database db) {
  db.execute('CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)');
  final applied = {for (final r in db.select('SELECT version FROM schema_migrations')) r['version'] as int};
  for (var i = 0; i < migrations.length; i++) {
    final version = i + 1;
    if (applied.contains(version)) continue;
    transaction(db, () {
      db.execute(migrations[i]);
      db.execute('INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)', [version, nowIso()]);
    });
  }
}
