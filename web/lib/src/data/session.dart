import 'dart:async';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/platform/files.dart';

/// The signed-in state of the app, over [MarketplaceClient]'s session. The
/// access token lives in the client's memory only; in the browser the refresh
/// token lives only in the backend's httpOnly cookie, so a reload restores the
/// session through [restore].
class MarketplaceSession extends ChangeNotifier {
  MarketplaceSession(this.client) {
    _sub = client.sessionChanges.listen((_) => notifyListeners());
  }

  final MarketplaceClient client;
  late final StreamSubscription<MarketplaceUser?> _sub;

  MarketplaceUser? get user => client.currentUser;
  bool get isSignedIn => client.isSignedIn && user != null;
  bool get canModerate => user?.role.canModerate ?? false;

  /// Restores a session from the refresh cookie (web) or a persisted token.
  Future<void> restore({String? refreshToken}) async {
    await client.restoreSession(refreshToken: refreshToken);
    notifyListeners();
  }

  Future<void> logIn(String login, String password) => client.logIn(login: login, password: password);

  Future<void> signUp({required String email, required String username, required String password, String? displayName}) =>
      client.signUp(email: email, username: username, password: password, displayName: displayName);

  Future<void> logOut() => client.logOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// App-wide dependencies, above the router.
class MarketplaceScope extends InheritedNotifier<MarketplaceSession> {
  const MarketplaceScope({
    super.key,
    required MarketplaceSession session,
    required this.fileSource,
    required this.fileSaver,
    this.searchPageSize = 24,
    required super.child,
  }) : super(notifier: session);

  final FileSource fileSource;
  final FileSaver fileSaver;

  /// Results per search page (tests use a small one to exercise pagination).
  final int searchPageSize;

  MarketplaceSession get session => notifier!;
  MarketplaceClient get client => notifier!.client;

  static MarketplaceScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarketplaceScope>()!;

  /// Without subscribing to session changes.
  static MarketplaceScope read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MarketplaceScope>()!;
}

/// Human-readable text for an API error.
String errorText(Object error) => switch (error) {
      MarketplaceException e => e.message,
      _ => 'Could not reach the marketplace ($error).',
    };
