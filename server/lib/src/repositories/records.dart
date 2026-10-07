import 'dart:convert';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

import 'package:lumina_marketplace_server/src/storage/zip_validator.dart';

// Rows as the repositories return them. Services turn them into the shared
// DTOs.

class UserRecord {
  const UserRecord({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.passwordHash,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.avatarSha256,
    this.suspendedReason,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarSha256;
  final String passwordHash;
  final UserRole role;
  final UserStatus status;
  final String? suspendedReason;
  final String createdAt;
  final String updatedAt;

  String? get avatarUrl => avatarSha256 == null ? null : '/api/v1/media/$avatarSha256';

  PublisherSummary toPublisher() =>
      PublisherSummary(id: id, username: username, displayName: displayName, avatarUrl: avatarUrl);

  MarketplaceUser toDto({bool includeEmail = false}) => MarketplaceUser(
        id: id,
        username: username,
        displayName: displayName,
        email: includeEmail ? email : null,
        avatarUrl: avatarUrl,
        role: role,
        status: status,
        createdAt: DateTime.parse(createdAt),
      );

  factory UserRecord.fromRow(Map<String, Object?> r) => UserRecord(
        id: r['id'] as String,
        email: r['email'] as String,
        username: r['username'] as String,
        displayName: r['display_name'] as String,
        avatarSha256: r['avatar_sha256'] as String?,
        passwordHash: r['password_hash'] as String,
        role: UserRole.parse(r['role'] as String?),
        status: UserStatus.parse(r['status'] as String?),
        suspendedReason: r['suspended_reason'] as String?,
        createdAt: r['created_at'] as String,
        updatedAt: r['updated_at'] as String,
      );
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.userId,
    required this.refreshHash,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    this.revokedAt,
    this.revokedReason,
    this.userAgent,
    this.ipHash,
  });

  final String id;
  final String userId;
  final String refreshHash;
  final String createdAt;
  final String lastUsedAt;
  final String expiresAt;
  final String? revokedAt;
  final String? revokedReason;
  final String? userAgent;
  final String? ipHash;

  bool get isRevoked => revokedAt != null;
  bool get isExpired => DateTime.parse(expiresAt).isBefore(DateTime.now().toUtc());

  factory SessionRecord.fromRow(Map<String, Object?> r) => SessionRecord(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        refreshHash: r['refresh_hash'] as String,
        createdAt: r['created_at'] as String,
        lastUsedAt: r['last_used_at'] as String,
        expiresAt: r['expires_at'] as String,
        revokedAt: r['revoked_at'] as String?,
        revokedReason: r['revoked_reason'] as String?,
        userAgent: r['user_agent'] as String?,
        ipHash: r['ip_hash'] as String?,
      );
}

class MediaRecord {
  const MediaRecord(this.sha256, this.contentType, this.size);
  final String sha256;
  final String contentType;
  final int size;
}

/// A derived preview model: its blob, size and archive path.
class PreviewInfo {
  const PreviewInfo({required this.sha256, required this.size, required this.source});
  final String sha256;
  final int size;
  final String source;

  static PreviewInfo? fromRow(Map<String, Object?> r) => r['preview_sha256'] == null
      ? null
      : PreviewInfo(
          sha256: r['preview_sha256'] as String,
          size: r['preview_size'] as int,
          source: r['preview_source'] as String,
        );
}

class UploadRecord {
  const UploadRecord({
    required this.id,
    required this.userId,
    required this.blobSha256,
    required this.fileName,
    required this.kind,
    required this.size,
    required this.files,
    required this.detectedKinds,
    required this.createdAt,
    this.consumedAt,
    this.preview,
    this.plugin,
    this.skipped = const {},
  });

  final String id;
  final String userId;
  final String blobSha256;
  final String fileName;
  final String kind;
  final int size;
  final List<ValidatedFile> files;
  final Set<LicenseKind> detectedKinds;
  final String createdAt;
  final String? consumedAt;

  /// The preview model derived from the archive, if it has one.
  final PreviewInfo? preview;

  /// The plugin package it holds, parsed on an upload that named the
  /// `plugin` category. Not stored: publish re-reads the archive.
  final PluginPackageInfo? plugin;

