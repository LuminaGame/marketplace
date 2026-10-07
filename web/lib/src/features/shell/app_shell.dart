import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/theme/marketplace_theme.dart';

/// The frame around every page: the top bar (logo, search, navigation,
/// account) over the routed page.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The routed page is laid out below the top bar but painted *before* it:
    // the nested navigator's routes block the semantics of everything painted
    // earlier, and the top bar must stay in the accessibility tree. The sort
    // keys keep the reading order top bar → page.
    return ColoredBox(
      color: MarketColors.background,
      child: Column(
        verticalDirection: VerticalDirection.up,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: Semantics(sortKey: const OrdinalSortKey(1), child: child)),
          Semantics(sortKey: const OrdinalSortKey(0), explicitChildNodes: true, child: _TopBar(location: location)),
        ],
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  const _TopBar({required this.location});
  final Uri location;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = widget.location.path == '/search' ? widget.location.queryParameters['q'] ?? '' : '';
  }

  @override
  void didUpdateWidget(_TopBar old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location && widget.location.path == '/search') {
      _search.text = widget.location.queryParameters['q'] ?? '';
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit(String q) {
    final text = q.trim();
    context.go(Uri(path: '/search', queryParameters: {if (text.isNotEmpty) 'q': text}).toString());
  }

  @override
  Widget build(BuildContext context) {
    final scope = MarketplaceScope.of(context);
    final session = scope.session;
    final path = widget.location.path;
    Widget nav(String label, String route, IconData icon, {Key? key, required bool iconOnly}) {
      final active = path == route || (route != '/' && path.startsWith(route));
      final button = GhostButton(
        key: key,
        size: ButtonSize.small,
        density: iconOnly ? ButtonDensity.icon : ButtonDensity.normal,
        leading: iconOnly ? null : Icon(icon, size: 14, color: active ? MarketColors.primary : null),
        onPressed: () => context.go(route),
        child: iconOnly
            ? Semantics(
                label: label,
                child: Icon(icon, size: 16, color: active ? MarketColors.primary : null),
              )
            : Text(
                label,
                style: TextStyle(color: active ? MarketColors.accentForeground : MarketColors.secondaryForeground),
              ),
      );
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: iconOnly
            ? Tooltip(
                tooltip: (context) => TooltipContainer(child: Text(label)),
                child: button,
              )
            : button,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;
        final iconOnly = constraints.maxWidth < (session.canModerate ? 1500 : 1320);
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: MarketColors.cardHeader,
            border: Border(bottom: BorderSide(color: MarketColors.border)),
          ),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Lumina Marketplace home',
                child: Clickable(
                  key: const ValueKey('nav_home'),
                  mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
                  onPressed: () => context.go('/'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/lumina_logo.png', height: 24, semanticLabel: 'Lumina'),
                      const SizedBox(width: 10),
                      if (!compact) ...[
                        const Text(
                          'LUMINA',
                          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'MARKETPLACE',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2,
                            fontSize: 13,
                            color: MarketColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360, minWidth: 160),
                  child: Semantics(
                    label: 'Search the marketplace',
                    textField: true,
                    child: TextField(
                      key: const ValueKey('shell_search'),
                      controller: _search,
                      placeholder: const Text('Search models, themes, plugins…'),
                      features: const [InputFeature.leading(Icon(LucideIcons.search, size: 14))],
                      onSubmitted: _submit,
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              nav('Browse', '/search', LucideIcons.layoutGrid, key: const ValueKey('nav_browse'), iconOnly: iconOnly),
              nav('Publish', '/publish', LucideIcons.upload, key: const ValueKey('nav_publish'), iconOnly: iconOnly),
              if (session.isSignedIn) ...[
                nav(
                  'My listings',
                  '/my/listings',
                  LucideIcons.store,
                  key: const ValueKey('nav_my_listings'),
                  iconOnly: iconOnly,
                ),
                nav(
                  'Library',
                  '/my/library',
                  LucideIcons.library,
                  key: const ValueKey('nav_library'),
                  iconOnly: iconOnly,
                ),
              ],
              if (session.canModerate)
                nav(
                  'Moderation',
                  '/moderation',
                  LucideIcons.shieldCheck,
                  key: const ValueKey('nav_moderation'),
                  iconOnly: iconOnly,
                ),
              const Spacer(),
              if (session.isSignedIn)
                _AccountButton(name: session.user!.displayName, username: session.user!.username)
              else ...[
                GhostButton(
                  key: const ValueKey('nav_login'),
                  size: ButtonSize.small,
                  onPressed: () => context.go(
                    Uri(
                      path: '/login',
                      queryParameters: {if (path != '/login' && path != '/signup') 'next': widget.location.toString()},
                    ).toString(),
                  ),
                  child: const Text('Log in'),
                ),
                const SizedBox(width: 6),
                PrimaryButton(
                  key: const ValueKey('nav_signup'),
                  size: ButtonSize.small,
                  onPressed: () => context.go('/signup'),
                  child: const Text('Sign up'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.name, required this.username});
  final String name;
  final String username;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return GhostButton(
      key: const ValueKey('nav_account'),
      size: ButtonSize.small,
      leading: Avatar(initials: initials, size: 22, backgroundColor: MarketColors.selectionBg),
      trailing: const Icon(LucideIcons.chevronDown, size: 14),
      onPressed: () {
        showDropdown(
          context: context,
          builder: (context) => DropdownMenu(
            children: [
              MenuLabel(child: Text('@$username')),
              MenuButton(
                key: const ValueKey('menu_profile'),
                leading: const Icon(LucideIcons.user),
                onPressed: (context) => context.go('/profile'),
                child: const Text('Profile'),
              ),
              MenuButton(
                leading: const Icon(LucideIcons.store),
                onPressed: (context) => context.go('/my/listings'),
                child: const Text('My listings'),
              ),
              MenuButton(
                leading: const Icon(LucideIcons.library),
                onPressed: (context) => context.go('/my/library'),
                child: const Text('My library'),
              ),
              const MenuDivider(),
              MenuButton(
                key: const ValueKey('menu_logout'),
                leading: const Icon(LucideIcons.logOut),
                onPressed: (context) async {
                  final scope = MarketplaceScope.read(context);
                  final router = GoRouter.of(context);
                  await scope.session.logOut();
                  router.go('/');
                },
                child: const Text('Log out'),
              ),
            ],
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(name, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
