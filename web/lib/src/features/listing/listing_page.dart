import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/session.dart';
import '../../platform/files.dart';
import '../../theme/marketplace_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/markdown_view.dart';
import 'model_viewer/listing_model_viewer.dart';
import 'model_viewer/model_viewer_controller.dart';

class ListingViewModel extends ChangeNotifier {
  ListingViewModel(this.client, this.saver, this.slug);
  final MarketplaceClient client;
  final FileSaver saver;
  final String slug;

  bool loading = true;
  bool busy = false;
  String? error;
  String? actionError;
  String? notice;
  Listing? listing;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      listing = await client.listing(slug);
    } catch (e) {
      error = e is MarketplaceException && e.statusCode == 404 ? 'This listing does not exist or was unlisted.' : errorText(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _act(Future<void> Function() body) async {
    busy = true;
    actionError = null;
    notice = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      actionError = errorText(e);
    }
    busy = false;
    notifyListeners();
  }

  /// "Get (Free)".
  Future<void> get() => _act(() async {
        await client.getListing(listing!.id);
        listing = await client.listing(listing!.id);
        notice = 'Added to your library. In Lumina Studio, open Window → Marketplace to add it to a project.';
      });

  Future<void> download(ListingVersion version) => _act(() async {
        final bytes = await client.downloadArchive(listing!.id, version.version);
        await saver.save(version.fileName, bytes,
            mimeType: version.archiveKind == 'json' ? 'application/json' : 'application/zip');
        listing = await client.listing(listing!.id);
        notice = 'Downloaded ${version.fileName}.';
      });

  Future<bool> report(ReportReason reason, String details) async {
    var ok = false;
    await _act(() async {
      await client.report(listing!.id, reason, details: details);
      notice = 'Thanks — a moderator will review your report.';
      ok = true;
    });
    return ok;
  }
}

class ListingPage extends StatefulWidget {
  const ListingPage({super.key, required this.slug});
  final String slug;

  @override
  State<ListingPage> createState() => _ListingPageState();
}

class _ListingPageState extends State<ListingPage> {
  late final ListingViewModel _vm;
  int _image = 0;
  int _tab = 0;

  /// The 3D view replaces the main image while [_show3d].
  bool _show3d = false;
  bool _fullscreen = false;
  ModelViewerController? _viewer;

  @override
  void initState() {
    super.initState();
    final scope = MarketplaceScope.read(context);
    _vm = ListingViewModel(scope.client, scope.fileSaver, widget.slug)..load();
  }

