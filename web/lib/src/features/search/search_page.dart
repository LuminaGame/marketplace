import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/session.dart';
import '../../theme/marketplace_theme.dart';
import '../../widgets/common.dart';

/// Runs one search. The query lives in the URL (`/search?q=…&category=…`), so
/// every filter change is a navigation and the browser's back button works.
class SearchViewModel extends ChangeNotifier {
  SearchViewModel(this.client, this.query);
  final MarketplaceClient client;
  final SearchQuery query;

  bool loading = true;
  String? error;
  ResultPage<Listing>? results;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      results = await client.search(query);
    } catch (e) {
      error = errorText(e);
    }
    loading = false;
    notifyListeners();
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.query});
  final SearchQuery query;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final SearchViewModel _vm;
  late final TextEditingController _engine = TextEditingController(text: widget.query.engineVersion ?? '');

  @override
  void initState() {
    super.initState();
    final pageSize = MarketplaceScope.read(context).searchPageSize;
    _vm = SearchViewModel(MarketplaceScope.read(context).client, widget.query.copyWith(pageSize: pageSize))..load();
  }

  @override
  void dispose() {
    _vm.dispose();
    _engine.dispose();
    super.dispose();
  }

  /// Navigates to [q] (page reset to 1 unless given).
  void _go(SearchQuery q) {
    final params = q.copyWith(pageSize: 24).toQueryParameters();
    context.go(Uri(path: '/search', queryParameters: params.isEmpty ? null : params).toString());
  }

  SearchQuery get _q => _vm.query;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 900;
      final filters = _Filters(
        query: _q,
        engine: _engine,
        onChanged: (q) => _go(q.copyWith(page: 1)),
      );
      final results = ListenableBuilder(listenable: _vm, builder: (context, _) => _results());
      return PageFrame(children: [
        if (narrow) ...[filters, const SizedBox(height: 16), results]
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 250, child: filters),
            const SizedBox(width: 24),
            Expanded(child: results),
          ]),
      ]);
    });
  }

  Widget _results() {
    if (_vm.loading) return const LoadingView(label: 'Searching…');
    if (_vm.error != null) return ErrorBanner(_vm.error!);
    final r = _vm.results!;
    final what = _q.q == null || _q.q!.isEmpty ? '' : ' for “${_q.q}”';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text('${r.total} ${r.total == 1 ? 'result' : 'results'}$what', key: const ValueKey('search_count')).large().semiBold(),
          ),
        ),
        _SortSelect(query: _q, onChanged: (s) => _go(_q.copyWith(sort: s, page: 1))),
      ]),
      const SizedBox(height: 16),
      if (r.items.isEmpty)
        const InfoBanner('Nothing matches. Try fewer words or clear a filter.', title: 'No results', icon: LucideIcons.searchX)
      else
        ListingGrid(listings: r.items, minTileWidth: 230),
      const SizedBox(height: 20),
      if (r.pageCount > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlineButton(
            key: const ValueKey('search_prev'),
            size: ButtonSize.small,
            enabled: r.hasPrevious,
            onPressed: r.hasPrevious ? () => _go(_q.copyWith(page: r.page - 1)) : null,
            leading: const Icon(LucideIcons.chevronLeft, size: 14),
            child: const Text('Previous'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Page ${r.page} of ${r.pageCount}', key: const ValueKey('search_page')).small().muted(),
          ),
          OutlineButton(
            key: const ValueKey('search_next'),
            size: ButtonSize.small,
            enabled: r.hasNext,
            onPressed: r.hasNext ? () => _go(_q.copyWith(page: r.page + 1)) : null,
            trailing: const Icon(LucideIcons.chevronRight, size: 14),
            child: const Text('Next'),
          ),
        ]),
    ]);
  }
}

