import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/session.dart';
import '../../theme/marketplace_theme.dart';
import '../../widgets/common.dart';

class ModerationViewModel extends ChangeNotifier {
  ModerationViewModel(this.client);
  final MarketplaceClient client;

  bool loading = true;
  bool busy = false;
  String? error;
  String? notice;
  List<ListingReport> open = const [];
  List<ListingReport> resolved = const [];
  List<AuditEntry> audit = const [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    await _refresh();
    loading = false;
    notifyListeners();
  }

  Future<void> _refresh() async {
    try {
      final all = await client.reports(status: null);
      open = [for (final r in all) if (r.status == ReportStatus.open) r];
      resolved = [for (final r in all) if (r.status != ReportStatus.open) r];
      audit = await client.auditLog(limit: 50);
    } catch (e) {
      error = errorText(e);
    }
  }

  Future<void> _act(Future<void> Function() body, String done) async {
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    var ok = false;
    try {
      await body();
      ok = true;
    } catch (e) {
      error = errorText(e);
    }
    await _refresh();
    if (ok) notice = done;
    busy = false;
    notifyListeners();
  }

  void fail(String message) {
    error = message;
    notice = null;
    notifyListeners();
  }

  Future<void> unlist(ListingReport r, String note) =>
      _act(() => client.resolveReport(r.id, action: 'unlist', note: note), '“${r.listingTitle}” was unlisted.');
  Future<void> dismiss(ListingReport r, String note) =>
      _act(() => client.resolveReport(r.id, action: 'dismiss', note: note), 'Report dismissed.');
  Future<void> restore(ListingReport r) =>
      _act(() => client.moderatorRestore(r.listingId), '“${r.listingTitle}” is listed again.');
  Future<void> suspend(String username, String reason) => _act(
      () => client.suspend(username, reason: reason),
      '@$username is suspended: all of their listings are unlisted and their sessions revoked.');
  Future<void> unsuspend(String username) =>
      _act(() => client.unsuspend(username), '@$username is active again (their listings stay unlisted until restored).');
}

class ModerationPage extends StatefulWidget {
  const ModerationPage({super.key});

