part of '../dto.dart';

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
