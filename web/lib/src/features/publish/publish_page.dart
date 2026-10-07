import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/platform/files.dart';
import 'package:lumina_marketplace_web/src/theme/marketplace_theme.dart';
import 'package:lumina_marketplace_web/src/widgets/common.dart';
import 'package:lumina_marketplace_web/src/widgets/markdown_view.dart';
import 'package:lumina_marketplace_web/src/features/publish/publish_view_model.dart';

class PublishPage extends StatefulWidget {
  const PublishPage({super.key, this.listingId});

  /// Publish a new version of this listing instead of a new listing.
  final String? listingId;

  @override
  State<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> {
  late final PublishViewModel _vm;
  bool _showChangelog = false;

  @override
  void initState() {
    super.initState();
    final scope = MarketplaceScope.read(context);
    _vm = PublishViewModel(scope.client, scope.fileSource, listingId: widget.listingId)..init();
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
      builder: (context, _) {
        if (_vm.loading) return const PageFrame(children: [LoadingView()]);
        if (_vm.published != null) return _done(context);
        return PageFrame(maxWidth: 920, children: [
          Semantics(
            header: true,
            child: Text(_vm.isNewVersion ? 'Publish a new version of ${_vm.listing?.title ?? ''}' : 'Publish to the marketplace').h3(),
          ),
          const SizedBox(height: 6),
          const Text('Free listings only for now. Every version needs a free license and your ownership attestation.').muted(),
          const SizedBox(height: 20),
          _StepHeader(current: _vm.step, steps: _vm.steps),
          const SizedBox(height: 20),
          if (_vm.error != null) ...[ErrorBanner(_vm.error!), const SizedBox(height: 14)],
          switch (_vm.step) {
            PublishStep.details => _details(),
            PublishStep.screenshots => _screenshots(),
            PublishStep.upload => _upload(),
            PublishStep.licenses => _licenses(),
            PublishStep.publish => _attest(),
          },
        ]);
      },
    );
  }

  /// Back to the step before [s] in this flow's order, or no Back button.
  VoidCallback? _back(PublishStep s) {
    final before = _vm.stepBefore(s);
    return before == null ? null : () => _vm.goTo(before);
  }

