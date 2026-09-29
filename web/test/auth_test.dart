import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

void main() {
  late TestBackend backend;
  setUpAll(() async => backend = await TestBackend.start());
  tearDownAll(() => backend.stop());

  testWidgets('sign up, log out and log back in', (tester) async {
    final client = backend.client();
    final session = await pumpApp(tester, client);
    await tapOn(tester, find.byKey(const ValueKey('nav_signup')), until: find.byKey(const ValueKey('signup_email')));

    await tester.enterText(find.byKey(const ValueKey('signup_email')), 'ivy@example.test');
    await tester.enterText(find.byKey(const ValueKey('signup_username')), 'ivy');
    await tester.enterText(find.byKey(const ValueKey('signup_display_name')), 'Ivy Maker');
    await tester.enterText(find.byKey(const ValueKey('signup_password')), 'short');
    await tapOn(tester, find.byKey(const ValueKey('signup_submit')));
    expect(find.text('The password needs at least 10 characters.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('signup_password')), 'correct horse battery');
    await tapOn(tester, find.byKey(const ValueKey('signup_submit')), until: find.byKey(const ValueKey('nav_account')));
    expect(session.user!.username, 'ivy');
    expect(find.text('Ivy Maker'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav_library')), findsOneWidget);

    await tapOn(tester, find.byKey(const ValueKey('nav_account')), until: find.text('Log out'));
    await tapOn(tester, find.byKey(const ValueKey('menu_logout')), until: find.byKey(const ValueKey('nav_login')));
    expect(session.isSignedIn, isFalse);

    await tapOn(tester, find.byKey(const ValueKey('nav_login')), until: find.byKey(const ValueKey('login_login')));
    await tester.enterText(find.byKey(const ValueKey('login_login')), 'ivy');
    await tester.enterText(find.byKey(const ValueKey('login_password')), 'wrong password!!');
    await tapOn(tester, find.byKey(const ValueKey('login_submit')), until: find.text('Wrong email/username or password.'));
    await tester.enterText(find.byKey(const ValueKey('login_password')), 'correct horse battery');
    await tapOn(tester, find.byKey(const ValueKey('login_submit')), until: find.byKey(const ValueKey('nav_account')));
    expect(session.user!.displayName, 'Ivy Maker');
  });

  testWidgets('signed-out visits to protected pages go to log-in and come back', (tester) async {
    await pumpApp(tester, backend.client(), location: '/my/library');
    await settle(tester, until: find.byKey(const ValueKey('login_login')));
    await tester.enterText(find.byKey(const ValueKey('login_login')), 'moderator');
    await tester.enterText(find.byKey(const ValueKey('login_password')), 'seed-moderator-password');
    await tapOn(tester, find.byKey(const ValueKey('login_submit')), until: find.text('My library'));
    expect(find.byKey(const ValueKey('nav_moderation')), findsOneWidget, reason: 'moderators get the moderation page');
  });
}
