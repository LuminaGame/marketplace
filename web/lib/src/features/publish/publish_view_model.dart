import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/platform/files.dart';

enum PublishStep {
  details('Details'),
  screenshots('Screenshots'),
  upload('Upload'),
  licenses('Licenses'),
  publish('Publish');

  const PublishStep(this.label);
  final String label;
}

/// The publish flow: create the listing → screenshots → upload the version →
/// pick licenses (one per kind the version contains) → tick the ownership
/// attestation → publish. It runs the same license check as the API
/// ([licenseProblems]) so it refuses exactly what the server would.
class PublishViewModel extends ChangeNotifier {
  PublishViewModel(this.client, this.files, {this.listingId});

  final MarketplaceClient client;
  final FileSource files;

  /// Set for "publish a new version" of an existing listing.
  final String? listingId;

  PublishStep step = PublishStep.details;
  bool loading = true;
  bool busy = false;
  String? error;
  Terms? terms;
  Listing? listing;
  ListingVersion? published;

  // Details.
  ListingCategory? category;
  final title = TextEditingController();
  final description = TextEditingController();
  final tags = TextEditingController();
  final engineVersion = TextEditingController(text: '0.0.1');

  /// Shown disabled: publishing is free only for now.
  final price = TextEditingController(text: 'Free');

  // Upload.
  UploadInfo? upload;

  // Licenses.
  String? contentLicense;
  String? codeLicense;

  // Publish.
  bool attested = false;
  final version = TextEditingController(text: '1.0.0');
  final releaseNotes = TextEditingController();

  bool get isNewVersion => listingId != null;

  /// The package the upload holds, when it is a plugin package.
  PluginPackageInfo? get plugin => upload?.plugin;

  /// Whether this is the plugin flow of a new listing: the package comes
  /// first and fills the details.
  bool get pluginFirst => category == ListingCategory.plugin && !isNewVersion;

  /// The steps in the order this flow visits them.
  List<PublishStep> get steps => pluginFirst
      ? const [PublishStep.upload, PublishStep.details, PublishStep.screenshots, PublishStep.licenses, PublishStep.publish]
      : [for (final s in PublishStep.values) if (!(isNewVersion && s == PublishStep.details)) s];

  /// The step before [s], or null at the start (a new version starts at
  /// Upload).
  PublishStep? stepBefore(PublishStep s) {
    // Plugin first: Back from the package goes to the category.
    if (pluginFirst && s == PublishStep.upload) return PublishStep.details;
    final i = steps.indexOf(s);
    if (i <= 0 || (isNewVersion && s == PublishStep.upload)) return null;
    return steps[i - 1];
  }

  PublishStep? _stepAfter(PublishStep s) {
    final i = steps.indexOf(s);
    return i < 0 || i + 1 >= steps.length ? null : steps[i + 1];
  }

  /// The license [kind] the package declares, which the version must use.
  String? declaredLicense(LicenseKind kind) => plugin?.license?[kind];

  /// The license kinds this version needs: the category's plus what the
  /// uploaded files contain.
  Set<LicenseKind> get requiredKinds =>
      category == null ? const {} : requiredLicenseKinds(category!, upload?.detectedLicenseKinds ?? const {});

  LicenseSelection get selection => LicenseSelection(
        content: requiredKinds.contains(LicenseKind.content) ? contentLicense : null,
        code: requiredKinds.contains(LicenseKind.code) ? codeLicense : null,
      );

  List<LicenseProblem> get problems => licenseProblems(requiredKinds, selection);

  Future<void> init() async {
    try {
      terms = await client.terms();
      if (listingId != null) {
        final l = await client.listing(listingId!);
        if (l.publisher.id != client.currentUser?.id) throw const MarketplaceException(403, 'forbidden', 'Only the publisher can publish new versions.');
        listing = l;
        category = l.category;
        title.text = l.title;
        final latest = l.latestVersion;
        if (latest != null) {
          final parts = latest.version.split('.').map(int.parse).toList();
          version.text = '${parts[0]}.${parts[1] + 1}.0';
          contentLicense = latest.licenses.content;
          codeLicense = latest.licenses.code;
        }
        step = PublishStep.upload;
      }
    } catch (e) {
      error = errorText(e);
    }
    loading = false;
    notifyListeners();
  }