  @override
  void dispose() {
    if (_fullscreen) setBrowserFullscreen(false);
    _viewer?.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _setShow3d(Listing l, bool show) {
    if (show == _show3d) return;
    if (!show && _fullscreen) _exitFullscreen();
    setState(() {
      _show3d = show;
      // Created on first open: until then the Lumina runtime is not loaded.
      if (show) _viewer ??= ModelViewerController(client: _vm.client, version: l.latestVersion!);
    });
  }

  void _enterFullscreen() {
    final viewer = _viewer;
    if (viewer == null || _fullscreen) return;
    // The page body becomes the viewer (remounted on the controller's model
    // and camera), and the browser goes fullscreen when it allows it.
    setState(() => _fullscreen = true);
    setBrowserFullscreen(true);
  }

  void _exitFullscreen() {
    if (!_fullscreen) return;
    setBrowserFullscreen(false);
    if (mounted) setState(() => _fullscreen = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = MarketplaceScope.of(context).session;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        if (_vm.loading) return const PageFrame(children: [LoadingView()]);
        if (_vm.error != null) return PageFrame(children: [ErrorBanner(_vm.error!)]);
        final l = _vm.listing!;
        if (_fullscreen && _viewer != null) return _FullscreenViewer(controller: _viewer!, onExit: _exitFullscreen);
        return LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 980;
          final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _gallery(l),
            const SizedBox(height: 20),
            _tabs(l),
          ]);
          final side = _sidePanel(context, l, session);
          return PageFrame(children: [
            _breadcrumb(context, l),
            const SizedBox(height: 16),
            if (narrow) ...[side, const SizedBox(height: 20), main]
            else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: main),
                const SizedBox(width: 24),
                SizedBox(width: 340, child: side),
              ]),
          ]);
        });
      },
    );
  }

  Widget _breadcrumb(BuildContext context, Listing l) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
        LinkButton(size: ButtonSize.small, onPressed: () => context.go('/search'), child: const Text('Browse')),
        const Icon(LucideIcons.chevronRight, size: 12, color: MarketColors.mutedForeground),
        LinkButton(
          size: ButtonSize.small,
          onPressed: () => context.go('/search?category=${l.category.wire}'),
          child: Text(l.category.pluralLabel),
        ),
        const Icon(LucideIcons.chevronRight, size: 12, color: MarketColors.mutedForeground),
        Text(l.title).small().muted(),
      ]);

  Widget _gallery(Listing l) {
    final count = l.screenshots.length;
    final has3d = l.previewModelUrl != null && l.latestVersion != null;
    final show3d = has3d && _show3d;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (has3d) ...[
        Row(children: [
          const Spacer(),
          Toggle(
            key: const ValueKey('gallery_images'),
            value: !show3d,
            onChanged: (_) => _setShow3d(l, false),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.image, size: 14),
              SizedBox(width: 6),
              Text('Images'),
            ]),
          ),
          const SizedBox(width: 4),
          Toggle(
            key: const ValueKey('gallery_3d'),
            value: show3d,
            onChanged: (_) => _setShow3d(l, true),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.box, size: 14),
              SizedBox(width: 6),
              Text('3D view'),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
      ],
      Container(
        decoration: BoxDecoration(border: Border.all(color: MarketColors.border), borderRadius: BorderRadius.circular(4)),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: !show3d
              ? ListingImage(listing: l, index: _image.clamp(0, count == 0 ? 0 : count - 1))
              : ListingModelViewer(controller: _viewer!, fullscreen: false, onToggleFullscreen: _enterFullscreen),
        ),
      ),
      if (count > 1 && !show3d) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => Clickable(
              onPressed: () => setState(() {
                _image = i;
                _show3d = false;
              }),
              child: Container(
                width: 114,
                decoration: BoxDecoration(
                  border: Border.all(color: i == _image ? MarketColors.primary : MarketColors.border, width: i == _image ? 2 : 1),
                  borderRadius: BorderRadius.circular(3),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListingImage(listing: l, index: i),
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _tabs(Listing l) {
    final versions = l.versions ?? const <ListingVersion>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TabList(
        index: _tab,
        onChanged: (i) => setState(() => _tab = i),
        children: [
          const TabItem(child: Text('Description')),
          TabItem(child: Text('Versions (${versions.length})')),
          const TabItem(child: Text('Licenses')),
        ],
      ),
      const SizedBox(height: 16),
      switch (_tab) {
        0 => l.description.trim().isEmpty ? const Text('No description.').muted() : MarkdownView(l.description),
        1 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final v in versions) _VersionTile(version: v, isLatest: v.id == l.latestVersion?.id),
          ]),
        _ => _LicenseList(ids: l.licenses.ids),
      },
    ]);
  }

  Widget _sidePanel(BuildContext context, Listing l, MarketplaceSession session) {
    final owned = session.user?.id == l.publisher.id;
    final inLibrary = l.inLibrary == true;
    final latest = l.latestVersion;
    return Panel(
      title: l.category.label,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(l.title, key: const ValueKey('listing_title')).h3()),
        const SizedBox(height: 4),
        Text('by ${l.publisher.displayName} (@${l.publisher.username})').small().muted(),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          CategoryBadge(l.category),
          for (final id in l.licenses.ids) LicenseBadge(id),
          if (l.status != ListingStatus.published) DestructiveBadge(child: Text(l.status.wire)),
        ]),
        const SizedBox(height: 14),
        _fact('Price', 'Free'),
        _fact('Downloads', formatCount(l.downloadCount)),
        if (latest != null) ...[
          _fact('Version', latest.version),
          _fact('Engine', '≥ ${latest.engineVersion}'),
          _fact('Size', formatBytes(latest.size)),
          _fact('Updated', formatDate(latest.createdAt)),
        ],
        const SizedBox(height: 16),
        if (_vm.actionError != null) ...[ErrorBanner(_vm.actionError!), const SizedBox(height: 10)],
        if (_vm.notice != null) ...[InfoBanner(_vm.notice!, icon: LucideIcons.circleCheck), const SizedBox(height: 10)],
        if (!session.isSignedIn)
          PrimaryButton(
            key: const ValueKey('listing_get'),
            onPressed: () => context.go(Uri(path: '/login', queryParameters: {'next': '/listings/${l.slug}'}).toString()),
            child: const Text('Log in to get it (Free)'),
          )
        else if (inLibrary)
          SecondaryButton(
            key: const ValueKey('listing_in_library'),
            enabled: false,
            leading: const Icon(LucideIcons.check, size: 14),
            onPressed: null,
            child: const Text('In your library'),
          )
        else
          PrimaryButton(
            key: const ValueKey('listing_get'),
            enabled: !_vm.busy && latest != null,
            onPressed: _vm.busy || latest == null ? null : _vm.get,
            leading: const Icon(LucideIcons.plus, size: 14),
            child: const Text('Get (Free)'),
          ),
        if (session.isSignedIn && (inLibrary || owned) && latest != null) ...[
          const SizedBox(height: 8),
          OutlineButton(
            key: const ValueKey('listing_download'),
            enabled: !_vm.busy,
            onPressed: _vm.busy ? null : () => _vm.download(latest),
            leading: const Icon(LucideIcons.download, size: 14),
            child: Text('Download ${latest.archiveKind == 'json' ? '.json' : '.zip'}'),
          ),
        ],
        if (owned) ...[
          const SizedBox(height: 8),
          OutlineButton(
            key: const ValueKey('listing_new_version'),
            onPressed: () => context.go('/publish/${l.id}'),
            leading: const Icon(LucideIcons.upload, size: 14),
            child: const Text('Publish a new version'),
          ),
        ],
        const SizedBox(height: 12),
        const Text('Add it to a project from Window → Marketplace in Lumina Studio; it installs into '
                'contents/Marketplace/<publisher>/<listing>/.')
            .xSmall()
            .muted(),
        if (session.isSignedIn && !owned) ...[
          const SizedBox(height: 12),
          GhostButton(
            key: const ValueKey('listing_report'),
            size: ButtonSize.small,
            leading: const Icon(LucideIcons.flag, size: 13),
            onPressed: () => _openReport(context),
            child: const Text('Report this listing'),
          ),
        ],
      ]),
    );
  }

  Widget _fact(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 90, child: Text(label).small().muted()),
          Expanded(child: Text(value, textAlign: TextAlign.right).small()),
        ]),
      );

  void _openReport(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(builder: (dialogContext) => _ReportDialog(onSubmit: _vm.report)),
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({required this.version, required this.isLatest});
  final ListingVersion version;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarketColors.card,
        border: Border.all(color: MarketColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('v${version.version}', style: MarketType.mono(fontSize: 13, color: MarketColors.accentForeground)),
          const SizedBox(width: 8),
          if (isLatest) const PrimaryBadge(child: Text('Latest')),
          const Spacer(),
          Text(formatDate(version.createdAt)).xSmall().muted(),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in version.licenses.ids) LicenseBadge(id),
          OutlineBadge(child: Text('${version.fileCount} files · ${formatBytes(version.size)}')),
          OutlineBadge(child: Text('engine ≥ ${version.engineVersion}')),
          OutlineBadge(child: Text('${formatCount(version.downloadCount)} downloads')),
        ]),
        if (version.releaseNotes.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          MarkdownView(version.releaseNotes),
        ],
      ]),
    );
  }
}

