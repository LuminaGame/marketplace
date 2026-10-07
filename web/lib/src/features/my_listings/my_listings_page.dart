import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/theme/marketplace_theme.dart';
import 'package:lumina_marketplace_web/src/widgets/common.dart';

class MyListingsViewModel extends ChangeNotifier {
  MyListingsViewModel(this.client);
  final MarketplaceClient client;

  bool loading = true;
  bool busy = false;
  String? error;
  List<Listing> listings = const [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      listings = await client.myListings();
    } catch (e) {
      error = errorText(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _act(Future<void> Function() body) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
      listings = await client.myListings();
    } catch (e) {
      error = errorText(e);
    }
    busy = false;
    notifyListeners();
  }

  Future<void> unlist(Listing l) => _act(() => client.unlist(l.id));
  Future<void> relist(Listing l) => _act(() => client.relist(l.id));
  Future<void> save(Listing l, {required String title, required String description, required List<String> tags}) =>
      _act(() => client.updateListing(l.id, title: title, description: description, tags: tags));
}

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  late final MyListingsViewModel _vm = MyListingsViewModel(MarketplaceScope.read(context).client)..load();

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
        Row(children: [
          Expanded(child: Semantics(header: true, child: const Text('My listings').h3())),
          PrimaryButton(
            key: const ValueKey('my_listings_new'),
            leading: const Icon(LucideIcons.plus, size: 14),
            onPressed: () => context.go('/publish'),
            child: const Text('New listing'),
          ),
        ]),
        const SizedBox(height: 16),
        if (_vm.error != null) ...[ErrorBanner(_vm.error!), const SizedBox(height: 12)],
        if (_vm.loading)
          const LoadingView()
        else if (_vm.listings.isEmpty)
          const InfoBanner('You have not published anything yet.', title: 'No listings')
        else
          for (final l in _vm.listings) _row(context, l),
      ]),
    );
  }

  Widget _row(BuildContext context, Listing l) {
    final status = switch (l.status) {
      ListingStatus.published => const PrimaryBadge(child: Text('Published')),
      ListingStatus.draft => const SecondaryBadge(child: Text('Draft')),
      ListingStatus.unlisted => DestructiveBadge(child: Text(l.unlistedBy == 'moderator' ? 'Unlisted by a moderator' : 'Unlisted')),
    };
    return Container(
      key: ValueKey('my_listing_${l.slug}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarketColors.card,
        border: Border.all(color: MarketColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Container(
          width: 128,
          height: 72,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: MarketColors.border)),
          clipBehavior: Clip.antiAlias,
          child: ListingImage(listing: l),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(l.title, overflow: TextOverflow.ellipsis).semiBold()),
              const SizedBox(width: 8),
              status,
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              CategoryBadge(l.category),
              for (final id in l.licenses.ids) LicenseBadge(id),
              if (l.latestVersion != null) OutlineBadge(child: Text('v${l.latestVersion!.version}')),
              OutlineBadge(child: Text('${formatCount(l.downloadCount)} downloads')),
            ]),
            if (l.unlistedReason != null) ...[
              const SizedBox(height: 6),
              Text('Reason: ${l.unlistedReason}').xSmall().muted(),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (l.status != ListingStatus.draft)
            GhostButton(size: ButtonSize.small, onPressed: () => context.go('/listings/${l.slug}'), child: const Text('View')),
          GhostButton(
            key: ValueKey('my_listing_edit_${l.slug}'),
            size: ButtonSize.small,
            enabled: !_vm.busy,
            onPressed: () => _edit(context, l),
            child: const Text('Edit'),
          ),
          OutlineButton(
            key: ValueKey('my_listing_version_${l.slug}'),
            size: ButtonSize.small,
            onPressed: () => context.go(l.latestVersion == null ? '/publish' : '/publish/${l.id}'),
            child: Text(l.latestVersion == null ? 'Finish publishing' : 'New version'),
          ),
          if (l.status == ListingStatus.published)
            OutlineButton(
              key: ValueKey('my_listing_unlist_${l.slug}'),
              size: ButtonSize.small,
              enabled: !_vm.busy,
              onPressed: () => _vm.unlist(l),
              child: const Text('Unlist'),
            ),
          if (l.status == ListingStatus.unlisted && l.unlistedBy == 'owner')
            OutlineButton(
              key: ValueKey('my_listing_relist_${l.slug}'),
              size: ButtonSize.small,
              enabled: !_vm.busy,
              onPressed: () => _vm.relist(l),
              child: const Text('List again'),
            ),
        ]),
      ]),
    );
  }

  void _edit(BuildContext context, Listing l) {
    showOverlay(context, const DialogConfiguration(), builder: (dialogContext) => _EditDialog(listing: l, vm: _vm));
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.listing, required this.vm});
  final Listing listing;
  final MyListingsViewModel vm;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _title = TextEditingController(text: widget.listing.title);
  late final _description = TextEditingController(text: widget.listing.description);
  late final _tags = TextEditingController(text: widget.listing.tags.join(', '));

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.listing.title}'),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledField(label: 'Title', controller: _title, fieldKey: const ValueKey('edit_title')),
          const SizedBox(height: 12),
          LabeledField(label: 'Description (Markdown)', controller: _description, maxLines: 8),
          const SizedBox(height: 12),
          LabeledField(label: 'Tags', controller: _tags, help: 'Comma-separated.'),
        ]),
      ),
      actions: [
        GhostButton(onPressed: () => closeOverlay(context), child: const Text('Cancel')),
        PrimaryButton(
          key: const ValueKey('edit_save'),
          onPressed: () async {
            await widget.vm.save(
              widget.listing,
              title: _title.text.trim(),
              description: _description.text,
              tags: _tags.text.split(RegExp(r'[,\s]+')).where((t) => t.isNotEmpty).toList(),
            );
            if (context.mounted) closeOverlay(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