  void _fail(String message) {
    error = message;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() body) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      error = errorText(e);
    }
    busy = false;
    notifyListeners();
  }

  void setCategory(ListingCategory? c) {
    if (listing?.latestVersion != null) return;
    category = c;
    if (upload != null && c != null && c.acceptsJson != (upload!.kind == 'json')) upload = null;
    // A plugin listing starts with its package.
    if (c == ListingCategory.plugin && upload?.plugin == null) upload = null;
    if (pluginFirst && listing == null && upload == null) step = PublishStep.upload;
    notifyListeners();
  }

  void goTo(PublishStep s) {
    error = null;
    step = s;
    notifyListeners();
  }

  List<String> get _tagList =>
      tags.text.split(RegExp(r'[,\s]+')).map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toList();

  /// Details → creates (or updates) the draft listing.
  Future<void> submitDetails() async {
    if (category == null) return _fail('Pick a category.');
    // Plugin first: the package fills the details, so it comes first.
    if (pluginFirst && plugin == null) return goTo(PublishStep.upload);
    if (title.text.trim().length < 3) return _fail('The title needs at least 3 characters.');
    await _run(() async {
      if (listing == null) {
        listing = await client.createListing(NewListing(
          category: category!,
          title: title.text.trim(),
          description: description.text,
          tags: _tagList,
          engineVersion: engineVersion.text.trim(),
        ));
      } else {
        listing = await client.updateListing(listing!.id,
            title: title.text.trim(), description: description.text, tags: _tagList, engineVersion: engineVersion.text.trim(),
            category: listing!.latestVersion == null ? category : null);
      }
      step = _stepAfter(PublishStep.details)!;
    });
  }

  Future<void> addScreenshot() => _run(() async {
        final picked = await files.pick(extensions: const ['png', 'jpg', 'jpeg', 'webp']);
        if (picked == null) return;
        final lower = picked.name.toLowerCase();
        listing = await client.addScreenshot(listing!.id, picked.bytes,
            contentType: lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      });

  Future<void> removeScreenshot(int index) => _run(() async {
        listing = await client.removeScreenshot(listing!.id, index);
      });

  /// Picks the version file and uploads it. The server validates it with the
  /// listing's category, so a game template that breaks the template format
  /// is refused here with the message publishing would give.
  Future<void> chooseArchive() => _run(() async {
        final json = category?.acceptsJson ?? false;
        final picked = await files.pick(extensions: json ? const ['json'] : const ['zip']);
        if (picked == null) return;
        upload = null;
        upload = await client.upload(picked.bytes, fileName: picked.name, category: category);
        if (upload?.plugin case final p?) _applyPlugin(p);
      });

  /// Fills the flow from what a plugin package declares: the
  /// details (a new listing), the version, its release notes and the declared
  /// licenses.
  void _applyPlugin(PluginPackageInfo p) {
    if (listing?.latestVersion == null) {
      title.text = p.title;
      description.text = p.description;
      tags.text = p.tags.join(', ');
      if (p.minEngineVersion case final e?) engineVersion.text = e;
    }
    version.text = p.version;
    releaseNotes.text = p.releaseNotes ?? '';
    if (p.license case final l?) {
      if (l.content != null) contentLicense = l.content;
      if (l.code != null) codeLicense = l.code;
    }
  }

  void continueFromUpload() {
    if (category == ListingCategory.plugin && plugin == null) {
      return _fail('Upload the plugin package (a .zip of the plugin folder) first.');
    }
    if (upload == null) return _fail('Upload the ${category?.acceptsJson ?? false ? '.json theme' : '.zip archive'} first.');
    // Plugin first: on to the details the package filled.
    goTo(_stepAfter(PublishStep.upload)!);
  }

  /// Screenshots → the next step (Upload, or Licenses when the package came
  /// first).
  void continueFromScreenshots() => goTo(_stepAfter(PublishStep.screenshots)!);

  void setLicense(LicenseKind kind, String? id) {
    if (declaredLicense(kind) != null) return; // the package's own
    if (kind == LicenseKind.content) {
      contentLicense = id;
    } else {
      codeLicense = id;
    }
    error = null;
    notifyListeners();
  }

  /// Licenses → the attestation step, only with one license per needed kind.
  void continueFromLicenses() {
    final p = problems;
    if (p.isNotEmpty) return _fail(p.map((e) => e.message).join(' '));
    goTo(PublishStep.publish);
  }

  void setAttested(bool value) {
    attested = value;
    error = null;
    notifyListeners();
  }

  Future<void> publish() async {
    if (problems.isNotEmpty) return _fail(problems.map((e) => e.message).join(' '));
    if (!attested) return _fail('Tick the ownership attestation to publish: "${terms?.attestationStatement}"');
    await _run(() async {
      published = await client.publishVersion(
        listing!.id,
        NewVersion(
          version: version.text.trim(),
          uploadId: upload!.id,
          licenses: selection,
          attestation: attested,
          termsVersion: terms!.version,
          releaseNotes: releaseNotes.text,
        ),
      );
      listing = await client.listing(listing!.id);
    });
  }

  @override
  void dispose() {
    for (final c in [title, description, tags, engineVersion, price, version, releaseNotes]) {
      c.dispose();
    }
    super.dispose();
  }
}