  @override
  State<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends State<ModerationPage> {
  late final ModerationViewModel _vm = ModerationViewModel(MarketplaceScope.read(context).client)..load();
  int _tab = 0;
  final _username = TextEditingController();
  final _reason = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _vm.dispose();
    _username.dispose();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => PageFrame(children: [
        Semantics(header: true, child: const Text('Moderation').h3()),
        const SizedBox(height: 4),
        const Text('Reports, unlisting, suspensions. Every action lands in the append-only audit log.').muted(),
        const SizedBox(height: 16),
        TabList(key: ValueKey('mod_tabs_${_vm.open.length}'), index: _tab, onChanged: (i) => setState(() => _tab = i), children: [
          TabItem(child: Text('Reports (${_vm.open.length})', key: const ValueKey('mod_tab_reports'))),
          const TabItem(child: Text('Resolved', key: ValueKey('mod_tab_resolved'))),
          const TabItem(child: Text('Publishers', key: ValueKey('mod_tab_users'))),
          const TabItem(child: Text('Audit log', key: ValueKey('mod_tab_audit'))),
        ]),
        const SizedBox(height: 16),
        if (_vm.error != null) ...[ErrorBanner(_vm.error!), const SizedBox(height: 12)],
        if (_vm.notice != null) ...[InfoBanner(_vm.notice!, icon: LucideIcons.circleCheck), const SizedBox(height: 12)],
        if (_vm.loading)
          const LoadingView()
        else
          switch (_tab) {
            0 => _reports(context),
            1 => _resolved(context),
            2 => _users(),
            _ => _audit(),
          },
      ]),
    );
  }

  Widget _card({required Key key, required List<Widget> children}) => Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MarketColors.card,
          border: Border.all(color: MarketColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _reports(BuildContext context) {
    if (_vm.open.isEmpty) return const InfoBanner('The queue is empty.', title: 'No open reports', icon: LucideIcons.inbox);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledField(label: 'Resolution note (optional)', controller: _note, fieldKey: const ValueKey('mod_note')),
      const SizedBox(height: 12),
      for (final r in _vm.open)
        _card(key: ValueKey('report_${r.id}'), children: [
          Row(children: [
            Expanded(
              child: LinkButton(
                size: ButtonSize.small,
                onPressed: () => context.go('/listings/${r.listingId}'),
                child: Text(r.listingTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            DestructiveBadge(child: Text(r.reason.label)),
          ]),
          Text('by @${r.publisher.username} · reported by @${r.reporter} on ${formatDate(r.createdAt)}').xSmall().muted(),
          if (r.details.isNotEmpty) ...[const SizedBox(height: 6), Text(r.details).small()],
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            DestructiveButton(
              key: ValueKey('report_unlist_${r.id}'),
              size: ButtonSize.small,
              enabled: !_vm.busy,
              onPressed: () => _vm.unlist(r, _note.text.trim()),
              child: const Text('Unlist listing'),
            ),
            OutlineButton(
              key: ValueKey('report_dismiss_${r.id}'),
              size: ButtonSize.small,
              enabled: !_vm.busy,
              onPressed: () => _vm.dismiss(r, _note.text.trim()),
              child: const Text('Dismiss'),
            ),
            GhostButton(
              size: ButtonSize.small,
              onPressed: () {
                _username.text = r.publisher.username;
                setState(() => _tab = 2);
              },
              child: const Text('Suspend publisher…'),
            ),
          ]),
        ]),
    ]);
  }

  Widget _resolved(BuildContext context) {
    if (_vm.resolved.isEmpty) return const InfoBanner('Nothing resolved yet.');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in _vm.resolved)
        _card(key: ValueKey('resolved_${r.id}'), children: [
          Row(children: [
            Expanded(child: Text(r.listingTitle).semiBold()),
            r.status == ReportStatus.actioned
                ? const DestructiveBadge(child: Text('Unlisted'))
                : const SecondaryBadge(child: Text('Dismissed')),
          ]),
          Text('${r.reason.label} · resolved by @${r.resolvedBy ?? '?'}${r.resolutionNote?.isNotEmpty == true ? ' — ${r.resolutionNote}' : ''}')
              .xSmall()
              .muted(),
          if (r.status == ReportStatus.actioned && r.listingStatus == ListingStatus.unlisted) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlineButton(
                key: ValueKey('resolved_restore_${r.id}'),
                size: ButtonSize.small,
                enabled: !_vm.busy,
                onPressed: () => _vm.restore(r),
                child: const Text('Restore listing'),
              ),
            ),
          ],
        ]),
    ]);
  }

  Widget _users() {
    return Panel(
      title: 'Suspend or restore a publisher',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Suspending enforces the publishing terms\' penalty: all of the publisher\'s listings are unlisted, the '
                'account is suspended and every session and token it holds is revoked.')
            .small()
            .muted(),
        const SizedBox(height: 12),
        LabeledField(label: 'Username', controller: _username, fieldKey: const ValueKey('mod_username')),
        const SizedBox(height: 12),
        LabeledField(label: 'Reason', controller: _reason, fieldKey: const ValueKey('mod_reason')),
        const SizedBox(height: 12),
        Row(children: [
          DestructiveButton(
            key: const ValueKey('mod_suspend'),
            enabled: !_vm.busy,
            onPressed: () {
              if (_username.text.trim().isEmpty || _reason.text.trim().isEmpty) {
                _vm.fail('Enter the username and a reason.');
                return;
              }
              _vm.suspend(_username.text.trim(), _reason.text.trim());
            },
            child: const Text('Suspend'),
          ),
          const SizedBox(width: 8),
          OutlineButton(
            key: const ValueKey('mod_unsuspend'),
            enabled: !_vm.busy,
            onPressed: () => _username.text.trim().isEmpty ? null : _vm.unsuspend(_username.text.trim()),
            child: const Text('Lift suspension'),
          ),
        ]),
      ]),
    );
  }

  Widget _audit() {
    return Panel(
      title: 'Audit log (latest 50)',
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in _vm.audit)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MarketColors.border))),
            child: Row(children: [
              SizedBox(width: 150, child: Text(formatDate(e.createdAt)).xSmall().muted()),
              SizedBox(width: 120, child: Text('@${e.actor}').small()),
              SizedBox(width: 150, child: Text(e.action, style: MarketType.mono(fontSize: 12, color: MarketColors.primary))),
              Expanded(
                child: Text('${e.targetType} ${e.targetId}${e.details.isEmpty ? '' : ' · ${e.details.entries.map((d) => '${d.key}: ${d.value}').join(', ')}'}',
                        overflow: TextOverflow.ellipsis)
                    .xSmall()
                    .muted(),
              ),
            ]),
          ),
      ]),
    );
  }
}
