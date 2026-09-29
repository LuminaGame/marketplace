import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

void main() {
  late TestBackend backend;
  setUpAll(() async => backend = await TestBackend.start());
  tearDownAll(() => backend.stop());

  testWidgets('the listing page renders the Markdown description, versions and licenses; '
      '"Get (Free)" adds it to My library and the button becomes "In your library"', (tester) async {
    final client = backend.client();
    await tester.runAsync(() => signUpUser(client, 'collector'));
    await pumpApp(tester, client, location: '/listings/barrel');
    await settle(tester, until: find.byKey(const ValueKey('listing_title')));

    expect(find.text('Barrel'), findsWidgets);
    expect(find.textContaining('Eight steel drums'), findsOneWidget, reason: 'Markdown paragraph');
    expect(find.text('by Lumina Samples (@lumina)'), findsOneWidget);
    await tapOn(tester, find.text('Versions (1)'));
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('First release.'), findsOneWidget);
    await tapOn(tester, find.text('Licenses'));
    expect(find.text('Creative Commons Zero v1.0 Universal'), findsOneWidget);
    expect(find.text('Read the license text'), findsOneWidget);

    await tapOn(tester, find.byKey(const ValueKey('listing_get')), until: find.byKey(const ValueKey('listing_in_library')));
    expect(find.text('In your library'), findsOneWidget);
    expect(find.byKey(const ValueKey('listing_get')), findsNothing);
    expect(find.byKey(const ValueKey('listing_download')), findsOneWidget);

    await tapOn(tester, find.byKey(const ValueKey('nav_library')), until: find.byKey(const ValueKey('library_barrel')));
    expect(find.text('Barrel'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('library_download_barrel')), until: find.textContaining('Downloaded Barrel.zip'));
    final library = await tester.runAsync(() => client.library());
    expect(library!.single.listing.slug, 'barrel');
    expect(library.single.listing.downloadCount, 1);
  });

  testWidgets('signed-out visitors are sent to log in by "Get"', (tester) async {
    await pumpApp(tester, backend.client(), location: '/listings/chair');
    await settle(tester, until: find.text('Log in to get it (Free)'));
    await tapOn(tester, find.byKey(const ValueKey('listing_get')), until: find.byKey(const ValueKey('login_login')));
  });
}
