import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

void main() {
  group('license catalogue', () {
    test('is free-only and split into content and code', () {
      expect(licensesOfKind(LicenseKind.content).map((l) => l.id), ['CC0-1.0', 'CC-BY-4.0', 'CC-BY-SA-4.0']);
      expect(licensesOfKind(LicenseKind.code).map((l) => l.id),
          ['MIT', 'Apache-2.0', 'BSD-2-Clause', 'BSD-3-Clause', 'MPL-2.0', 'Zlib']);
      expect(licenseById('Proprietary'), isNull);
      expect(licenseById('CC-BY-NC-4.0'), isNull);
      for (final l in licenseCatalogue) {
        expect(Uri.parse(l.url).isScheme('https'), isTrue, reason: l.id);
      }
    });

    test('licenseProblems enforces one license per required kind', () {
      final content = {LicenseKind.content};
      expect(licenseProblems(content, const LicenseSelection(content: 'CC0-1.0')), isEmpty);
      expect(licenseProblems(content, const LicenseSelection()).single.code, 'license_required');
      expect(licenseProblems(content, const LicenseSelection(content: 'Proprietary')).single.code, 'license_unknown');
      expect(licenseProblems(content, const LicenseSelection(content: 'MIT')).single.code, 'license_wrong_kind');

      final plugin = requiredLicenseKinds(ListingCategory.plugin, const []);
      final onlyContent = licenseProblems(plugin, const LicenseSelection(content: 'CC0-1.0'));
      expect(onlyContent.single.code, 'license_required');
      expect(onlyContent.single.kind, LicenseKind.code);

      final mixed = requiredLicenseKinds(ListingCategory.model, const [LicenseKind.code]);
      expect(mixed, {LicenseKind.content, LicenseKind.code});
      expect(licenseProblems(mixed, const LicenseSelection(content: 'CC-BY-4.0', code: 'MIT')), isEmpty);
    });
  });

  test('categories round-trip through their wire names', () {
    for (final c in ListingCategory.values) {
      expect(ListingCategory.tryParse(c.wire), c);
    }
    expect(ListingCategory.gameTemplate.wire, 'game_template');
    expect(ListingCategory.model.installKind, InstallKind.projectContents);
    expect(ListingCategory.plugin.installKind, InstallKind.plugin);
  });

  test('install paths', () {
    expect(installFolderName('Lumina Samples'), 'Lumina_Samples');
    expect(installFolderName('Barrel'), 'Barrel');
    expect(installFolderName('../..'), 'Listing');
    expect(isSafeRelativePath('meshes/barrel.glb'), isTrue);
    for (final bad in ['../evil', 'a/../../b', '/etc/passwd', r'C:\x', 'a\\b', 'a//b', './a', '']) {
      expect(isSafeRelativePath(bad), isFalse, reason: bad);
    }
  });

  test('SearchQuery round-trips through query parameters', () {
    const q = SearchQuery(
      q: 'barrel',
      category: ListingCategory.model,
      licenseKind: LicenseKind.content,
      license: 'CC0-1.0',
      engineVersion: '0.0.1',
      free: true,
      publisher: 'lumina',
      sort: SearchSort.downloads,
      page: 2,
      pageSize: 5,
    );
    final back = SearchQuery.fromQueryParameters(q.toQueryParameters());
    expect(back.toQueryParameters(), q.toQueryParameters());
    expect(const SearchQuery().toQueryParameters(), isEmpty);
  });

  test('Listing and InstallManifest round-trip through JSON', () {
    final now = DateTime.utc(2026, 9, 27, 12);
    const publisher = PublisherSummary(id: 'u1', username: 'lumina', displayName: 'Lumina Samples');
    final version = ListingVersion(
      id: 'v1',
      version: '1.0.0',
      releaseNotes: 'First',
      engineVersion: '0.0.1',
      licenses: const LicenseSelection(content: 'CC0-1.0'),
      archiveKind: 'zip',
      fileName: 'barrel.zip',
      size: 10,
      sha256: 'ab',
      fileCount: 1,
      downloadCount: 3,
      createdAt: now,
    );
    final listing = Listing(
      id: 'l1',
      slug: 'barrel',
      title: 'Barrel',
      description: '# Barrel',
      category: ListingCategory.model,
      tags: const ['barrel'],
      engineVersion: '0.0.1',
      priceCents: 0,
      currency: 'USD',
      status: ListingStatus.published,
      featured: true,
      publisher: publisher,
      screenshots: const ['/api/v1/media/ab'],
      downloadCount: 3,
      licenses: const LicenseSelection(content: 'CC0-1.0'),
      createdAt: now,
      updatedAt: now,
      publishedAt: now,
      latestVersion: version,
      versions: [version],
      inLibrary: true,
    );
    expect(Listing.fromJson(listing.toJson()).toJson(), listing.toJson());

    final manifest = InstallManifest(
      formatVersion: 1,
      listingId: 'l1',
      slug: 'barrel',
      title: 'Barrel',
      category: ListingCategory.model,
      version: '1.0.0',
      engineVersion: '0.0.1',
      publisher: publisher,
      installKind: InstallKind.projectContents,
      targetRoot: 'contents/Marketplace/lumina/Barrel/',
      folderName: 'Barrel',
      archiveUrl: '/api/v1/listings/l1/versions/1.0.0/download',
      archiveSha256: 'ab',
      archiveSize: 10,
      licenses: [licenseById('CC0-1.0')!],
      files: const [
        ManifestFile(
            path: 'a.glb', size: 1, sha256: 'cd', target: 'contents/Marketplace/lumina/Barrel/a.glb', url: '/x'),
      ],
    );
    expect(InstallManifest.fromJson(manifest.toJson()).toJson(), manifest.toJson());
  });

  test('MarketplaceException parses the API error envelope', () {
    final e = MarketplaceException.fromJson(422, {
      'error': {'code': 'license_required', 'message': 'A code license is required', 'details': {'kind': 'code'}},
    });
    expect(e.code, 'license_required');
    expect(e.details['kind'], 'code');
  });
}
