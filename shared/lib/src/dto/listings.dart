part of '../dto.dart';

enum ListingStatus {
  /// Created, no version published yet: only the publisher sees it.
  draft('draft'),
  published('published'),

  /// Hidden from search and listing pages (by the publisher or a moderator).
  unlisted('unlisted');

  const ListingStatus(this.wire);
  final String wire;

  static ListingStatus parse(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => ListingStatus.draft);
}

/// A file inside an uploaded version.
class ArchiveEntry {
  const ArchiveEntry({required this.path, required this.size});

  /// Forward-slash path relative to the archive root; validated server-side
  /// (no `..`, no absolute paths, allowed extensions only).
  final String path;
  final int size;

  Map<String, Object?> toJson() => {'path': path, 'size': size};

  factory ArchiveEntry.fromJson(Map<String, Object?> j) =>
      ArchiveEntry(path: j['path'] as String, size: j['size'] as int);
}

/// An upload that passed validation and waits to be attached to a version.
class UploadInfo {
  const UploadInfo({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.size,
    required this.sha256,
    required this.files,
    required this.detectedLicenseKinds,
    this.plugin,
    this.skippedPaths = const [],
    this.skippedFileCount = 0,
  });

  final String id;
  final String fileName;

  /// `zip` or `json`.
  final String kind;
  final int size;
  final String sha256;
  final List<ArchiveEntry> files;

  /// License kinds the files need (`.dart` → code, `.glb` → content).
  final Set<LicenseKind> detectedLicenseKinds;

  /// The plugin package it holds: set when the upload named the
  /// `plugin` category, parsed from its `.lmplugin` manifest, license text and
  /// changelog.
  final PluginPackageInfo? plugin;

  /// Generated folders left out of a plugin upload (`build/`, `.dart_tool/`,
  /// `.git/`, …), as archive paths ending in `/`, and how many files
  /// they held. The stored archive is repacked without them.
  final List<String> skippedPaths;
  final int skippedFileCount;

  Map<String, Object?> toJson() => {
        'id': id,
        'fileName': fileName,
        'kind': kind,
        'size': size,
        'sha256': sha256,
        'files': [for (final f in files) f.toJson()],
        'detectedLicenseKinds': [for (final k in detectedLicenseKinds) k.wire],
        'plugin': ?plugin?.toJson(),
        if (skippedPaths.isNotEmpty) 'skippedPaths': skippedPaths,
        if (skippedFileCount > 0) 'skippedFileCount': skippedFileCount,
      };

  factory UploadInfo.fromJson(Map<String, Object?> j) => UploadInfo(
        id: j['id'] as String,
        fileName: j['fileName'] as String,
        kind: j['kind'] as String,
        size: j['size'] as int,
        sha256: j['sha256'] as String,
        files: [for (final f in j['files'] as List) ArchiveEntry.fromJson(_map(f))],
        detectedLicenseKinds: {
          for (final k in _strings(j['detectedLicenseKinds'])) ?LicenseKind.tryParse(k),
        },
        plugin: j['plugin'] == null ? null : PluginPackageInfo.fromJson(_map(j['plugin'])),
        skippedPaths: _strings(j['skippedPaths']),
        skippedFileCount: j['skippedFileCount'] as int? ?? 0,
      );
}

/// A published version of a listing.
class ListingVersion {
  const ListingVersion({
    required this.id,
    required this.version,
    required this.releaseNotes,
    required this.engineVersion,
    required this.licenses,
    required this.archiveKind,
    required this.fileName,
    required this.size,
    required this.sha256,
    required this.fileCount,
    required this.downloadCount,
    required this.createdAt,
    this.previewModelUrl,
    this.previewModelSha256,
    this.previewModelSize,
    this.previewModelSource,
  });

  final String id;

  /// Semver, e.g. `1.0.0`; unique per listing.
  final String version;
  final String releaseNotes;

  /// Minimum Lumina engine version, e.g. `0.0.1`.
  final String engineVersion;
  final LicenseSelection licenses;
  final String archiveKind;
  final String fileName;
  final int size;
  final String sha256;
  final int fileCount;
  final int downloadCount;
  final DateTime createdAt;

  /// The public, server-relative URL of the version's preview model (a
  /// self-contained `.glb` the server derived from the archive), or
  /// null when the version has none (not a model listing, no mesh, too big).
  final String? previewModelUrl;
  final String? previewModelSha256;
  final int? previewModelSize;

  /// The archive path the preview was derived from.
  final String? previewModelSource;

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'releaseNotes': releaseNotes,
        'engineVersion': engineVersion,
        'contentLicense': licenses.content,
        'codeLicense': licenses.code,
        'archiveKind': archiveKind,
        'fileName': fileName,
        'size': size,
        'sha256': sha256,
        'fileCount': fileCount,
        'downloadCount': downloadCount,
        'createdAt': createdAt.toIso8601String(),
        'previewModelUrl': previewModelUrl,
        'previewModelSha256': previewModelSha256,
        'previewModelSize': previewModelSize,
        'previewModelSource': previewModelSource,
      };

  factory ListingVersion.fromJson(Map<String, Object?> j) => ListingVersion(
        id: j['id'] as String,
        version: j['version'] as String,
        releaseNotes: j['releaseNotes'] as String? ?? '',
        engineVersion: j['engineVersion'] as String,
        licenses: LicenseSelection(content: j['contentLicense'] as String?, code: j['codeLicense'] as String?),
        archiveKind: j['archiveKind'] as String,
        fileName: j['fileName'] as String,
        size: j['size'] as int,
        sha256: j['sha256'] as String,
        fileCount: j['fileCount'] as int,
        downloadCount: j['downloadCount'] as int? ?? 0,
        createdAt: _date(j['createdAt']),
        previewModelUrl: j['previewModelUrl'] as String?,
        previewModelSha256: j['previewModelSha256'] as String?,
        previewModelSize: j['previewModelSize'] as int?,
        previewModelSource: j['previewModelSource'] as String?,
      );
}

