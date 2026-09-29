import 'dart:convert';
import 'dart:typed_data';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:sqlite3/sqlite3.dart';

import '../db/database.dart';
import '../errors.dart';
import '../repositories/records.dart';
import '../repositories/repositories.dart';
import '../storage/blob_store.dart';
import '../storage/game_template_validator.dart';
import '../storage/plugin_package_validator.dart';
import '../storage/preview_model.dart';
import '../storage/zip_validator.dart';
import '../terms.dart';
import '../util.dart';
import 'auth_service.dart';

final _tagPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');
final _currencyPattern = RegExp(r'^[A-Z]{3}$');

/// Listings, versions, uploads, the library and install manifests.
class ListingService {
  ListingService({
    required this.db,
    required this.listings,
    required this.users,
    required this.uploads,
    required this.attestations,
    required this.library,
    required this.audit,
    required this.blobs,
    required this.validator,
    required this.auth,
    required this.maxUploadBytes,
    this.maxPreviewBytes = 32 * 1024 * 1024,
    this.templateValidator = const GameTemplateValidator(),
    this.pluginValidator = const PluginPackageValidator(),
  });

  final Database db;
  final ListingRepository listings;
  final UserRepository users;
  final UploadRepository uploads;
  final AttestationRepository attestations;
  final LibraryRepository library;
  final AuditRepository audit;
  final BlobStore blobs;
  final ZipValidator validator;
  final AuthService auth;
  final int maxUploadBytes;
  final int maxPreviewBytes;
  final GameTemplateValidator templateValidator;
  final PluginPackageValidator pluginValidator;

  static const maxScreenshots = 8;

  // --- DTOs --------------------------------------------------------------------

  Listing toDto(ListingRecord r, {bool withVersions = false, bool? inLibrary, Map<String, UserRecord>? publishers}) {
    final publisher = publishers?[r.publisherId] ?? users.findById(r.publisherId)!;
    publishers?[r.publisherId] = publisher;
    final versions = withVersions ? listings.versionsOf(r.id) : null;
    final latest = r.latestVersionId == null
        ? null
        : versions?.firstWhere((v) => v.id == r.latestVersionId) ?? listings.findVersionById(r.latestVersionId!);
    return Listing(
      id: r.id,
      slug: r.slug,
      title: r.title,
      description: r.description,
      category: r.category,
      tags: r.tags,
      engineVersion: r.engineVersion,
      priceCents: r.priceCents,
      currency: r.currency,
      status: r.status,
      featured: r.featured,
      publisher: publisher.toPublisher(),
      screenshots: [for (final s in r.screenshots) '/api/v1/media/$s'],
      downloadCount: r.downloadCount,
      licenses: LicenseSelection(content: r.contentLicense, code: r.codeLicense),
      createdAt: DateTime.parse(r.createdAt),
      updatedAt: DateTime.parse(r.updatedAt),
      publishedAt: r.publishedAt == null ? null : DateTime.parse(r.publishedAt!),
      latestVersion: latest?.toDto(),
      versions: versions?.map((v) => v.toDto()).toList(),
      unlistedBy: r.unlistedBy,
      unlistedReason: r.unlistedReason,
      inLibrary: inLibrary,
    );
  }

  bool _isOwner(ListingRecord r, AuthContext? viewer) => viewer != null && viewer.user.id == r.publisherId;

  bool _visibleTo(ListingRecord r, AuthContext? viewer) =>
      r.status == ListingStatus.published || _isOwner(r, viewer) || (viewer?.canModerate ?? false);

  /// A listing by id or slug that [viewer] may see, else 404.
  ListingRecord findVisible(String idOrSlug, AuthContext? viewer) {
    final r = listings.findById(idOrSlug) ?? listings.findBySlug(idOrSlug);
    if (r == null || !_visibleTo(r, viewer)) throw ApiException.notFound('No such listing.');
    return r;
  }

  ListingRecord _findOwned(String id, AuthContext caller) {
    final r = listings.findById(id);
    if (r == null) throw ApiException.notFound('No such listing.');
    if (!_isOwner(r, caller)) throw ApiException.forbidden('Only the publisher can change this listing.');
    return r;
  }

