import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  late TestServer server;
  late MarketplaceClient anon;
  late SeedResult seeded;

  setUpAll(() async {
    server = await TestServer.start();
    seeded = await server.seed();
    anon = server.client();
  });

  test('the seed publishes real CC0 listings made from test-assets', () async {
    final all = await anon.search(const SearchQuery(pageSize: 100));
    expect(all.total, seeded.listings.length);
    expect(all.items.map((l) => l.title), containsAll(['Barrel', 'Access Cards', 'AC Units', 'Banana Bunch', 'Jerry Can']));
    for (final l in all.items) {
      expect(l.status, ListingStatus.published);
      expect(l.isFree, isTrue);
      expect(l.licenses.content, 'CC0-1.0');
      expect(l.publisher.username, 'lumina');
    }
    final barrel = all.items.firstWhere((l) => l.title == 'Barrel');
    expect(barrel.latestVersion!.fileCount, 8, reason: 'every mesh in test-assets/Props/Barrels');
    expect(barrel.screenshots, isNotEmpty);
  });

  test('search "barrel" with category model and license kind content returns the seeded barrel listing first', () async {
    final page = await anon.search(const SearchQuery(q: 'barrel', category: ListingCategory.model, licenseKind: LicenseKind.content));
    expect(page.items.first.title, 'Barrel');
    expect(page.total, greaterThanOrEqualTo(2), reason: 'Jerry Can mentions barrels in its description');
    expect(page.items.map((l) => l.category).toSet(), {ListingCategory.model});

    expect((await anon.search(const SearchQuery(q: 'barrels'))).items.first.title, 'Barrel', reason: 'stemming');
    expect((await anon.search(const SearchQuery(q: 'barr'))).items.first.title, 'Barrel', reason: 'prefix match');
    expect((await anon.search(const SearchQuery(q: 'banana'))).items.single.title, 'Banana Bunch');
    expect((await anon.search(const SearchQuery(q: 'keycard'))).items.single.title, 'Access Cards', reason: 'tags are searched');
    expect((await anon.search(const SearchQuery(q: 'barrel', licenseKind: LicenseKind.code))).items, isEmpty);
    expect((await anon.search(const SearchQuery(q: '"unbalanced'))).items, isEmpty, reason: 'FTS syntax is escaped, not a 500');
  });

  test('filters: category, license, engine version, free/paid, publisher, featured', () async {
    expect((await anon.search(const SearchQuery(category: ListingCategory.theme))).items.map((l) => l.title), ['Lumina Ember']);
    expect((await anon.search(const SearchQuery(license: 'CC0-1.0', pageSize: 100))).total, seeded.listings.length);
    expect((await anon.search(const SearchQuery(license: 'MIT'))).total, 0);
    expect((await anon.search(const SearchQuery(engineVersion: '0.0.1', pageSize: 100))).total, seeded.listings.length);
    expect((await anon.search(const SearchQuery(engineVersion: '0.0.0'))).total, 0, reason: 'needs engine ≥ 0.0.1');
    expect((await anon.search(const SearchQuery(free: true, pageSize: 100))).total, seeded.listings.length);
    expect((await anon.search(const SearchQuery(free: false))).total, 0);
    expect((await anon.search(const SearchQuery(publisher: 'lumina', pageSize: 100))).total, seeded.listings.length);
    expect((await anon.search(const SearchQuery(publisher: 'nobody'))).total, 0);
    expect((await anon.search(const SearchQuery(featured: true))).items.map((l) => l.title), contains('Barrel'));
  });

  test('pagination and sort by downloads work', () async {
    final total = (await anon.search(const SearchQuery())).total;
    final seen = <String>{};
    final pages = (total + 1) ~/ 2;
    for (var p = 1; p <= pages; p++) {
      final page = await anon.search(SearchQuery(sort: SearchSort.name, page: p, pageSize: 2));
      expect(page.page, p);
      expect(page.total, total);
      expect(page.items.length, p < pages ? 2 : total - 2 * (pages - 1));
      seen.addAll(page.items.map((l) => l.id));
    }
    expect(seen, hasLength(total), reason: 'pages do not overlap');

    final byName = await anon.search(const SearchQuery(sort: SearchSort.name, pageSize: 100));
    final names = byName.items.map((l) => l.title.toLowerCase()).toList();
    expect(names, [...names]..sort());

    // Download Banana Bunch three times and Chair once.
    final downloader = server.client();
    await signUp(downloader);
    final banana = byName.items.firstWhere((l) => l.title == 'Banana Bunch');
    final chair = byName.items.firstWhere((l) => l.title == 'Chair');
    await downloader.getListing(banana.id);
    await downloader.getListing(chair.id);
    for (var i = 0; i < 3; i++) {
      await downloader.downloadArchive(banana.id, '1.0.0');
    }
    await downloader.downloadArchive(chair.id, '1.0.0');
    final byDownloads = await anon.search(const SearchQuery(sort: SearchSort.downloads, pageSize: 2));
    expect(byDownloads.items.map((l) => l.title), ['Banana Bunch', 'Chair']);
    expect(byDownloads.items.first.downloadCount, 3);
    final detail = await anon.listing(banana.slug);
    expect(detail.versions!.single.downloadCount, 3);

    final newest = await anon.search(const SearchQuery(sort: SearchSort.newest, pageSize: 100));
    final dates = newest.items.map((l) => l.publishedAt!).toList();
    for (var i = 1; i < dates.length; i++) {
      expect(dates[i].isAfter(dates[i - 1]), isFalse);
    }
  });

  test('listing detail by slug, license catalogue, terms and categories are served', () async {
    final barrel = await anon.listing('barrel');
    expect(barrel.title, 'Barrel');
    expect(barrel.versions, hasLength(1));
    expect(barrel.description, contains('#'), reason: 'Markdown description');
    expect(barrel.inLibrary, isNull, reason: 'anonymous');

    final licenses = await anon.licenses();
    expect(licenses.map((l) => l.id), licenseCatalogue.map((l) => l.id));
    expect(licenses.first.url, startsWith('https://creativecommons.org/'));

    final terms = await anon.terms();
    expect(terms.attestationStatement, contains('I own this work or have the right to publish it'));
    expect(terms.penalty, contains('all'));
    expect(terms.penalty.toLowerCase(), contains('suspend'));
  });
}
