import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/platform/files.dart';
import 'package:lumina_marketplace_web/src/theme/marketplace_theme.dart';
import 'package:lumina_marketplace_web/src/widgets/common.dart';

class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel(this.client, this.saver);
  final MarketplaceClient client;
  final FileSaver saver;

  bool loading = true;
  bool busy = false;
  String? error;
  String? notice;
  List<LibraryEntry> entries = const [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      entries = await client.library();
    } catch (e) {
      error = errorText(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> download(Listing l) async {
    final v = l.latestVersion;
    if (v == null) return;
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      final bytes = await client.downloadArchive(l.id, v.version);
      await saver.save(v.fileName, bytes, mimeType: v.archiveKind == 'json' ? 'application/json' : 'application/zip');
      notice = 'Downloaded ${v.fileName}.';
    } catch (e) {
      error = errorText(e);
    }
    busy = false;
    notifyListeners();
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final LibraryViewModel _vm;

  @override
  void initState() {
    super.initState();
    final scope = MarketplaceScope.read(context);
    _vm = LibraryViewModel(scope.client, scope.fileSaver)..load();
  }

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
        Semantics(header: true, child: const Text('My library').h3()),
        const SizedBox(height: 4),
        const Text('Everything you got. In Lumina Studio, open Window → Marketplace and choose Add to Project: it '
                'installs into contents/Marketplace/<publisher>/<listing>/ with its license notice.')
            .muted(),
        const SizedBox(height: 16),
        if (_vm.error != null) ...[ErrorBanner(_vm.error!), const SizedBox(height: 12)],
        if (_vm.notice != null) ...[InfoBanner(_vm.notice!, icon: LucideIcons.circleCheck), const SizedBox(height: 12)],
        if (_vm.loading)
          const LoadingView()
        else if (_vm.entries.isEmpty)
          InfoBanner('Your library is empty. Browse the marketplace and choose "Get (Free)".', title: 'Nothing here yet', icon: LucideIcons.library)
        else
          for (final e in _vm.entries) _row(context, e),
      ]),
    );
  }

  Widget _row(BuildContext context, LibraryEntry e) {
    final l = e.listing;
    final pulled = l.status == ListingStatus.unlisted && l.unlistedBy == 'moderator';
    return Container(
      key: ValueKey('library_${l.slug}'),
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
            Text(l.title).semiBold(),
            Text('by ${l.publisher.displayName} · got ${formatDate(e.acquiredAt)}').xSmall().muted(),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              CategoryBadge(l.category),
              for (final id in l.licenses.ids) LicenseBadge(id),
              if (l.latestVersion != null) OutlineBadge(child: Text('v${l.latestVersion!.version}')),
              if (pulled) const DestructiveBadge(child: Text('Removed by a moderator')),
            ]),
          ]),
        ),
        Wrap(spacing: 6, children: [
          if (!pulled) GhostButton(size: ButtonSize.small, onPressed: () => context.go('/listings/${l.slug}'), child: const Text('View')),
          OutlineButton(
            key: ValueKey('library_download_${l.slug}'),
            size: ButtonSize.small,
            enabled: !_vm.busy && !pulled && l.latestVersion != null,
            onPressed: _vm.busy || pulled ? null : () => _vm.download(l),
            leading: const Icon(LucideIcons.download, size: 14),
            child: const Text('Download'),
          ),
        ]),
      ]),
    );
  }
}