  Widget _nav({VoidCallback? back, required VoidCallback? next, required String nextLabel, Key? nextKey, bool primary = true}) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(children: [
        if (back != null)
          GhostButton(
            key: const ValueKey('publish_back'),
            onPressed: _vm.busy ? null : back,
            leading: const Icon(LucideIcons.chevronLeft, size: 14),
            child: const Text('Back'),
          ),
        const Spacer(),
        if (_vm.busy) const Padding(padding: EdgeInsets.only(right: 12), child: CircularProgressIndicator(size: 16)),
        PrimaryButton(
          key: nextKey ?? const ValueKey('publish_continue'),
          enabled: !_vm.busy,
          onPressed: _vm.busy ? null : next,
          trailing: primary ? const Icon(LucideIcons.chevronRight, size: 14) : null,
          child: Text(nextLabel),
        ),
      ]),
    );
  }

  Widget _details() {
    final locked = _vm.listing?.latestVersion != null;
    return Panel(
      title: 'Listing details',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Category').small().semiBold(),
        const SizedBox(height: 6),
        Select<ListingCategory>(
          key: const ValueKey('publish_category'),
          value: _vm.category,
          enabled: !locked,
          placeholder: const Text('Pick a category'),
          onChanged: _vm.setCategory,
          itemBuilder: (context, c) => Row(children: [
            Icon(categoryIcon(c), size: 14, color: MarketColors.category(c.wire)),
            const SizedBox(width: 8),
            Text(c.label),
          ]),
          popup: SelectPopup<ListingCategory>(
            items: SelectItemList(children: [
              for (final c in ListingCategory.values)
                SelectItemButton(
                  key: ValueKey('publish_category_${c.wire}'),
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
        if (_vm.pluginFirst && _vm.plugin != null) ...[
          const SizedBox(height: 10),
          Text(
            key: const ValueKey('publish_details_from_manifest'),
            'Filled from ${_vm.plugin!.manifestFileName}: edit the text if you like. The version '
            '(${_vm.plugin!.version}) and the licenses the package declares come from the package.',
          ).small().muted(),
        ],
        const SizedBox(height: 14),
        LabeledField(label: 'Title', controller: _vm.title, fieldKey: const ValueKey('publish_title')),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Description (Markdown)',
          controller: _vm.description,
          fieldKey: const ValueKey('publish_description'),
          maxLines: 8,
          help: 'Headings, lists, **bold**, `code` and links render on the listing page.',
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: LabeledField(
              label: 'Tags',
              controller: _vm.tags,
              fieldKey: const ValueKey('publish_tags'),
              placeholder: 'barrel, prop, industrial',
              help: 'Comma-separated, up to 10.',
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 160,
            child: LabeledField(
              label: 'Engine version',
              controller: _vm.engineVersion,
              fieldKey: const ValueKey('publish_engine'),
              help: 'Minimum Lumina version.',
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 160,
            child: LabeledField(
              label: 'Price',
              controller: _vm.price,
              fieldKey: const ValueKey('publish_price'),
              enabled: false,
              help: 'Free only for now',
            ),
          ),
        ]),
        _nav(
          back: _back(PublishStep.details),
          next: _vm.submitDetails,
          nextLabel: _vm.listing == null ? 'Create listing' : 'Save and continue',
        ),
      ]),
    );
  }

  Widget _screenshots() {
    final l = _vm.listing!;
    return Panel(
      title: 'Screenshots',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Add up to 8 PNG, JPEG or WebP images. The first one is the card image.').small().muted(),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < l.screenshots.length; i++)
            Stack(children: [
              Container(
                width: 192,
                height: 108,
                decoration: BoxDecoration(border: Border.all(color: MarketColors.border), borderRadius: BorderRadius.circular(3)),
                clipBehavior: Clip.antiAlias,
                child: ListingImage(listing: l, index: i),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.ghost(
                  icon: const Icon(LucideIcons.x, size: 14),
                  onPressed: _vm.busy ? null : () => _vm.removeScreenshot(i),
                ),
              ),
            ]),
          OutlineButton(
            key: const ValueKey('publish_add_screenshot'),
            enabled: !_vm.busy && l.screenshots.length < 8,
            onPressed: _vm.busy ? null : _vm.addScreenshot,
            leading: const Icon(LucideIcons.imagePlus, size: 14),
            child: const Text('Add screenshot'),
          ),
        ]),
        _nav(back: _back(PublishStep.screenshots), next: _vm.continueFromScreenshots, nextLabel: 'Continue'),
      ]),
    );
  }

  Widget _upload() {
    final json = _vm.category?.acceptsJson ?? false;
    final upload = _vm.upload;
    return Panel(
      title: 'Upload the version',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(json
                ? 'Themes are a single .json file.'
                : 'A .zip of your Lumina assets or project folder (or a plugin package). Paths must stay inside the archive; '
                    'allowed: meshes, textures, audio, .lmas, Dart code, JSON/YAML, text.')
            .small()
            .muted(),
        if (_vm.category == ListingCategory.gameTemplate) ...[
          const SizedBox(height: 6),
          Text(
            key: const ValueKey('publish_template_format'),
            'Game template (format $kGameTemplateFormatVersion): your project folder with contents/ (levels and assets) and '
            'a template.json with a title, or the project\'s one .lmproject; optionally lib/, pubspec.yaml and a '
            'thumbnail.png. Leave out ${kGameTemplatePlatformFolders.map((f) => '$f/').join(' ')}, build/ and .dart_tool/. '
            'A pubspec path dependency other than lumina must be a copy inside the template (e.g. packages/<name>/).',
          ).small().muted(),
        ],
        if (_vm.category == ListingCategory.plugin) ...[
          const SizedBox(height: 6),
          const Text(
            key: ValueKey('publish_plugin_format'),
            'Plugin: a .zip of the plugin folder (e.g. my_plugin/) with its my_plugin$kPluginManifestExtension manifest at the '
            'top. The listing is filled from the manifest (friendly_name, description, category, version, engine_version); '
            'the license from its "license" key or the LICENSE text; the release notes from the version\'s section of '
            'CHANGELOG.md.',
          ).small().muted(),
        ],
        const SizedBox(height: 12),
        Row(children: [
          OutlineButton(
            key: const ValueKey('publish_choose_file'),
            enabled: !_vm.busy,
            onPressed: _vm.busy ? null : _vm.chooseArchive,
            leading: const Icon(LucideIcons.fileArchive, size: 14),
            child: Text(json ? 'Choose .json' : _vm.category == ListingCategory.plugin ? 'Choose plugin .zip' : 'Choose .zip'),
          ),
          const SizedBox(width: 12),
          if (upload != null)
            Expanded(child: Text('${upload.fileName} · ${formatBytes(upload.size)} · ${upload.files.length} files', key: const ValueKey('publish_upload_summary')).small()),
        ]),
        if (_vm.plugin case final p?) ...[const SizedBox(height: 12), _pluginSummary(p)],
        if (upload != null) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: MarketColors.rail,
              border: Border.all(color: MarketColors.border),
              borderRadius: BorderRadius.circular(3),
            ),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(8), children: [
              for (final f in upload.files)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(f.path, style: MarketType.mono(fontSize: 12))),
                    Text(formatBytes(f.size)).xSmall().muted(),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Text('Contains: ${upload.detectedLicenseKinds.isEmpty ? 'no licensed content' : upload.detectedLicenseKinds.map((k) => k.wire).join(' and ')}.').small(),
          // Generated folders the server left out of a plugin package.
          if (upload.skippedPaths.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              key: const ValueKey('publish_upload_skipped'),
              'Left out ${upload.skippedFileCount} generated file${upload.skippedFileCount == 1 ? '' : 's'} in '
              '${upload.skippedPaths.join(', ')}: build output and tool folders are not part of a plugin package, '
              'so they are not stored or installed.',
            ).small().muted(),
          ],
        ],
        _nav(
          back: _back(PublishStep.upload),
          next: _vm.continueFromUpload,
          nextLabel: 'Continue',
        ),
      ]),
    );
  }

  /// What the plugin package declares, as the flow will use it.
  Widget _pluginSummary(PluginPackageInfo p) {
    final license = p.license;
    final String licenseText;
    if (license != null) {
      licenseText = '${license.selection.ids.join(' AND ')} (from ${license.fileName})';
    } else if (p.licenseFile != null) {
      licenseText = 'none declared: ${p.licenseFile!.split('/').last} was not recognised; pick the licenses on the Licenses step';
    } else {
      licenseText = 'none declared: pick the licenses on the Licenses step';
    }
    final changelog = p.changelogPath?.split('/').last;
    final String notes;
    if (changelog == null) {
      notes = 'no changelog in the package';
    } else if (p.releaseNotes != null) {
      notes = 'release notes from the ${p.version} section of $changelog';
    } else {
      notes = '$changelog has no ${p.version} section; write the release notes on the Publish step';
    }
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label).small().muted()),
            Expanded(child: Text(value).small()),
          ]),
        );
    return Container(
      key: const ValueKey('publish_plugin_summary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarketColors.card,
        border: Border.all(color: MarketColors.primary),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(LucideIcons.plug, size: 14, color: MarketColors.primary),
          const SizedBox(width: 8),
          Text('Read from ${p.manifestFileName}').small().semiBold(),
        ]),
        const SizedBox(height: 8),
        row('Plugin', '${p.title} (${p.name})'),
        row('Version', p.version),
        if (p.engineVersionConstraint != null) row('Engine', '${p.engineVersionConstraint} → minimum ${p.minEngineVersion ?? 'any'}'),
        if (p.authors.isNotEmpty) row('Authors', p.authors.join(', ')),
        if (p.tags.isNotEmpty) row('Tags', p.tags.join(', ')),
        row('License', licenseText),
        row('Changelog', notes),
      ]),
    );
  }

  Widget _licenseSelect(LicenseKind kind) {
    final declared = _vm.declaredLicense(kind);
    final value = kind == LicenseKind.content ? _vm.contentLicense : _vm.codeLicense;
    final options = licensesOfKind(kind);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${kind.label} license').small().semiBold(),
      const SizedBox(height: 6),
      Select<String>(
        key: ValueKey('publish_license_${kind.wire}'),
        // A license the package declares is the version's.
        enabled: declared == null,
        value: declared ?? value,
        placeholder: Text('Pick a ${kind.wire} license'),
        onChanged: (id) => _vm.setLicense(kind, id),
        itemBuilder: (context, id) => Text('${licenseById(id)?.name ?? id} ($id)'),
        popup: SelectPopup<String>(
          items: SelectItemList(children: [
            for (final l in options)
              SelectItemButton(
                key: ValueKey('publish_license_option_${l.id}'),
                value: l.id,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${l.id} — ${l.name}'),
                  Text(l.summary).xSmall().muted(),
                ]),
              ),
          ]),
        ).call,
      ),
      if (declared != null) ...[
        const SizedBox(height: 6),
        Text(
          key: ValueKey('publish_license_source_${kind.wire}'),
          'Declared by ${_vm.plugin!.license!.fileName}'
          '${_vm.plugin!.license!.source == PluginLicenseSource.licenseFile ? ' (recognised license text)' : ''}: '
          'the package\'s own license, so it cannot be changed here.',
        ).xSmall(),
      ],
      if (licenseById(declared ?? value) case final l?) ...[
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(l.summary).xSmall().muted()),
          LinkButton(
            size: ButtonSize.small,
            onPressed: () => openExternal(l.url),
            trailing: const Icon(LucideIcons.externalLink, size: 12),
            child: const Text('License text'),
          ),
        ]),
      ],
    ]);
  }

  Widget _licenses() {
    final kinds = _vm.requiredKinds;
    return Panel(
      title: 'Licenses',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(kinds.length == 2
                ? 'This version contains both content and code: pick one license of each kind.'
                : kinds.contains(LicenseKind.code)
                    ? 'This version contains code: pick a code license.'
                    : 'This version contains content (models, images, sounds…): pick a content license.')
            .small(),
        const SizedBox(height: 4),
        const Text('Only free licenses are available. Content: CC0-1.0, CC-BY-4.0, CC-BY-SA-4.0. '
                'Code: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, MPL-2.0, Zlib.')
            .xSmall()
            .muted(),
        if (_vm.plugin case final p? when p.license == null) ...[
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('publish_license_hint'),
            '${p.manifestFileName} declares no license. Pick them here — or add "license": "MIT" (an SPDX id; '
            '"CC-BY-4.0 AND MIT" for content and code) to the manifest and ship the license text as LICENSE, so '
            'the next version takes it from the package.',
          ).xSmall(),
        ],
        const SizedBox(height: 14),
        for (final kind in LicenseKind.values)
          if (kinds.contains(kind)) Padding(padding: const EdgeInsets.only(bottom: 14), child: _licenseSelect(kind)),
        _nav(back: _back(PublishStep.licenses), next: _vm.continueFromLicenses, nextLabel: 'Continue'),
      ]),
    );
  }

  Widget _attest() {
    final terms = _vm.terms!;
    final plugin = _vm.plugin;
    return Panel(
      title: 'Ownership attestation',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: LabeledField(
              label: 'Version',
              controller: _vm.version,
              fieldKey: const ValueKey('publish_version'),
              // A plugin version is its manifest's.
              enabled: plugin == null,
              help: plugin == null ? null : 'From ${plugin.manifestFileName}',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: LabeledField(
              label: 'Release notes',
              controller: _vm.releaseNotes,
              fieldKey: const ValueKey('publish_release_notes'),
              maxLines: 3,
              help: plugin?.releaseNotes == null
                  ? null
                  : 'From the ${plugin!.version} section of ${plugin.changelogPath!.split('/').last}; edit if you like.',
            ),
          ),
        ]),
        if (plugin?.changelog case final changelog?) ...[
          const SizedBox(height: 8),
          Row(children: [
            GhostButton(
              key: const ValueKey('publish_changelog_toggle'),
              size: ButtonSize.small,
              onPressed: () => setState(() => _showChangelog = !_showChangelog),
              leading: Icon(_showChangelog ? LucideIcons.chevronDown : LucideIcons.chevronRight, size: 12),
              child: Text('${_showChangelog ? 'Hide' : 'Show'} ${plugin!.changelogPath!.split('/').last}'),
            ),
          ]),
          if (_showChangelog)
            Container(
              key: const ValueKey('publish_changelog'),
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MarketColors.rail,
                border: Border.all(color: MarketColors.border),
                borderRadius: BorderRadius.circular(3),
              ),
              child: SingleChildScrollView(child: MarkdownView(changelog)),
            ),
        ],
        const SizedBox(height: 16),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Licenses:').small(),
          for (final id in _vm.selection.ids) LicenseBadge(id),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x14EE3533),
            border: Border.all(color: const Color(0x55EE3533)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(LucideIcons.shieldAlert, size: 16, color: MarketColors.destructive),
              SizedBox(width: 8),
              Text('Penalty for publishing work you do not own', style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Text(terms.penalty, key: const ValueKey('publish_penalty')).small(),
          ]),
        ),
        const SizedBox(height: 14),
        Checkbox(
          key: const ValueKey('publish_attestation'),
          state: _vm.attested ? CheckboxState.checked : CheckboxState.unchecked,
          onChanged: (s) => _vm.setAttested(s == CheckboxState.checked),
          trailing: Flexible(child: Text(terms.attestationStatement)),
        ),
        const SizedBox(height: 4),
        Text('Terms version ${terms.version}. Your confirmation is stored with your account, the time and the listing.').xSmall().muted(),
        _nav(
          back: _back(PublishStep.publish),
          next: _vm.publish,
          nextLabel: 'Publish',
          nextKey: const ValueKey('publish_submit'),
          primary: false,
        ),
      ]),
    );
  }

  Widget _done(BuildContext context) {
    final l = _vm.listing!;
    return PageFrame(maxWidth: 720, children: [
      Panel(
        title: 'Published',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(LucideIcons.circleCheck, color: MarketColors.success),
            const SizedBox(width: 10),
            Expanded(child: Text('${l.title} v${_vm.published!.version} is live.', key: const ValueKey('publish_done')).large().semiBold()),
          ]),
          const SizedBox(height: 8),
          const Text('It shows in search and on your listings page. People can get it for free and add it to their '
                  'projects from Lumina Studio.')
              .muted(),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            PrimaryButton(key: const ValueKey('publish_view_listing'), onPressed: () => context.go('/listings/${l.slug}'), child: const Text('View listing')),
            OutlineButton(key: const ValueKey('publish_my_listings'), onPressed: () => context.go('/my/listings'), child: const Text('My listings')),
          ]),
        ]),
      ),
    ]);
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current, required this.steps});
  final PublishStep current;

  /// The steps in the order the flow visits them (a plugin's package comes
  /// first).
  final List<PublishStep> steps;

  @override
  Widget build(BuildContext context) {
    final at = steps.indexOf(current);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (i, s) in steps.indexed)
          Container(
            key: ValueKey('publish_step_${s.name}'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: s == current ? MarketColors.selectionBg : MarketColors.card,
              border: Border.all(color: s == current ? MarketColors.primary : MarketColors.border),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < at ? MarketColors.success : s == current ? MarketColors.primary : MarketColors.secondary,
                ),
                child: i < at
                    ? const Icon(LucideIcons.check, size: 11, color: MarketColors.primaryForeground)
                    : Text('${i + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MarketColors.primaryForeground)),
              ),
              const SizedBox(width: 8),
              Text(s.label, style: TextStyle(fontSize: 12, color: s == current ? MarketColors.accentForeground : MarketColors.secondaryForeground)),
            ]),
          ),
    ]);
  }
}