  /// Generated folders left out of the upload, folder → file count.
  /// Not stored, like [plugin].
  final Map<String, int> skipped;

  UploadInfo toDto() => UploadInfo(
        id: id,
        fileName: fileName,
        kind: kind,
        size: size,
        sha256: blobSha256,
        files: [for (final f in files) ArchiveEntry(path: f.path, size: f.size)],
        detectedLicenseKinds: detectedKinds,
        plugin: plugin,
        skippedPaths: skipped.keys.toList(),
        skippedFileCount: skipped.values.fold(0, (a, b) => a + b),
      );

  factory UploadRecord.fromRow(Map<String, Object?> r) => UploadRecord(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        blobSha256: r['blob_sha256'] as String,
        fileName: r['file_name'] as String,
        kind: r['kind'] as String,
        size: r['size'] as int,
        files: decodeFiles(r['files_json'] as String),
        detectedKinds: {
          for (final k in (r['detected_kinds'] as String).split(',')) ?LicenseKind.tryParse(k),
        },
        createdAt: r['created_at'] as String,
        consumedAt: r['consumed_at'] as String?,
        preview: PreviewInfo.fromRow(r),
      );
}

List<ValidatedFile> decodeFiles(String json) =>
    [for (final f in jsonDecode(json) as List) ValidatedFile.fromJson((f as Map).cast())];

String encodeFiles(List<ValidatedFile> files) => jsonEncode([for (final f in files) f.toJson()]);

class ListingRecord {
  const ListingRecord({
    required this.id,
    required this.slug,
    required this.publisherId,
    required this.category,
    required this.title,
    required this.description,
    required this.tags,
    required this.engineVersion,
    required this.priceCents,
    required this.currency,
    required this.status,
    required this.featured,
    required this.screenshots,
    required this.downloadCount,
    required this.createdAt,
    required this.updatedAt,
    this.unlistedBy,
    this.unlistedReason,
    this.contentLicense,
    this.codeLicense,
    this.latestVersionId,
    this.publishedAt,
  });

  final String id;
  final String slug;
  final String publisherId;
  final ListingCategory category;
  final String title;
  final String description;
  final List<String> tags;
  final String engineVersion;
  final int priceCents;
  final String currency;
  final ListingStatus status;
  final String? unlistedBy;
  final String? unlistedReason;
  final bool featured;

  /// Media SHA-256s.
  final List<String> screenshots;
  final int downloadCount;
  final String? contentLicense;
  final String? codeLicense;
  final String? latestVersionId;
  final String createdAt;
  final String updatedAt;
  final String? publishedAt;

  factory ListingRecord.fromRow(Map<String, Object?> r) => ListingRecord(
        id: r['id'] as String,
        slug: r['slug'] as String,
        publisherId: r['publisher_id'] as String,
        category: ListingCategory.tryParse(r['category'] as String?)!,
        title: r['title'] as String,
        description: r['description'] as String,
        tags: [for (final t in jsonDecode(r['tags_json'] as String) as List) t as String],
        engineVersion: r['engine_version'] as String,
        priceCents: r['price_cents'] as int,
        currency: r['currency'] as String,
        status: ListingStatus.parse(r['status'] as String?),
        unlistedBy: r['unlisted_by'] as String?,
        unlistedReason: r['unlisted_reason'] as String?,
        featured: (r['featured'] as int) == 1,
        screenshots: [for (final s in jsonDecode(r['screenshots_json'] as String) as List) s as String],
        downloadCount: r['download_count'] as int,
        contentLicense: r['content_license'] as String?,
        codeLicense: r['code_license'] as String?,
        latestVersionId: r['latest_version_id'] as String?,
        createdAt: r['created_at'] as String,
        updatedAt: r['updated_at'] as String,
        publishedAt: r['published_at'] as String?,
      );
}

class VersionRecord {
  const VersionRecord({
    required this.id,
    required this.listingId,
    required this.version,
    required this.releaseNotes,
    required this.engineVersion,
    required this.uploadId,
    required this.blobSha256,
    required this.archiveKind,
    required this.fileName,
    required this.size,
    required this.files,
    required this.downloadCount,
    required this.createdAt,
    this.contentLicense,
    this.codeLicense,
    this.preview,
    this.previewState,
  });

