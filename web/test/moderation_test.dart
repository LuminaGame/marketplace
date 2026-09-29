import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

void main() {
  late TestBackend backend;
  setUpAll(() async => backend = await TestBackend.start());
  tearDownAll(() => backend.stop());

  testWidgets('a report filed from the listing page reaches the queue; a moderator unlists it and it disappears from search',
      (tester) async {
    // A publisher re-uploads the seed barrels as their own.
    final thief = backend.client();
    late Listing stolen;
    await tester.runAsync(() async {
      await signUpUser(thief, 'copycat');
      final terms = await thief.terms();
      final seedZip = await (() async {
        final admin = backend.client();
        await admin.logIn(login: 'lumina', password: 'seed-admin-password');
        final barrel = await admin.listing('barrel');
        return admin.downloadArchive(barrel.id, '1.0.0');
      })();
      stolen = await thief.createListing(const NewListing(category: ListingCategory.model, title: 'Premium Drum Pack'));
      final upload = await thief.upload(seedZip, fileName: 'drums.zip');
      await thief.publishVersion(stolen.id, NewVersion(
          version: '1.0.0', uploadId: upload.id, licenses: const LicenseSelection(content: 'CC-BY-4.0'),
          attestation: true, termsVersion: terms.version));
    });

    // A user reports it through the UI.
    final reporter = backend.client();
    await tester.runAsync(() => signUpUser(reporter, 'watchdog'));
    await pumpApp(tester, reporter, location: '/listings/premium-drum-pack');
    await settle(tester, until: find.byKey(const ValueKey('listing_report')));
    await tapOn(tester, find.byKey(const ValueKey('listing_report')), until: find.byKey(const ValueKey('report_reason')));
    await choose(tester, const ValueKey('report_reason'), const ValueKey('report_reason_stolen_content'));
    await tester.enterText(find.byKey(const ValueKey('report_details')), 'These are the Lumina sample barrels.');
    await tapOn(tester, find.byKey(const ValueKey('report_submit')), until: find.textContaining('a moderator will review'));

    // The moderator unlists it from the queue.
    final mod = backend.client();
    await tester.runAsync(() => mod.logIn(login: 'moderator', password: 'seed-moderator-password'));
    await pumpApp(tester, mod, location: '/moderation');
    await settle(tester, until: find.text('Premium Drum Pack'));
    expect(find.text("Someone else's (paid) work"), findsOneWidget);
    expect(find.textContaining('reported by @watchdog'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mod_note')), 'Copied seed content.');
    final unlist = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('report_unlist_'));
    await tapOn(tester, unlist, until: find.textContaining('was unlisted'));
    final all = await tester.runAsync(() => mod.reports(status: null));
    expect(all!.single.status, ReportStatus.actioned);
    expect(unlist, findsNothing, reason: 'the queue is empty');
    expect(find.text('No open reports'), findsOneWidget);

    await tapOn(tester, find.byKey(const ValueKey('mod_tab_audit')), until: find.text('listing.unlist'));
    expect(find.text('report.resolve'), findsOneWidget);

    // Gone from search.
    await tester.enterText(find.byKey(const ValueKey('shell_search')), 'premium drum');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, until: find.text('0 results for “premium drum”'));
    final after = await tester.runAsync(() => reporter.search(const SearchQuery(q: 'premium')));
    expect(after!.total, 0);
  });

  testWidgets('suspending a publisher from the Publishers tab unlists all their listings', (tester) async {
    final pub = backend.client();
    await tester.runAsync(() async {
      await signUpUser(pub, 'spammer');
      final terms = await pub.terms();
      for (final title in ['Spam One', 'Spam Two']) {
        final l = await pub.createListing(NewListing(category: ListingCategory.theme, title: title));
        final upload = await pub.upload('{"name": "$title", "colors": {}}'.codeUnits, fileName: 'spam.json');
        await pub.publishVersion(l.id, NewVersion(version: '1.0.0', uploadId: upload.id,
            licenses: const LicenseSelection(content: 'CC0-1.0'), attestation: true, termsVersion: terms.version));
      }
    });
    final mod = backend.client();
    await tester.runAsync(() => mod.logIn(login: 'moderator', password: 'seed-moderator-password'));
    await pumpApp(tester, mod, location: '/moderation');
    await tapOn(tester, find.byKey(const ValueKey('mod_tab_users')), until: find.byKey(const ValueKey('mod_username')));
    await tester.enterText(find.byKey(const ValueKey('mod_username')), 'spammer');
    await tester.enterText(find.byKey(const ValueKey('mod_reason')), 'Spam listings.');
    await tapOn(tester, find.byKey(const ValueKey('mod_suspend')), until: find.textContaining('@spammer is suspended'));
    final left = await tester.runAsync(() => mod.search(const SearchQuery(q: 'spam')));
    expect(left!.total, 0);
  });
}
