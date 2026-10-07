import 'package:sqlite3/sqlite3.dart';

import 'package:lumina_marketplace_server/src/config.dart';
import 'package:lumina_marketplace_server/src/db/database.dart';
import 'package:lumina_marketplace_server/src/log.dart';
import 'package:lumina_marketplace_server/src/repositories/repositories.dart';
import 'package:lumina_marketplace_server/src/repositories/sqlite_repositories.dart';
import 'package:lumina_marketplace_server/src/storage/blob_store.dart';
import 'package:lumina_marketplace_server/src/storage/zip_validator.dart';
import 'package:lumina_marketplace_server/src/util.dart';
import 'package:lumina_marketplace_server/src/services/auth_service.dart';
import 'package:lumina_marketplace_server/src/services/crypto.dart';
import 'package:lumina_marketplace_server/src/services/listing_service.dart';
import 'package:lumina_marketplace_server/src/services/moderation_service.dart';

/// Every repository and service, wired from a [MarketplaceConfig]. The HTTP
/// layer, the seed script and tests all go through this.
class MarketplaceServices {
  MarketplaceServices._({
    required this.config,
    required this.log,
    required this.database,
    required this.users,
    required this.sessions,
    required this.media,
    required this.uploads,
    required this.listings,
    required this.attestations,
    required this.library,
    required this.reports,
    required this.audit,
    required this.blobs,
    required this.auth,
    required this.listingService,
    required this.moderation,
  });

  factory MarketplaceServices.open(MarketplaceConfig config, MarketplaceLog log) {
    final db = openMarketplaceDatabase(config.databasePath);
    final users = SqliteUserRepository(db);
    final sessions = SqliteSessionRepository(db);
    final media = SqliteMediaRepository(db);
    final uploads = SqliteUploadRepository(db);
    final listings = SqliteListingRepository(db);
    final attestations = SqliteAttestationRepository(db);
    final library = SqliteLibraryRepository(db);
    final reports = SqliteReportRepository(db);
    final audit = SqliteAuditRepository(db);
    final blobs = FileSystemBlobStore(config.storageDir);
    final auth = AuthService(
      db: db,
      users: users,
      sessions: sessions,
      media: media,
      blobs: blobs,
      tokens: TokenService(config.jwtSecret, config.accessTokenTtl),
      hasher: const PasswordHasher(),
      refreshTtl: config.refreshTokenTtl,
      maxImageBytes: config.maxImageBytes,
    );
    final listingService = ListingService(
      db: db,
      listings: listings,
      users: users,
      uploads: uploads,
      attestations: attestations,
      library: library,
      audit: audit,
      blobs: blobs,
      validator: ZipValidator(maxUnpackedBytes: config.maxUnpackedBytes),
      auth: auth,
      maxUploadBytes: config.maxUploadBytes,
      maxPreviewBytes: config.maxPreviewBytes,
    );
    return MarketplaceServices._(
      config: config,
      log: log,
      database: db,
      users: users,
      sessions: sessions,
      media: media,
      uploads: uploads,
      listings: listings,
      attestations: attestations,
      library: library,
      reports: reports,
      audit: audit,
      blobs: blobs,
      auth: auth,
      listingService: listingService,
      moderation: ModerationService(
        db: db,
        listings: listings,
        users: users,
        sessions: sessions,
        reports: reports,
        audit: audit,
        listingService: listingService,
      ),
    );
  }

  final MarketplaceConfig config;
  final MarketplaceLog log;

  /// The SQLite handle (exposed for migrations tooling and tests).
  final Database database;
  final UserRepository users;
  final SessionRepository sessions;
  final MediaRepository media;
  final UploadRepository uploads;
  final ListingRepository listings;
  final AttestationRepository attestations;
  final LibraryRepository library;
  final ReportRepository reports;
  final AuditRepository audit;
  final BlobStore blobs;
  final AuthService auth;
  final ListingService listingService;
  final ModerationService moderation;

  /// A client IP as stored: salted SHA-256, never the address itself.
  String hashIp(String ip) => sha256OfString('${config.jwtSecret}:ip:$ip');

  void close() => database.close();
}
