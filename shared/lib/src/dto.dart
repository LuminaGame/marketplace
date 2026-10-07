import 'package:lumina_marketplace_shared/src/categories.dart';
import 'package:lumina_marketplace_shared/src/licenses.dart';
import 'package:lumina_marketplace_shared/src/plugin_package.dart';

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

enum SearchSort {
  relevance('relevance', 'Relevance'),
  newest('newest', 'Newest'),
  downloads('downloads', 'Most downloaded'),
  name('name', 'Name');

  const SearchSort(this.wire, this.label);
  final String wire;
  final String label;

  static SearchSort? tryParse(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// `GET /listings` query.
class SearchQuery {
  const SearchQuery({
    this.q,
    this.category,
    this.licenseKind,
    this.license,
    this.engineVersion,
    this.free,
    this.publisher,
    this.featured,
    this.sort,
    this.page = 1,
    this.pageSize = 24,
  });

  final String? q;
  final ListingCategory? category;
  final LicenseKind? licenseKind;
  final String? license;

  /// Listings compatible with this engine version (their minimum ≤ it).
  final String? engineVersion;
  final bool? free;

  /// A publisher's username.
  final String? publisher;
  final bool? featured;

  /// Defaults to relevance with [q], newest without.
  final SearchSort? sort;
  final int page;
  final int pageSize;

  SearchQuery copyWith({
    String? q,
    ListingCategory? category,
    LicenseKind? licenseKind,
    String? license,
    String? engineVersion,
    bool? free,
    String? publisher,
    bool? featured,
    SearchSort? sort,
    int? page,
    int? pageSize,
    bool clearCategory = false,
    bool clearLicenseKind = false,
    bool clearLicense = false,
    bool clearEngineVersion = false,
    bool clearFree = false,
    bool clearSort = false,
  }) =>
      SearchQuery(
        q: q ?? this.q,
        category: clearCategory ? null : category ?? this.category,
        licenseKind: clearLicenseKind ? null : licenseKind ?? this.licenseKind,
        license: clearLicense ? null : license ?? this.license,
        engineVersion: clearEngineVersion ? null : engineVersion ?? this.engineVersion,
        free: clearFree ? null : free ?? this.free,
        publisher: publisher ?? this.publisher,
        featured: featured ?? this.featured,
        sort: clearSort ? null : sort ?? this.sort,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
      );

  Map<String, String> toQueryParameters() => {
        if (q != null && q!.isNotEmpty) 'q': q!,
        if (category != null) 'category': category!.wire,
        if (licenseKind != null) 'licenseKind': licenseKind!.wire,
        'license': ?license,
        'engineVersion': ?engineVersion,
        if (free != null) 'free': '$free',
        'publisher': ?publisher,
        if (featured != null) 'featured': '$featured',
        if (sort != null) 'sort': sort!.wire,
        if (page != 1) 'page': '$page',
        if (pageSize != 24) 'pageSize': '$pageSize',
      };

  factory SearchQuery.fromQueryParameters(Map<String, String> p) {
    bool? flag(String k) => p[k] == null ? null : p[k] == 'true' || p[k] == '1';
    return SearchQuery(
      q: p['q'],
      category: ListingCategory.tryParse(p['category']),
      licenseKind: LicenseKind.tryParse(p['licenseKind']),
      license: p['license'],
      engineVersion: p['engineVersion'],
      free: flag('free'),
      publisher: p['publisher'],
      featured: flag('featured'),
      sort: SearchSort.tryParse(p['sort']),
      page: int.tryParse(p['page'] ?? '') ?? 1,
      pageSize: int.tryParse(p['pageSize'] ?? '') ?? 24,
    );
  }
}

/// One page of results.
class ResultPage<T> {
  const ResultPage({required this.items, required this.total, required this.page, required this.pageSize});

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
  bool get hasNext => page < pageCount;
  bool get hasPrevious => page > 1;

  Map<String, Object?> toJson(Object? Function(T) item) => {
        'items': [for (final i in items) item(i)],
        'total': total,
        'page': page,
        'pageSize': pageSize,
      };

  factory ResultPage.fromJson(Map<String, Object?> j, T Function(Map<String, Object?>) item) => ResultPage(
        items: [for (final i in j['items'] as List) item(_map(i))],
        total: j['total'] as int,
        page: j['page'] as int,
        pageSize: j['pageSize'] as int,
      );
}

/// An entry of `GET /library`.
class LibraryEntry {
  const LibraryEntry({required this.listing, required this.acquiredAt});

  final Listing listing;
  final DateTime acquiredAt;

  Map<String, Object?> toJson() => {'listing': listing.toJson(), 'acquiredAt': acquiredAt.toIso8601String()};

  factory LibraryEntry.fromJson(Map<String, Object?> j) =>
      LibraryEntry(listing: Listing.fromJson(_map(j['listing'])), acquiredAt: _date(j['acquiredAt']));
}

/// One file of an install manifest.
class ManifestFile {
  const ManifestFile({required this.path, required this.size, required this.sha256, required this.target, required this.url});

  /// Path inside the archive.
  final String path;
  final int size;
  final String sha256;

  /// Where the file goes, relative to the install root of [InstallManifest.installKind]
  /// (the project root for `project_contents`).
  final String target;

  /// Server-relative URL of this single file.
  final String url;

  Map<String, Object?> toJson() => {'path': path, 'size': size, 'sha256': sha256, 'target': target, 'url': url};

  factory ManifestFile.fromJson(Map<String, Object?> j) => ManifestFile(
        path: j['path'] as String,
        size: j['size'] as int,
        sha256: j['sha256'] as String,
        target: j['target'] as String,
        url: j['url'] as String,
      );
}

/// `GET /listings/{id}/versions/{v}/manifest`: everything Lumina Studio needs
/// to install a version.
class InstallManifest {
  const InstallManifest({
    required this.formatVersion,
    required this.listingId,
    required this.slug,
    required this.title,
    required this.category,
    required this.version,
    required this.engineVersion,
    required this.publisher,
    required this.installKind,
    required this.targetRoot,
    required this.folderName,
    required this.archiveUrl,
    required this.archiveSha256,
    required this.archiveSize,
    required this.licenses,
    required this.files,
  });

  /// Bumped on breaking changes to this shape (currently 1).
  final int formatVersion;
  final String listingId;
  final String slug;
  final String title;
  final ListingCategory category;
  final String version;
  final String engineVersion;
  final PublisherSummary publisher;
  final InstallKind installKind;

  /// Target folder with a trailing slash, e.g.
  /// `contents/Marketplace/<Publisher>/<Listing>/`.
  final String targetRoot;

  /// The sanitized `<Listing>` folder name (for `LICENSE-<folderName>.txt`).
  final String folderName;
  final String archiveUrl;
  final String archiveSha256;
  final int archiveSize;
  final List<LicenseInfo> licenses;
  final List<ManifestFile> files;

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'listingId': listingId,
        'slug': slug,
        'title': title,
        'category': category.wire,
        'version': version,
        'engineVersion': engineVersion,
        'publisher': publisher.toJson(),
        'installKind': installKind.wire,
        'targetRoot': targetRoot,
        'folderName': folderName,
        'archive': {'url': archiveUrl, 'sha256': archiveSha256, 'size': archiveSize},
        'licenses': [for (final l in licenses) l.toJson()],
        'files': [for (final f in files) f.toJson()],
      };

  factory InstallManifest.fromJson(Map<String, Object?> j) {
    final archive = _map(j['archive']);
    return InstallManifest(
      formatVersion: j['formatVersion'] as int,
      listingId: j['listingId'] as String,
      slug: j['slug'] as String,
      title: j['title'] as String,
      category: ListingCategory.tryParse(j['category'] as String?) ?? ListingCategory.model,
      version: j['version'] as String,
      engineVersion: j['engineVersion'] as String,
      publisher: PublisherSummary.fromJson(_map(j['publisher'])),
      installKind: InstallKind.tryParse(j['installKind'] as String?) ?? InstallKind.projectContents,
      targetRoot: j['targetRoot'] as String,
      folderName: j['folderName'] as String,
      archiveUrl: archive['url'] as String,
      archiveSha256: archive['sha256'] as String,
      archiveSize: archive['size'] as int,
      licenses: [for (final l in j['licenses'] as List) LicenseInfo.fromJson(_map(l))],
      files: [for (final f in j['files'] as List) ManifestFile.fromJson(_map(f))],
    );
  }
}

enum ReportReason {
  stolenContent('stolen_content', "Someone else's (paid) work"),
  licenseViolation('license_violation', 'Wrong or violated license'),
  malware('malware', 'Malware or harmful code'),
  broken('broken', 'Broken or not as described'),
  inappropriate('inappropriate', 'Inappropriate content'),
  spam('spam', 'Spam'),
  other('other', 'Other');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;

