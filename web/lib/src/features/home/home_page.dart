import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/session.dart';
import '../../theme/marketplace_theme.dart';
import '../../widgets/common.dart';

/// Loads the home page rows: featured, newest, most downloaded, then the
/// newest few of every category that has listings.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel(this.client);
  final MarketplaceClient client;

  bool loading = true;
  String? error;
  List<Listing> featured = const [];
  List<Listing> newest = const [];
  List<Listing> popular = const [];
  Map<ListingCategory, List<Listing>> byCategory = const {};
  int total = 0;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        client.search(const SearchQuery(featured: true, pageSize: 8)),
        client.search(const SearchQuery(sort: SearchSort.newest, pageSize: 8)),
        client.search(const SearchQuery(sort: SearchSort.downloads, pageSize: 8)),
        for (final c in ListingCategory.values) client.search(SearchQuery(category: c, pageSize: 4)),
      ]);
      featured = results[0].items;
      newest = results[1].items;
      popular = results[2].items;
      total = results[1].total;
      byCategory = {
        for (var i = 0; i < ListingCategory.values.length; i++)
          if (results[3 + i].items.isNotEmpty) ListingCategory.values[i]: results[3 + i].items,
      };
    } catch (e) {
      error = errorText(e);
    }
    loading = false;
    notifyListeners();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeViewModel _vm = HomeViewModel(MarketplaceScope.read(context).client)..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => PageFrame(children: [
        const _Hero(),
        const SizedBox(height: 20),
        const _CategoryStrip(),
        const SizedBox(height: 28),
        if (_vm.loading)
          const LoadingView(label: 'Loading the catalogue…')
        else if (_vm.error != null)
          ErrorBanner(_vm.error!)
        else if (_vm.total == 0)
          const InfoBanner('Nothing is published yet. Be the first: use Publish in the top bar.', title: 'An empty shelf')
        else ...[
          if (_vm.featured.isNotEmpty) _Row(title: 'Featured', listings: _vm.featured, seeAll: '/search?featured=true'),
          _Row(title: 'Newest', listings: _vm.newest, seeAll: '/search?sort=newest'),
          _Row(title: 'Most downloaded', listings: _vm.popular, seeAll: '/search?sort=downloads'),
          for (final e in _vm.byCategory.entries)
            _Row(title: e.key.pluralLabel, listings: e.value, seeAll: '/search?category=${e.key.wire}'),
        ],
      ]),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        border: Border.all(color: MarketColors.border),
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x26FB7C01), MarketColors.card, Color(0x140099C8)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FREE ASSETS FOR LUMINA STUDIO', style: MarketType.panelHeading),
        const SizedBox(height: 10),
        const Text('Models, Blueprints, materials, sounds, templates, plugins and themes.').h3(),
        const SizedBox(height: 8),
        const Text('Everything here is free and openly licensed. Get it once and add it to any project from '
                'Window → Marketplace in Lumina Studio.')
            .muted(),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PrimaryButton(
            leading: const Icon(LucideIcons.layoutGrid, size: 14),
            onPressed: () => context.go('/search'),
            child: const Text('Browse everything'),
          ),
          OutlineButton(
            leading: const Icon(LucideIcons.upload, size: 14),
            onPressed: () => context.go('/publish'),
            child: const Text('Publish your work'),
          ),
        ]),
      ]),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip();

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in ListingCategory.values)
        OutlineButton(
          size: ButtonSize.small,
          leading: Icon(categoryIcon(c), size: 14, color: MarketColors.category(c.wire)),
          onPressed: () => context.go('/search?category=${c.wire}'),
          child: Text(c.pluralLabel),
        ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.listings, required this.seeAll});
  final String title;
  final List<Listing> listings;
  final String seeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelHeading(
          title,
          trailing: LinkButton(
            size: ButtonSize.small,
            onPressed: () => context.go(seeAll),
            trailing: const Icon(LucideIcons.arrowRight, size: 12),
            child: const Text('See all'),
          ),
        ),
        ListingGrid(listings: listings),
      ]),
    );
  }
}