class _SortSelect extends StatelessWidget {
  const _SortSelect({required this.query, required this.onChanged});
  final SearchQuery query;
  final ValueChanged<SearchSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasText = query.q != null && query.q!.isNotEmpty;
    final current = query.sort ?? (hasText ? SearchSort.relevance : SearchSort.newest);
    final options = [if (hasText) SearchSort.relevance, SearchSort.newest, SearchSort.downloads, SearchSort.name];
    return SizedBox(
      width: 200,
      child: Semantics(
        label: 'Sort by',
        child: Select<SearchSort>(
          key: const ValueKey('search_sort'),
          value: current,
          onChanged: (s) {
            if (s != null) onChanged(s);
          },
          itemBuilder: (context, s) => Text('Sort: ${s.label}'),
          popup: SelectPopup(
            items: SelectItemList(children: [
              for (final s in options) SelectItemButton(key: ValueKey('sort_option_${s.wire}'), value: s, child: Text(s.label)),
            ]),
          ).call,
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.query, required this.engine, required this.onChanged});
  final SearchQuery query;
  final TextEditingController engine;
  final ValueChanged<SearchQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final kind = query.licenseKind;
    final licenses = kind == null ? licenseCatalogue : licensesOfKind(kind);
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t).small().semiBold());
    return Panel(
      title: 'Filters',
      trailing: LinkButton(
        key: const ValueKey('filter_clear'),
        size: ButtonSize.small,
        onPressed: () => onChanged(SearchQuery(q: query.q)),
        child: const Text('Clear'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label('Category'),
        Select<ListingCategory?>(
          key: const ValueKey('filter_category'),
          value: query.category,
          placeholder: const Text('All categories'),
          onChanged: (c) => onChanged(c == null ? query.copyWith(clearCategory: true) : query.copyWith(category: c)),
          itemBuilder: (context, c) => Text(c?.pluralLabel ?? 'All categories'),
          popup: SelectPopup<ListingCategory?>(
            items: SelectItemList(children: [
              const SelectItemButton<ListingCategory?>(key: ValueKey('category_option_all'), value: null, child: Text('All categories')),
              for (final c in ListingCategory.values)
                SelectItemButton<ListingCategory?>(
                  key: ValueKey('category_option_${c.wire}'),
                  value: c,
                  child: Row(children: [
                    Icon(categoryIcon(c), size: 14, color: MarketColors.category(c.wire)),
                    const SizedBox(width: 8),
                    Text(c.label),
                  ]),
                ),
            ]),
          ).call,
        ),
        label('License kind'),
        Select<LicenseKind?>(
          key: const ValueKey('filter_license_kind'),
          value: kind,
          placeholder: const Text('Any'),
          onChanged: (k) => onChanged(k == null
              ? query.copyWith(clearLicenseKind: true)
              : query.copyWith(licenseKind: k, clearLicense: licenseById(query.license)?.kind != k)),
          itemBuilder: (context, k) => Text(k?.label ?? 'Any'),
          popup: SelectPopup<LicenseKind?>(
            items: SelectItemList(children: [
              const SelectItemButton<LicenseKind?>(key: ValueKey('kind_option_any'), value: null, child: Text('Any')),
              for (final k in LicenseKind.values)
                SelectItemButton<LicenseKind?>(key: ValueKey('kind_option_${k.wire}'), value: k, child: Text(k.label)),
            ]),
          ).call,
        ),
        label('License'),
        Select<String?>(
          key: const ValueKey('filter_license'),
          value: query.license,
          placeholder: const Text('Any license'),
          onChanged: (id) => onChanged(id == null ? query.copyWith(clearLicense: true) : query.copyWith(license: id)),
          itemBuilder: (context, id) => Text(id ?? 'Any license'),
          popup: SelectPopup<String?>(
            items: SelectItemList(children: [
              const SelectItemButton<String?>(key: ValueKey('license_option_any'), value: null, child: Text('Any license')),
              for (final l in licenses)
                SelectItemButton<String?>(key: ValueKey('license_option_${l.id}'), value: l.id, child: Text(l.id)),
            ]),
          ).call,
        ),
        label('Engine version'),
        Semantics(
          label: 'Compatible with engine version',
          textField: true,
          child: TextField(
            key: const ValueKey('filter_engine'),
            controller: engine,
            placeholder: const Text('e.g. 0.0.1'),
            onSubmitted: (v) => onChanged(v.trim().isEmpty
                ? query.copyWith(clearEngineVersion: true)
                : query.copyWith(engineVersion: v.trim())),
          ),
        ),
        const SizedBox(height: 14),
        Checkbox(
          key: const ValueKey('filter_free'),
          state: query.free == true ? CheckboxState.checked : CheckboxState.unchecked,
          onChanged: (s) => onChanged(s == CheckboxState.checked ? query.copyWith(free: true) : query.copyWith(clearFree: true)),
          trailing: const Text('Free only'),
        ),
        const SizedBox(height: 6),
        const Text('Every listing is free for now.').xSmall().muted(),
      ]),
    );
  }
}
