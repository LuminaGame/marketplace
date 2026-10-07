import 'package:lumina_marketplace_shared/src/licenses.dart';

/// What a listing is. The wire name (`model`, `game_template`, …) is what the
/// API, the database and the install manifest use.
enum ListingCategory {
  model('model', 'Model', 'Models'),
  blueprint('blueprint', 'Blueprint', 'Blueprints'),
  material('material', 'Material', 'Materials'),
  texture('texture', 'Texture', 'Textures'),
  sound('sound', 'Sound', 'Sounds'),
  animation('animation', 'Animation', 'Animations'),
  gameTemplate('game_template', 'Game template', 'Game templates'),
  plugin('plugin', 'Plugin', 'Plugins'),
  theme('theme', 'Theme', 'Themes');

  const ListingCategory(this.wire, this.label, this.pluralLabel);

  final String wire;
  final String label;
  final String pluralLabel;

  static ListingCategory? tryParse(String? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }

  /// The license kinds every version of this category must declare, before
  /// looking at what the uploaded archive actually contains
  /// ([requiredLicenseKinds] adds those).
  Set<LicenseKind> get baseLicenseKinds => switch (this) {
        ListingCategory.plugin => {LicenseKind.code},
        ListingCategory.gameTemplate => {LicenseKind.content, LicenseKind.code},
        _ => {LicenseKind.content},
      };

  /// Where Lumina Studio puts a version of this category.
  InstallKind get installKind => switch (this) {
        ListingCategory.plugin => InstallKind.plugin,
        ListingCategory.theme => InstallKind.theme,
        ListingCategory.gameTemplate => InstallKind.gameTemplate,
        _ => InstallKind.projectContents,
      };

  /// Whether a version is a zip archive (everything but themes) or a single
  /// `.json` file (themes).
  bool get acceptsJson => this == ListingCategory.theme;

  /// Whether versions get a preview model for the listing page's 3D view.
  bool get hasModelPreview => this == ListingCategory.model;
  bool get acceptsZip => this != ListingCategory.theme;
}

/// The install destination family of a listing version (see the install
/// manifest's `installKind`).
enum InstallKind {
  /// Into the open project under `contents/Marketplace/<Publisher>/<Listing>/`.
  projectContents('project_contents'),

  /// Into the editor's plugin install dir under `<package>/`.
  plugin('plugin'),

  /// Into the editor themes dir as `<file>.json`.
  theme('theme'),

  /// Into the launcher's template list under `<slug>/`.
  gameTemplate('game_template');

  const InstallKind(this.wire);
  final String wire;

  static InstallKind? tryParse(String? wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

/// The license kinds a version needs: the category's base kinds plus the kinds
/// detected in the uploaded files ([detectedKinds], computed by the server from
/// file extensions — `.dart` is code, `.glb` is content, …).
Set<LicenseKind> requiredLicenseKinds(
  ListingCategory category,
  Iterable<LicenseKind> detectedKinds,
) =>
    {...category.baseLicenseKinds, ...detectedKinds};