  Listing detail(String idOrSlug, AuthContext? viewer) {
    final r = findVisible(idOrSlug, viewer);
    return toDto(r, withVersions: true, inLibrary: viewer == null ? null : library.acquiredAt(viewer.user.id, r.id) != null);
  }

  // --- Create & edit -------------------------------------------------------------

  static String _title(Object? v) {
    final t = (v as String? ?? '').trim();
    if (t.length < 3 || t.length > 80) throw ApiException.validation('Titles are 3–80 characters.', {'field': 'title'});
    return t;
  }

  static String _description(Object? v) {
    final d = v as String? ?? '';
    if (d.length > 20000) throw ApiException.validation('The description is too long.', {'field': 'description'});
    return d;
  }

  static List<String> _tags(Object? v) {
    final raw = v as List? ?? const [];
    final tags = <String>[];
    for (final t in raw) {
      final tag = (t as String).trim().toLowerCase();
      if (!_tagPattern.hasMatch(tag)) {
        throw ApiException.validation('Tags are lowercase letters, digits and "-", up to 32 characters.', {'field': 'tags'});
      }
      if (!tags.contains(tag)) tags.add(tag);
    }
    if (tags.length > 10) throw ApiException.validation('At most 10 tags.', {'field': 'tags'});
    return tags;
  }

  static String _engineVersion(Object? v) {
    final e = (v as String? ?? '0.0.1').trim();
    if (!isSemver(e)) throw ApiException.validation('Engine versions look like 0.0.1.', {'field': 'engineVersion'});
    return e;
  }

  static ListingCategory _category(Object? v) {
    final c = ListingCategory.tryParse(v as String?);
    if (c == null) {
      throw ApiException.validation(
          'Unknown category; use one of ${ListingCategory.values.map((c) => c.wire).join(', ')}.', {'field': 'category'});
    }
    return c;
  }