class _LicenseList extends StatelessWidget {
  const _LicenseList({required this.ids});
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final id in ids)
        if (licenseById(id) case final l?)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MarketColors.card,
              border: Border.all(color: MarketColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(l.name).semiBold(),
                const SizedBox(width: 8),
                OutlineBadge(child: Text('${l.kind.label} · ${l.id}')),
              ]),
              const SizedBox(height: 6),
              Text(l.summary).small().muted(),
              if (l.attributionRequired) ...[
                const SizedBox(height: 4),
                const Text('Credit the publisher when you use it.').xSmall(),
              ],
              const SizedBox(height: 6),
              LinkButton(
                size: ButtonSize.small,
                onPressed: () => openExternal(l.url),
                trailing: const Icon(LucideIcons.externalLink, size: 12),
                child: const Text('Read the license text'),
              ),
            ]),
          ),
    ]);
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.onSubmit});
  final Future<bool> Function(ReportReason reason, String details) onSubmit;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report this listing'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Moderators review every report. Publishing someone else\'s work can get all of the publisher\'s '
                  'listings removed and their account suspended.')
              .small()
              .muted(),
          const SizedBox(height: 12),
          Select<ReportReason>(
            key: const ValueKey('report_reason'),
            value: _reason,
            placeholder: const Text('Pick a reason'),
            onChanged: (r) => setState(() => _reason = r),
            itemBuilder: (context, r) => Text(r.label),
            popup: SelectPopup<ReportReason>(
              items: SelectItemList(children: [
                for (final r in ReportReason.values)
                  SelectItemButton(key: ValueKey('report_reason_${r.wire}'), value: r, child: Text(r.label)),
              ]),
            ).call,
          ),
          const SizedBox(height: 12),
          LabeledField(label: 'Details', controller: _details, fieldKey: const ValueKey('report_details'), maxLines: 4),
        ]),
      ),
      actions: [
        GhostButton(onPressed: () => closeOverlay(context), child: const Text('Cancel')),
        DestructiveButton(
          key: const ValueKey('report_submit'),
          enabled: _reason != null && !_busy,
          onPressed: _reason == null || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await widget.onSubmit(_reason!, _details.text.trim());
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (ok) closeOverlay(context);
                },
          child: const Text('Send report'),
        ),
      ],
    );
  }
}

/// The 3D view filling the page; Esc or the toolbar button exits.
class _FullscreenViewer extends StatelessWidget {
  const _FullscreenViewer({required this.controller, required this.onExit});
  final ModelViewerController controller;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): onExit},
          child: Focus(
            autofocus: true,
            child: ColoredBox(
              color: MarketColors.background,
              child: ListingModelViewer(controller: controller, fullscreen: true, onToggleFullscreen: onExit),
            ),
          ),
        ),
      );
}