  static ReportReason? tryParse(String? wire) {
    for (final r in values) {
      if (r.wire == wire) return r;
    }
    return null;
  }
}

enum ReportStatus {
  open('open'),
  dismissed('dismissed'),
  actioned('actioned');

  const ReportStatus(this.wire);
  final String wire;

  static ReportStatus parse(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => ReportStatus.open);
}

class ListingReport {
  const ListingReport({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.listingStatus,
    required this.publisher,
    required this.reporter,
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
  final String listingTitle;
  final ListingStatus listingStatus;
  final PublisherSummary publisher;
  final String reporter;
  final ReportReason reason;
  final String details;
  final ReportStatus status;
  final DateTime createdAt;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final String? resolutionNote;

  Map<String, Object?> toJson() => {
        'id': id,
        'listingId': listingId,
        'listingTitle': listingTitle,
        'listingStatus': listingStatus.wire,
        'publisher': publisher.toJson(),
        'reporter': reporter,
        'reason': reason.wire,
        'details': details,
        'status': status.wire,
        'createdAt': createdAt.toIso8601String(),
        'resolvedBy': resolvedBy,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'resolutionNote': resolutionNote,
      };

  factory ListingReport.fromJson(Map<String, Object?> j) => ListingReport(
        id: j['id'] as String,
        listingId: j['listingId'] as String,
        listingTitle: j['listingTitle'] as String,
        listingStatus: ListingStatus.parse(j['listingStatus'] as String?),
        publisher: PublisherSummary.fromJson(_map(j['publisher'])),
        reporter: j['reporter'] as String,
        reason: ReportReason.tryParse(j['reason'] as String?) ?? ReportReason.other,
        details: j['details'] as String? ?? '',
        status: ReportStatus.parse(j['status'] as String?),
        createdAt: _date(j['createdAt']),
        resolvedBy: j['resolvedBy'] as String?,
        resolvedAt: _dateOrNull(j['resolvedAt']),
        resolutionNote: j['resolutionNote'] as String?,
      );
}

/// An immutable moderation/audit record.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.details,
    required this.createdAt,
  });