/// A listing: a card in search results, or a full page when [versions] is set.
class Listing {
  const Listing({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.category,
    required this.tags,
    required this.engineVersion,
    required this.priceCents,
    required this.currency,
    required this.status,
    required this.featured,
    required this.publisher,
    required this.screenshots,
    required this.downloadCount,
    required this.licenses,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.latestVersion,
    this.versions,
    this.unlistedBy,
    this.unlistedReason,
    this.inLibrary,
  });

  final String id;
  final String slug;
  final String title;

  /// Markdown.
  final String description;
  final ListingCategory category;
  final List<String> tags;
  final String engineVersion;

  /// Always 0 for now: publishing is free-only.
  final int priceCents;
  final String currency;
  final ListingStatus status;
  final bool featured;
  final PublisherSummary publisher;

  /// Server-relative image URLs.
  final List<String> screenshots;
  final int downloadCount;

  /// The latest version's licenses.
  final LicenseSelection licenses;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final ListingVersion? latestVersion;

  /// Every published version, newest first; only on the detail endpoint.
  final List<ListingVersion>? versions;

  /// `owner` or `moderator` when [status] is unlisted.
  final String? unlistedBy;
  final String? unlistedReason;

  /// Whether the caller has it in their library (detail endpoint, signed in).
  final bool? inLibrary;

  bool get isFree => priceCents == 0;

  /// The latest version's preview model: the listing page shows a
  /// 3D view when it is set.
  String? get previewModelUrl => latestVersion?.previewModelUrl;

  Map<String, Object?> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        'description': description,
        'category': category.wire,
        'tags': tags,
        'engineVersion': engineVersion,
        'priceCents': priceCents,
        'currency': currency,
        'status': status.wire,
        'featured': featured,
        'publisher': publisher.toJson(),
        'screenshots': screenshots,
        'downloadCount': downloadCount,
        'contentLicense': licenses.content,
        'codeLicense': licenses.code,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'publishedAt': publishedAt?.toIso8601String(),
        'latestVersion': latestVersion?.toJson(),
        'previewModelUrl': previewModelUrl,
        if (versions != null) 'versions': [for (final v in versions!) v.toJson()],
        if (unlistedBy != null) 'unlistedBy': unlistedBy,
        if (unlistedReason != null) 'unlistedReason': unlistedReason,
        if (inLibrary != null) 'inLibrary': inLibrary,
      };

  factory Listing.fromJson(Map<String, Object?> j) => Listing(
        id: j['id'] as String,
        slug: j['slug'] as String,
        title: j['title'] as String,
        description: j['description'] as String? ?? '',
        category: ListingCategory.tryParse(j['category'] as String?) ?? ListingCategory.model,
        tags: _strings(j['tags']),
        engineVersion: j['engineVersion'] as String,
        priceCents: j['priceCents'] as int? ?? 0,
        currency: j['currency'] as String? ?? 'USD',
        status: ListingStatus.parse(j['status'] as String?),
        featured: j['featured'] as bool? ?? false,
        publisher: PublisherSummary.fromJson(_map(j['publisher'])),
        screenshots: _strings(j['screenshots']),
        downloadCount: j['downloadCount'] as int? ?? 0,
        licenses: LicenseSelection(content: j['contentLicense'] as String?, code: j['codeLicense'] as String?),
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
        publishedAt: _dateOrNull(j['publishedAt']),
        latestVersion: j['latestVersion'] == null ? null : ListingVersion.fromJson(_map(j['latestVersion'])),
        versions: j['versions'] == null
            ? null
            : [for (final v in j['versions'] as List) ListingVersion.fromJson(_map(v))],
        unlistedBy: j['unlistedBy'] as String?,
        unlistedReason: j['unlistedReason'] as String?,
        inLibrary: j['inLibrary'] as bool?,
      );
}

/// `POST /listings` body.
class NewListing {
  const NewListing({
    required this.category,
    required this.title,
    this.description = '',
    this.tags = const [],
    this.engineVersion = '0.0.1',
    this.priceCents = 0,
    this.currency = 'USD',
  });

  final ListingCategory category;
  final String title;
  final String description;
  final List<String> tags;
  final String engineVersion;
  final int priceCents;
  final String currency;

  Map<String, Object?> toJson() => {
        'category': category.wire,
        'title': title,
        'description': description,
        'tags': tags,
        'engineVersion': engineVersion,
        'priceCents': priceCents,
        'currency': currency,
      };
}

/// `POST /listings/{id}/versions` body.
class NewVersion {
  const NewVersion({
    required this.version,
    required this.uploadId,
    required this.licenses,
    required this.attestation,
    required this.termsVersion,
    this.releaseNotes = '',
    this.engineVersion,
  });

  final String version;
  final String uploadId;
  final LicenseSelection licenses;

  /// "I own this work or have the right to publish it under the chosen
  /// license." Must be true.
  final bool attestation;

  /// The `Terms.version` the uploader accepted.
  final String termsVersion;
  final String releaseNotes;

  /// Defaults to the listing's engine version.
  final String? engineVersion;

  Map<String, Object?> toJson() => {
        'version': version,
        'uploadId': uploadId,
        'contentLicense': licenses.content,
        'codeLicense': licenses.code,
        'attestation': {'accepted': attestation, 'termsVersion': termsVersion},
        'releaseNotes': releaseNotes,
        if (engineVersion != null) 'engineVersion': engineVersion,
      };
}
