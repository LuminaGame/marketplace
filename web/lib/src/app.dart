import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'data/session.dart';
import 'features/auth/auth_pages.dart';
import 'features/home/home_page.dart';
import 'features/library/library_page.dart';
import 'features/listing/listing_page.dart';
import 'features/moderation/moderation_page.dart';
import 'features/my_listings/my_listings_page.dart';
import 'features/publish/publish_page.dart';
import 'features/search/search_page.dart';
import 'features/shell/app_shell.dart';
import 'platform/files.dart';
import 'theme/marketplace_theme.dart';

/// Pages that need a signed-in user; visiting one signed out goes to log-in
/// and comes back after.
const _protected = ['/publish', '/my/', '/profile', '/moderation'];

GoRouter buildRouter(MarketplaceSession session, {String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      refreshListenable: session,
      redirect: (context, state) {
        final path = state.uri.path;
        final needsAuth = _protected.any((p) => path == p || path.startsWith(p.endsWith('/') ? p : '$p/'));
        if (needsAuth && !session.isSignedIn) {
          return Uri(path: '/login', queryParameters: {'next': state.uri.toString()}).toString();
        }
        if (path.startsWith('/moderation') && session.isSignedIn && !session.canModerate) return '/';
        if ((path == '/login' || path == '/signup') && session.isSignedIn) {
          return state.uri.queryParameters['next'] ?? '/';
        }
        return null;
      },
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.uri, child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomePage()),
            GoRoute(
              path: '/search',
              builder: (context, state) =>
                  SearchPage(key: ValueKey(state.uri.query), query: SearchQuery.fromQueryParameters(state.uri.queryParameters)),
            ),
            GoRoute(
              path: '/listings/:slug',
              builder: (context, state) => ListingPage(key: ValueKey(state.pathParameters['slug']), slug: state.pathParameters['slug']!),
            ),
            GoRoute(path: '/login', builder: (context, state) => LoginPage(next: state.uri.queryParameters['next'])),
            GoRoute(path: '/signup', builder: (context, state) => SignUpPage(next: state.uri.queryParameters['next'])),
            GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
            GoRoute(path: '/publish', builder: (context, state) => const PublishPage(key: ValueKey('publish_new'))),
            GoRoute(
              path: '/publish/:id',
              builder: (context, state) => PublishPage(key: ValueKey('publish_${state.pathParameters['id']}'), listingId: state.pathParameters['id']),
            ),
            GoRoute(path: '/my/listings', builder: (context, state) => const MyListingsPage()),
            GoRoute(path: '/my/library', builder: (context, state) => const LibraryPage()),
            GoRoute(path: '/moderation', builder: (context, state) => const ModerationPage()),
          ],
        ),
      ],
    );

/// The marketplace app: [ShadcnApp.router] on the editor's dark theme.
class MarketplaceApp extends StatefulWidget {
  const MarketplaceApp({
    super.key,
    required this.session,
    this.fileSource,
    this.fileSaver,
    this.searchPageSize = 24,
    this.initialLocation = '/',
    this.platform,
  });

  final MarketplaceSession session;
  final FileSource? fileSource;
  final FileSaver? fileSaver;
  final int searchPageSize;
  final String initialLocation;

  /// Overrides the host platform for layout decisions (tests).
  final TargetPlatform? platform;

  @override
  State<MarketplaceApp> createState() => _MarketplaceAppState();
}

class _MarketplaceAppState extends State<MarketplaceApp> {
  late final GoRouter _router = buildRouter(widget.session, initialLocation: widget.initialLocation);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MarketplaceScope(
      session: widget.session,
      fileSource: widget.fileSource ?? platformFileSource(),
      fileSaver: widget.fileSaver ?? platformFileSaver(),
      searchPageSize: widget.searchPageSize,
      child: ShadcnApp.router(
        title: 'Lumina Marketplace',
        theme: marketplaceTheme(platform: widget.platform),
        routerConfig: _router,
      ),
    );
  }
}
