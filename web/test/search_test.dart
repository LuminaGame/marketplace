import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

void main() {
  late TestBackend backend;
  setUpAll(() async => backend = await TestBackend.start());
  tearDownAll(() => backend.stop());

  testWidgets('searching "barrel" with Category = Model shows the seeded barrel listing; '
      'Most downloaded reorders; pagination loads page 2', (tester) async {
    final client = backend.client();
    // Make Jerry Can the most downloaded barrel-ish listing (real downloads).
    await tester.runAsync(() async {
      final downloader = backend.client();
      await signUpUser(downloader);
      final jerry = await downloader.listing('jerry-can');
      await downloader.getListing(jerry.id);
      await downloader.downloadArchive(jerry.id, '1.0.0');
      await downloader.downloadArchive(jerry.id, '1.0.0');
    });
    await pumpApp(tester, client, searchPageSize: 3);
    expect(find.byKey(const ValueKey('listing_card_barrel')), findsWidgets, reason: 'the home page shows the seed');

    await tester.enterText(find.byKey(const ValueKey('shell_search')), 'barrel');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, until: find.byKey(const ValueKey('search_count')));
    expect(find.text('2 results for “barrel”'), findsOneWidget);

    await choose(tester, const ValueKey('filter_category'), const ValueKey('category_option_model'));
    await settle(tester, until: find.text('2 results for “barrel”'));
    final barrel = find.byKey(const ValueKey('listing_card_barrel'));
    final jerry = find.byKey(const ValueKey('listing_card_jerry-can'));
    expect(barrel, findsOneWidget);
    expect(tester.getTopLeft(barrel).dx, lessThan(tester.getTopLeft(jerry).dx), reason: 'relevance: the title match first');

    await choose(tester, const ValueKey('search_sort'), const ValueKey('sort_option_downloads'));
    await settle(tester, until: find.text('Sort: Most downloaded'));
    expect(tester.getTopLeft(find.byKey(const ValueKey('listing_card_jerry-can'))).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('listing_card_barrel'))).dx),
        reason: 'Jerry Can has more downloads');

    // Pagination over the whole catalogue (7 listings, 3 per page).
    await tapOn(tester, find.byKey(const ValueKey('filter_clear')), until: find.text('Sort: Relevance'));
    await tester.enterText(find.byKey(const ValueKey('shell_search')), '');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, until: find.text('Page 1 of 3'));
    expect(find.text('7 results'), findsOneWidget);
    final firstPage = find.byType(Clickable).evaluate().length;
    await tapOn(tester, find.byKey(const ValueKey('search_next')), until: find.text('Page 2 of 3'));
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.byType(Clickable).evaluate().length, firstPage);
    await tapOn(tester, find.byKey(const ValueKey('search_next')), until: find.text('Page 3 of 3'));
    expect(find.byKey(const ValueKey('search_next')), findsOneWidget);
  });

  testWidgets('license filters narrow the results', (tester) async {
    await pumpApp(tester, backend.client(), location: '/search?licenseKind=code');
    await settle(tester, until: find.text('0 results'));
    await pumpApp(tester, backend.client(), location: '/search?category=theme');
    await settle(tester, until: find.byKey(const ValueKey('listing_card_lumina-ember')));
    expect(find.text('1 result'), findsOneWidget);
    await pumpApp(tester, backend.client(), location: '/search?license=CC0-1.0&engineVersion=0.0.1');
    await settle(tester, until: find.text('7 results'));
    expect(SearchQuery.fromQueryParameters(const {'license': 'CC0-1.0'}).license, 'CC0-1.0');
  });
}