  final String id;
  final String listingId;
  final String version;
  final String releaseNotes;
  final String engineVersion;
  final String? contentLicense;
  final String? codeLicense;
  final String uploadId;
  final String blobSha256;
  final String archiveKind;
  final String fileName;
  final int size;
  final List<ValidatedFile> files;
  final int downloadCount;
  final String createdAt;

  /// The version's preview model; null when it has none.
  final PreviewInfo? preview;

  /// `ready` / `none`, or null before the preview was derived (versions
  /// published before migration 2, until the start-up backfill).
  final String? previewState;

  /// The public route that serves [preview].
  String get previewUrl => '/api/v1/listings/$listingId/versions/$version/preview.glb';

  ListingVersion toDto() => ListingVersion(
        id: id,
        version: version,
        releaseNotes: releaseNotes,
        engineVersion: engineVersion,
        licenses: LicenseSelection(content: contentLicense, code: codeLicense),
        archiveKind: archiveKind,
        fileName: fileName,
        size: size,
        sha256: blobSha256,
        fileCount: files.length,
        downloadCount: downloadCount,
        createdAt: DateTime.parse(createdAt),
        previewModelUrl: preview == null ? null : previewUrl,
        previewModelSha256: preview?.sha256,
        previewModelSize: preview?.size,
        previewModelSource: preview?.source,
      );

  factory VersionRecord.fromRow(Map<String, Object?> r) => VersionRecord(
        id: r['id'] as String,
        listingId: r['listing_id'] as String,
        version: r['version'] as String,
        releaseNotes: r['release_notes'] as String,
        engineVersion: r['engine_version'] as String,
        contentLicense: r['content_license'] as String?,
        codeLicense: r['code_license'] as String?,
        uploadId: r['upload_id'] as String,
        blobSha256: r['blob_sha256'] as String,
        archiveKind: r['archive_kind'] as String,
        fileName: r['file_name'] as String,
        size: r['size'] as int,
        files: decodeFiles(r['files_json'] as String),
        downloadCount: r['download_count'] as int,
        createdAt: r['created_at'] as String,
        preview: PreviewInfo.fromRow(r),
        previewState: r['preview_state'] as String?,
      );
}

class AttestationRecord {
  const AttestationRecord({
    required this.id,
    required this.userId,
    required this.listingId,
    required this.versionId,
    required this.termsVersion,
    required this.statement,
    required this.acceptedAt,
    required this.ipHash,
  });

  final String id;
  final String userId;
  final String listingId;
  final String versionId;
  final String termsVersion;
  final String statement;
  final String acceptedAt;
  final String ipHash;

  factory AttestationRecord.fromRow(Map<String, Object?> r) => AttestationRecord(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        listingId: r['listing_id'] as String,
        versionId: r['version_id'] as String,
        termsVersion: r['terms_version'] as String,
        statement: r['statement'] as String,
        acceptedAt: r['accepted_at'] as String,
        ipHash: r['ip_hash'] as String,
      );
}

class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.listingId,
    required this.reporterId,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
    this.resolvedBy,
    this.resolvedAt,
    this.resolutionNote,
  });

  final String id;
  final String listingId;
  final String reporterId;
  final ReportReason reason;
  final String details;
  final ReportStatus status;
  final String createdAt;
  final String? resolvedBy;
  final String? resolvedAt;
  final String? resolutionNote;

  factory ReportRecord.fromRow(Map<String, Object?> r) => ReportRecord(
        id: r['id'] as String,
        listingId: r['listing_id'] as String,
        reporterId: r['reporter_id'] as String,
        reason: ReportReason.tryParse(r['reason'] as String?) ?? ReportReason.other,
        details: r['details'] as String,
        status: ReportStatus.parse(r['status'] as String?),
        createdAt: r['created_at'] as String,
        resolvedBy: r['resolved_by'] as String?,
        resolvedAt: r['resolved_at'] as String?,
        resolutionNote: r['resolution_note'] as String?,
      );
}