  ListingRecord create(AuthContext caller, Map<String, Object?> body) {
    final category = _category(body['category']);
    final title = _title(body['title']);
    final price = body['priceCents'] ?? 0;
    if (price is! int || price < 0) throw ApiException.validation('priceCents is a non-negative integer.');
    if (price != 0) {
      throw const ApiException(422, 'price_not_supported',
          'Paid listings are not available yet: publishing is free only for now (priceCents must be 0).');
    }
    final currency = (body['currency'] as String? ?? 'USD').toUpperCase();
    if (!_currencyPattern.hasMatch(currency)) throw ApiException.validation('currency is an ISO 4217 code.');
    final engine = _engineVersion(body['engineVersion']);
    final now = nowIso();
    var slug = slugify(title);
    if (listings.slugExists(slug)) {
      var n = 2;
      while (listings.slugExists('$slug-$n')) {
        n++;
      }
      slug = '$slug-$n';
    }
    final record = ListingRecord(
      id: newId(),
      slug: slug,
      publisherId: caller.user.id,
      category: category,
      title: title,
      description: _description(body['description']),
      tags: _tags(body['tags']),
      engineVersion: engine,
      priceCents: 0,
      currency: currency,
      status: ListingStatus.draft,
      featured: false,
      screenshots: const [],
      downloadCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    listings.create(record, engineVersionCode: semverCode(engine));
    return record;
  }

  ListingRecord update(AuthContext caller, String id, Map<String, Object?> body) {
    final r = _findOwned(id, caller);
    final columns = <String, Object?>{};
    if (body.containsKey('title')) columns['title'] = _title(body['title']);
    if (body.containsKey('description')) columns['description'] = _description(body['description']);
    if (body.containsKey('tags')) {
      final tags = _tags(body['tags']);
      columns['tags'] = tags.join(' ');
      columns['tags_json'] = jsonEncode(tags);
    }
    if (body.containsKey('engineVersion')) {
      final e = _engineVersion(body['engineVersion']);
      columns['engine_version'] = e;
      columns['engine_version_code'] = semverCode(e);
    }
    if (body.containsKey('category')) {
      if (r.latestVersionId != null) throw ApiException.conflict('The category cannot change once a version is published.');
      columns['category'] = _category(body['category']).wire;
    }
    if (body.containsKey('priceCents') && body['priceCents'] != 0) {
      throw const ApiException(422, 'price_not_supported', 'Publishing is free only for now (priceCents must be 0).');
    }
    return columns.isEmpty ? r : listings.update(id, columns);
  }

  List<Listing> mine(AuthContext caller) {
    final cache = <String, UserRecord>{};
    return [for (final r in listings.byPublisher(caller.user.id)) toDto(r, publishers: cache)];
  }

  Future<ListingRecord> addScreenshot(AuthContext caller, String id, Stream<List<int>> body) async {
    final r = _findOwned(id, caller);
    if (r.screenshots.length >= maxScreenshots) throw ApiException.validation('At most $maxScreenshots screenshots.');
    final media = await auth.storeImage(body, ownerId: caller.user.id);
    return listings.update(id, {'screenshots_json': jsonEncode([...r.screenshots, media.sha256])});
  }

  ListingRecord removeScreenshot(AuthContext caller, String id, int index) {
    final r = _findOwned(id, caller);
    if (index < 0 || index >= r.screenshots.length) throw ApiException.notFound('No such screenshot.');
    return listings.update(id, {'screenshots_json': jsonEncode([...r.screenshots]..removeAt(index))});
  }

  ListingRecord ownerUnlist(AuthContext caller, String id) {
    final r = _findOwned(id, caller);
    if (r.status != ListingStatus.published) throw ApiException.conflict('Only published listings can be unlisted.');
    return listings.update(id, {'status': ListingStatus.unlisted.wire, 'unlisted_by': 'owner', 'unlisted_reason': null});
  }

  ListingRecord ownerRelist(AuthContext caller, String id) {
    final r = _findOwned(id, caller);
    if (r.status != ListingStatus.unlisted) throw ApiException.conflict('The listing is not unlisted.');
    if (r.unlistedBy == 'moderator') {
      throw ApiException.forbidden('A moderator unlisted this listing; only a moderator can restore it.');
    }
    return listings.update(id, {'status': ListingStatus.published.wire, 'unlisted_by': null, 'unlisted_reason': null});
  }

  // --- Uploads & versions ------------------------------------------------------------

  /// Stores a validated version archive. With [category] (the listing's, when
  /// the client knows it), the category's archive rules run here already —
  /// a theme is JSON, the rest zips, a game template follows the template
  /// format — with the errors [publishVersion] would give.
  Future<UploadRecord> upload(AuthContext caller, Stream<List<int>> body,
      {required String fileName, String? contentType, ListingCategory? category}) async {
    final name = fileName.split(RegExp(r'[\\/]')).last.trim();
    final lower = name.toLowerCase();
    final isJson = lower.endsWith('.json') || (contentType?.startsWith('application/json') ?? false);
    final isZip = lower.endsWith('.zip');
    if (name.isEmpty || (!isJson && !isZip)) {
      throw const ApiException(422, 'invalid_archive', 'Upload a .zip archive, or a .json file for themes.');
    }
    if (category != null && category.acceptsJson != isJson) throw _wrongArchiveKind(category);
    final template = category == ListingCategory.gameTemplate;
    final Uint8List uploaded;
    try {
      uploaded = await collectLimited(body, maxUploadBytes);
    } on BlobTooLargeException {
      throw ApiException(413, 'payload_too_large', 'Uploads are limited to ${maxUploadBytes ~/ (1024 * 1024)} MB.',
          details: {'maxBytes': maxUploadBytes});
    }
    final ValidatedArchive validated;
    try {
      validated = isJson
          ? validator.validateJson(uploaded, name)
          : validator.validate(uploaded,
              beforeContents: template ? templateValidator.validatePaths : null,
              // A plugin folder's generated build/, .dart_tool/, … are left out.
              skipGenerated: category == ListingCategory.plugin);
    } on InvalidArchiveException catch (e) {
      // The message names the offending path(s).
      throw ApiException(422, 'invalid_archive', 'The upload was refused: ${e.message}.',
          details: {'path': ?e.path, if (e.paths.isNotEmpty) 'paths': e.paths});
    }
    // What is stored: the upload, or its repack without the generated folders.
    final bytes = validated.repacked ?? uploaded;
    if (template) templateValidator.validate(bytes);
    // A plugin upload returns what its package declares.
    final plugin = category == ListingCategory.plugin ? pluginValidator.validate(bytes) : null;
    final ref = await blobs.put(Stream.value(bytes));
    final preview = isJson ? null : await _storePreview(bytes);
    final record = UploadRecord(
      id: newId(),
      userId: caller.user.id,
      blobSha256: ref.sha256,
      fileName: name,
      kind: isJson ? 'json' : 'zip',
      size: ref.size,
      files: validated.files,
      detectedKinds: validated.detectedKinds,
      createdAt: nowIso(),
      preview: preview,
      plugin: plugin,
      skipped: validated.skipped,
    );
    uploads.create(record);
    return record;
  }

  /// Derives the preview model of a zip archive and stores it.
  Future<PreviewInfo?> _storePreview(List<int> zip) async {
    final PreviewModel? model;
    try {
      model = derivePreviewModelFromZip(zip, maxBytes: maxPreviewBytes);
    } catch (_) {
      return null; // a preview is a nicety: never fail an upload over it
    }
    if (model == null) return null;
    final ref = await blobs.put(Stream.value(model.bytes));
    return PreviewInfo(sha256: ref.sha256, size: ref.size, source: model.sourcePath);
  }

  /// Derives the preview of every version published before previews existed
  /// (run once at start-up). Returns how many got one.
  Future<int> backfillPreviews() async {
    var derived = 0;
    for (final v in listings.versionsWithoutPreviewState()) {
      final listing = listings.findById(v.listingId);
      PreviewInfo? preview;
      if (listing != null && listing.category.hasModelPreview && v.archiveKind == 'zip' && await blobs.exists(v.blobSha256)) {
        preview = await _storePreview(await blobs.readAll(v.blobSha256));
      }
      listings.setVersionPreview(v.id, preview);
      if (preview != null) derived++;
    }
    return derived;
  }

  /// The preview model of a version, for the public 3D view route: the
  /// listing's visibility rules apply; 404 `no_preview` when there is none.
  VersionRecord previewOf(String idOrSlug, String version, AuthContext? viewer) {
    final listing = findVisible(idOrSlug, viewer);
    final v = listings.findVersion(listing.id, version);
    if (v == null) throw ApiException.notFound('No such version.');
    if (v.preview == null) throw const ApiException(404, 'no_preview', 'This version has no 3D preview.');
    return v;
  }

  static ApiException _wrongArchiveKind(ListingCategory category) => ApiException(422, 'invalid_archive',
      category.acceptsJson ? 'Theme versions are a single .json file.' : 'Versions are a .zip archive.');

  Future<VersionRecord> publishVersion(AuthContext caller, String id, Map<String, Object?> body, ClientInfo client) async {
    final listing = _findOwned(id, caller);
    final version = (body['version'] as String? ?? '').trim();
    if (!isSemver(version)) throw ApiException.validation('Versions look like 1.0.0.', {'field': 'version'});
    final releaseNotes = body['releaseNotes'] as String? ?? '';
    if (releaseNotes.length > 20000) throw ApiException.validation('The release notes are too long.');
    final engine = body['engineVersion'] == null ? listing.engineVersion : _engineVersion(body['engineVersion']);

    final upload = uploads.find(body['uploadId'] as String? ?? '');
    if (upload == null || upload.userId != caller.user.id) {
      throw ApiException.validation('Unknown upload; upload the archive first.', {'field': 'uploadId'});
    }
    if (upload.consumedAt != null) throw ApiException.conflict('This upload is already published as a version.');
    if (listing.category.acceptsJson != (upload.kind == 'json')) throw _wrongArchiveKind(listing.category);
    // Lumina Studio must be able to turn a game template into a
    // project, so the archive has to follow the template format.
    if (listing.category == ListingCategory.gameTemplate) templateValidator.validate(await blobs.readAll(upload.blobSha256));
    // A plugin version is its package's: the manifest version, the
    // license the package declares, the changelog's release notes.
    final plugin = listing.category == ListingCategory.plugin ? pluginValidator.validate(await blobs.readAll(upload.blobSha256)) : null;
    if (plugin != null && plugin.version != version) {
      throw ApiException(422, 'version_mismatch',
          'This package is version ${plugin.version} (${plugin.manifestFileName}); publish it as ${plugin.version}.',
          details: {'field': 'version', 'manifestVersion': plugin.version});
    }

    final selection = LicenseSelection(content: body['contentLicense'] as String?, code: body['codeLicense'] as String?);
    final required = requiredLicenseKinds(listing.category, upload.detectedKinds);
    if (plugin?.license case final declared?) {
      for (final kind in required) {
        final id = declared[kind];
        if (id != null && selection[kind] != id) {
          throw ApiException(422, 'license_mismatch',
              'The package declares the ${kind.wire} license $id (${declared.fileName}); publish it under $id.',
              details: {'kind': kind.wire, 'declared': id, 'source': declared.source.wire, 'path': declared.path});
        }
      }
    }
    final notes = releaseNotes.trim().isEmpty ? (plugin?.releaseNotes ?? releaseNotes) : releaseNotes;
    final engineVersion = body['engineVersion'] == null && plugin?.minEngineVersion != null ? plugin!.minEngineVersion! : engine;
    final problems = licenseProblems(required, selection);
    if (problems.isNotEmpty) {
      throw ApiException(422, problems.first.code, problems.map((p) => p.message).join(' '), details: {
        'problems': [for (final p in problems) p.toJson()],
        'requiredKinds': [for (final k in required) k.wire],
      });
    }

    final attestation = (body['attestation'] as Map?)?.cast<String, Object?>();
    if (attestation?['accepted'] != true) {
      throw ApiException(422, 'attestation_required',
          'Confirm "${publishingTerms.attestationStatement}" to publish.', details: {'termsVersion': publishingTerms.version});
    }
    if (attestation?['termsVersion'] != publishingTerms.version) {
      throw ApiException(422, 'attestation_required',
          'The publishing terms changed; review and accept version ${publishingTerms.version}.',
          details: {'termsVersion': publishingTerms.version});
    }

    return transaction(db, () {
      if (listings.findVersion(id, version) != null) throw ApiException.conflict('Version $version already exists.');
      final now = nowIso();
      final record = VersionRecord(
        id: newId(),
        listingId: id,
        version: version,
        releaseNotes: notes,
        engineVersion: engineVersion,
        contentLicense: selection.content,
        codeLicense: selection.code,
        uploadId: upload.id,
        blobSha256: upload.blobSha256,
        archiveKind: upload.kind,
        fileName: upload.fileName,
        size: upload.size,
        files: upload.files,
        downloadCount: 0,
        createdAt: now,
        preview: listing.category.hasModelPreview ? upload.preview : null,
        previewState: listing.category.hasModelPreview && upload.preview != null ? 'ready' : 'none',
      );
      try {
        listings.createVersion(record);
      } on SqliteException {
        throw ApiException.conflict('Version $version already exists.');
      }
      attestations.create(AttestationRecord(
        id: newId(),
        userId: caller.user.id,
        listingId: id,
        versionId: record.id,
        termsVersion: publishingTerms.version,
        statement: publishingTerms.attestationStatement,
        acceptedAt: now,
        ipHash: client.ipHash,
      ));
      uploads.markConsumed(upload.id);
      listings.update(id, {
        if (listing.status == ListingStatus.draft) 'status': ListingStatus.published.wire,
        'latest_version_id': record.id,
        'content_license': selection.content,
        'code_license': selection.code,
        'engine_version': engineVersion,
        'engine_version_code': semverCode(engineVersion),
        if (listing.publishedAt == null) 'published_at': now,
      });
      audit.append(caller.user.id, 'version.publish', 'listing', id, {'version': version, 'versionId': record.id});
      return record;
    });
  }

  // --- Search -----------------------------------------------------------------------

  /// Turns free text into an FTS5 query: every word must match, as a prefix,
  /// so user input never reaches FTS5's query syntax.
  static String? ftsQuery(String? q) {
    if (q == null) return null;
    final words = RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(q).map((m) => m[0]!.toLowerCase()).take(12).toList();
    return words.isEmpty ? null : words.map((w) => '"$w"*').join(' ');
  }

  ResultPage<Listing> search(Map<String, String> params) {
    final query = SearchQuery.fromQueryParameters(params);
    if (params['category'] != null && query.category == null) throw ApiException.validation('Unknown category.');
    if (params['licenseKind'] != null && query.licenseKind == null) throw ApiException.validation('Unknown license kind.');
    if (params['sort'] != null && query.sort == null) throw ApiException.validation('Unknown sort.');
    if (query.license != null && licenseById(query.license) == null) throw ApiException.validation('Unknown license.');
    if (query.engineVersion != null && !isSemver(query.engineVersion!)) throw ApiException.validation('Bad engine version.');
    if (query.page < 1 || query.pageSize < 1 || query.pageSize > 100) {
      throw ApiException.validation('page ≥ 1 and 1 ≤ pageSize ≤ 100.');
    }
    String? publisherId;
    if (query.publisher != null) {
      publisherId = users.findByUsername(query.publisher!)?.id;
      if (publisherId == null) return ResultPage(items: const [], total: 0, page: query.page, pageSize: query.pageSize);
    }
    final fts = ftsQuery(query.q);
    final (rows, total) = listings.search(ListingSearch(
      ftsQuery: fts,
      category: query.category,
      licenseKind: query.licenseKind,
      license: query.license,
      engineVersionCode: query.engineVersion == null ? null : semverCode(query.engineVersion!),
      free: query.free,
      publisherId: publisherId,
      featured: query.featured,
      sort: query.sort ?? (fts != null ? SearchSort.relevance : SearchSort.newest),
      offset: (query.page - 1) * query.pageSize,
      limit: query.pageSize,
    ));
    final cache = <String, UserRecord>{};
    return ResultPage(
      items: [for (final r in rows) toDto(r, publishers: cache)],
      total: total,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  PublisherProfile profile(String username) {
    final user = users.findByUsername(username);
    if (user == null || user.status == UserStatus.suspended) throw ApiException.notFound('No such publisher.');
    final cache = {user.id: user};
    return PublisherProfile(
      publisher: user.toPublisher(),
      joinedAt: DateTime.parse(user.createdAt),
      listings: [
        for (final r in listings.byPublisher(user.id, statuses: {ListingStatus.published})) toDto(r, publishers: cache),
      ],
    );
  }

  // --- Library, downloads, manifests ------------------------------------------------

  LibraryEntry getListing(AuthContext caller, String id) {
    final r = findVisible(id, caller);
    if (r.status != ListingStatus.published && !_isOwner(r, caller)) throw ApiException.notFound('No such listing.');
    if (r.latestVersionId == null) throw ApiException.conflict('This listing has no published version yet.');
    if (r.priceCents != 0) throw const ApiException(422, 'price_not_supported', 'Paid listings are not available yet.');
    final acquired = library.add(caller.user.id, r.id);
    return LibraryEntry(listing: toDto(r, inLibrary: true), acquiredAt: DateTime.parse(acquired));
  }

  List<LibraryEntry> libraryOf(AuthContext caller) {
    final cache = <String, UserRecord>{};
    return [
      for (final (listingId, acquired) in library.list(caller.user.id))
        if (listings.findById(listingId) case final r?)
          LibraryEntry(listing: toDto(r, inLibrary: true, publishers: cache), acquiredAt: DateTime.parse(acquired)),
    ];
  }

  /// The version [caller] may download: they have the listing in their
  /// library (or publish/moderate it), and a moderator has not pulled it.
  (ListingRecord, VersionRecord) _downloadable(AuthContext caller, String id, String version) {
    final r = listings.findById(id) ?? listings.findBySlug(id);
    if (r == null) throw ApiException.notFound('No such listing.');
    final privileged = _isOwner(r, caller) || caller.canModerate;
    final pulled = r.status == ListingStatus.unlisted && r.unlistedBy == 'moderator';
    if (!privileged && (pulled || r.status == ListingStatus.draft)) throw ApiException.notFound('No such listing.');
    if (!privileged && library.acquiredAt(caller.user.id, r.id) == null) {
      throw const ApiException(403, 'not_in_library', 'Get this listing first (it is free).');
    }
    final v = listings.findVersion(r.id, version);
    if (v == null) throw ApiException.notFound('No such version.');
    return (r, v);
  }

  InstallManifest manifest(AuthContext caller, String id, String version) {
    final (r, v) = _downloadable(caller, id, version);
    final publisher = users.findById(r.publisherId)!;
    final folder = installFolderName(r.title);
    final kind = r.category.installKind;
    final files = v.files;

    // Plugins and game templates are folders of their own: a single top-level
    // folder in the archive names it, otherwise the listing does.
    final stripTop =
        kind == InstallKind.plugin || kind == InstallKind.gameTemplate ? singleTopFolder(files.map((f) => f.path)) : null;
    // A plugin package without a top folder is named by its root
    // `<name>.lmplugin` (Lumina Studio loads plugins/<name>/<name>.lmplugin).
    final rootPlugin = kind == InstallKind.plugin && stripTop == null
        ? files.map((f) => f.path).where((p) => !p.contains('/') && p.endsWith(kPluginManifestExtension)).firstOrNull
        : null;
    final pluginFolder = rootPlugin?.substring(0, rootPlugin.length - kPluginManifestExtension.length);
    final targetRoot = switch (kind) {
      InstallKind.projectContents => 'contents/Marketplace/${installFolderName(publisher.username)}/$folder/',
      InstallKind.theme => 'themes/',
      InstallKind.plugin => 'plugins/${stripTop ?? pluginFolder ?? folder.toLowerCase()}/',
      InstallKind.gameTemplate => 'templates/${stripTop ?? folder}/',
    };
    String target(ValidatedFile f) => switch (kind) {
          InstallKind.theme => '$targetRoot${folder.toLowerCase()}.json',
          _ => targetRoot + (stripTop == null ? f.path : f.path.substring(stripTop.length + 1)),
        };
    final base = '/api/v1/listings/${r.id}/versions/${v.version}';
    return InstallManifest(
      formatVersion: 1,
      listingId: r.id,
      slug: r.slug,
      title: r.title,
      category: r.category,
      version: v.version,
      engineVersion: v.engineVersion,
      publisher: publisher.toPublisher(),
      installKind: kind,
      targetRoot: targetRoot,
      folderName: folder,
      archiveUrl: '$base/download',
      archiveSha256: v.blobSha256,
      archiveSize: v.size,
      licenses: [?licenseById(v.contentLicense), ?licenseById(v.codeLicense)],
      files: [
        for (final f in files)
          ManifestFile(
            path: f.path,
            size: f.size,
            sha256: f.sha256,
            target: target(f),
            url: '$base/files/${f.path.split('/').map(Uri.encodeComponent).join('/')}',
          ),
      ],
    );
  }

  /// The archive; counts a download.
  (VersionRecord, Stream<List<int>>) download(AuthContext caller, String id, String version) {
    final (r, v) = _downloadable(caller, id, version);
    listings.recordDownload(r.id, v.id);
    return (v, blobs.openRead(v.blobSha256));
  }

  /// One file of a version.
  Future<List<int>> file(AuthContext caller, String id, String version, String path) async {
    final (_, v) = _downloadable(caller, id, version);
    if (!v.files.any((f) => f.path == path)) throw ApiException.notFound('No such file in this version.');
    final bytes = await blobs.readAll(v.blobSha256);
    if (v.archiveKind == 'json') return bytes;
    final entry = extractZipEntry(bytes, path);
    if (entry == null) throw ApiException.notFound('No such file in this version.');
    return entry;
  }
}