  final int id;

  /// Username of whoever acted (`system` for automatic cascades).
  final String actor;

  /// `listing.unlist`, `listing.restore`, `user.suspend`, `report.resolve`, …
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, Object?> details;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'actor': actor,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'details': details,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AuditEntry.fromJson(Map<String, Object?> j) => AuditEntry(
        id: j['id'] as int,
        actor: j['actor'] as String,
        action: j['action'] as String,
        targetType: j['targetType'] as String,
        targetId: j['targetId'] as String,
        details: _map(j['details'] ?? const <String, Object?>{}),
        createdAt: _date(j['createdAt']),
      );
}

/// `GET /terms`: the publishing terms, including the ownership attestation and
/// its penalty clause.
class Terms {
  const Terms({required this.version, required this.attestationStatement, required this.penalty, required this.text});

  final String version;

  /// The checkbox label the uploader ticks.
  final String attestationStatement;

  /// What happens to a publisher who publishes someone else's work.
  final String penalty;

  /// The full terms (Markdown).
  final String text;

  Map<String, Object?> toJson() =>
      {'version': version, 'attestationStatement': attestationStatement, 'penalty': penalty, 'text': text};

  factory Terms.fromJson(Map<String, Object?> j) => Terms(
        version: j['version'] as String,
        attestationStatement: j['attestationStatement'] as String,
        penalty: j['penalty'] as String,
        text: j['text'] as String,
      );
}

/// A public profile: the user plus their published listings.
class PublisherProfile {
  const PublisherProfile({required this.publisher, required this.listings, required this.joinedAt});

  final PublisherSummary publisher;
  final List<Listing> listings;
  final DateTime joinedAt;

  Map<String, Object?> toJson() => {
        'publisher': publisher.toJson(),
        'joinedAt': joinedAt.toIso8601String(),
        'listings': [for (final l in listings) l.toJson()],
      };

  factory PublisherProfile.fromJson(Map<String, Object?> j) => PublisherProfile(
        publisher: PublisherSummary.fromJson(_map(j['publisher'])),
        joinedAt: _date(j['joinedAt']),
        listings: [for (final l in j['listings'] as List) Listing.fromJson(_map(l))],
      );
}

/// The answer to a crash report (`POST /crash-reports`): the id the server
/// filed it under and when it arrived.
class CrashReportReceipt {
  const CrashReportReceipt({required this.id, required this.receivedAt});

  final String id;
  final DateTime receivedAt;

  Map<String, Object?> toJson() => {'id': id, 'receivedAt': receivedAt.toIso8601String()};

  factory CrashReportReceipt.fromJson(Map<String, Object?> j) =>
      CrashReportReceipt(id: j['id'] as String, receivedAt: _date(j['receivedAt']));
}
