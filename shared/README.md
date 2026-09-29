[Türkçe](README.tr.md)

# lumina_marketplace_shared

The code shared by the Lumina Marketplace server, its web front end and Lumina Studio. Pure Dart (depends on `http` and `yaml` only):

- DTOs for listings, versions, users, the library, reports, the audit log and install manifests;
- the free-license catalogue and license detection;
- listing categories;
- install-path helpers (`installFolderName`, `isSafeRelativePath`);
- the game template format (`checkGameTemplate`, `GameTemplateManifest`, `GameTemplateKeys`, `kGameTemplateFormatVersion`);
- the plugin package format (`checkPluginPackage`, `PluginPackageInfo`, `detectLicenseText`, `changelogSection`);
- `MarketplaceClient`, the HTTP client for the whole API.

```yaml
dependencies:
  lumina_marketplace_shared:
    git:
      url: https://github.com/LuminaGame/marketplace.git
      path: shared
```

## Using the client

```dart
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

final client = MarketplaceClient(baseUrl: Uri.parse('http://127.0.0.1:8787/'));

final page = await client.search(const SearchQuery(q: 'barrel', category: ListingCategory.model));
for (final listing in page.items) {
  print('${listing.title} (${listing.slug}), ${listing.downloadCount} downloads');
}

await client.logIn(login: 'me@example.com', password: password);
final listing = page.items.first;
await client.getListing(listing.id);                      // "Get (Free)": adds it to the library

final manifest = await client.manifest(listing.id, listing.latestVersion!.version);
for (final file in manifest.files) {
  if (!isSafeRelativePath(file.target)) continue;          // installers check paths again
  final bytes = await client.downloadUrl(file.url);
  // verify file.sha256, then write bytes to <install root>/<file.target>
}
```

The client also covers sign-up, sessions (`refresh`, `restoreSession`, `logOut`), profiles, publishing (`createListing`, `upload`, `publishVersion`, screenshots, `unlist` / `relist`), the library, reports and the moderation endpoints. API errors are thrown as `MarketplaceException`, carrying the server's error `code`.

## Licenses

| Kind | Allowed licenses |
|---|---|
| content | `CC0-1.0`, `CC-BY-4.0`, `CC-BY-SA-4.0` |
| code | `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `MPL-2.0`, `Zlib` |

Anything else ("Proprietary", CC NonCommercial or NoDerivatives, ...) is refused.

## Game template format (format 1)

A `game_template` version is a Lumina project folder that Lumina Studio's launcher turns into a new project. It installs to `templates/<Folder>/` in the editor's config folder.

```
<Folder>/                  optional single top-level folder; it names the install folder (no leading dot)
  template.json            {"format": 1, "title": "Arena", "description": "...", "engine_version": "0.0.1",
                            "thumbnail": "thumbnail.png"}   title required; the other keys are strings
  thumbnail.png | .jpg     optional card image (else thumbnail.* / screenshot.*)
  <source>.lmproject       the source project's manifest (settings, input, maps and modes)
  pubspec.yaml             optional: dependencies and asset folders
  contents/**              required: levels (.lmas) and assets
  lib/**                   optional: the project's Dart code
```

A broken template is refused with `422 invalid_template`; `details` holds the first problem's `problem` code and archive `path`, plus every problem in `problems`:

| `problem` | When |
|---|---|
| `missing_contents` | no file under `contents/` |
| `no_manifest` | neither `template.json` nor a `.lmproject` at the template root |
| `manifest_no_title` / `manifest_invalid` | `template.json` without a non-empty `title`; not a JSON object, a non-string key, `format` other than 1, or a thumbnail that is not an image |
| `thumbnail_missing` | the `thumbnail` named in `template.json` is not in the archive |
| `multiple_projects` / `project_invalid` | more than one root `.lmproject`; one that is not a Lumina project manifest (no `project_name`) |
| `excluded_path` | files under `android/ ios/ linux/ macos/ windows/ web/` or `build/` at the template root, or any `.dart_tool/` |
| `top_folder_invalid` | the single top-level folder starts with a dot |
| `pubspec_invalid` / `path_dependency` | a `pubspec.yaml` that is not a YAML map or has a bad `name:`; a path dependency Studio cannot resolve |

**Path dependencies.** Studio points the `lumina:` dependency at the local engine when it creates the project, so `lumina` may be a path dependency (under `dependencies:`, written as `lumina:` with `path: ...` on the next line). Any other path dependency must be a vendored copy inside the template, such as `packages/my_utils` with its `pubspec.yaml` in the archive; a vendored package follows the same rule and cannot depend on `lumina` by path. Hosted, git and SDK dependencies are left to `flutter pub get`. `.lmproject` and `pubspec.yaml` need no license; `.lmas` needs the content license and `.dart` the code license, so a game template always declares both.

## Plugin package format

A `plugin` version is a Lumina plugin folder, zipped as it is. Lumina Studio installs it to `plugins/<name>/` and loads `plugins/<name>/<name>.lmplugin`; the marketplace fills the listing from the same manifest.

```
<name>/                    optional single top-level folder; it must be named <name>
  <name>.lmplugin          {"name", "friendly_name", "version", "description", "category", "authors",
                            "engine_version", "modules", ..., "license": "MIT", "changelog": "CHANGELOG.md"}
  LICENSE | COPYING        optional license text (.md / .txt too)
  CHANGELOG.md             optional; "## 1.0.0" or "## [1.0.0] - 2026-09-01" sections
  pubspec.yaml, lib/**, resources/**
```

The publish flow maps the manifest to the listing: title from `friendly_name` (else `name`), description from `description`, tags from `category` plus `plugin`, engine version from the lower bound of `engine_version`, version from `version`, and release notes from the version's `CHANGELOG.md` section.

**License**: the optional `license` key (an allow-listed SPDX id, or one content and one code license joined by `AND`, e.g. `"CC-BY-4.0 AND MIT"`), else a root license text the server recognises (an `SPDX-License-Identifier:` line or the standard wording of an allow-listed license). A declared license is fixed for the version. `license` and `changelog` are read by the marketplace only; Lumina's plugin loader keeps them as extra keys.

Allowed besides media types and source files: `.gitignore`, `.gitattributes`, `.metadata`, `.pubignore`, `pubspec.lock`, `analysis_options.yaml`, `LICENSE` / `LICENCE` / `COPYING` / `NOTICE` / `AUTHORS`. Broken packages are refused with `422 invalid_plugin`:

| `problem` | When |
|---|---|
| `no_manifest` / `multiple_manifests` | no `<name>.lmplugin` at the package root; more than one |
| `manifest_invalid` | not a JSON object, no `name`, a non-string key |
| `name_invalid` / `name_mismatch` | `name` is not a Dart package name; it differs from the file's basename |
| `top_folder_mismatch` | the single top folder is not named `<name>` |
| `version_invalid` / `engine_version_invalid` | `version` is not `X.Y.Z`; `engine_version` is not a version constraint |
| `license_unknown` | `license` names an id off the allow-list, an `OR` / `WITH` expression, or two licenses of one kind |
| `license_not_free` | no `license` key and the license text is not free ("All rights reserved", NonCommercial, NoDerivatives) |
| `license_conflict` | the license text is a different (or non-free) license than the one `license` declares |
| `changelog_missing` | `changelog` names a file that is not in the package |

At publish the version must be the manifest's (`422 version_mismatch`) and a declared license cannot be replaced (`422 license_mismatch`). The plugins repository's `tool/pack_plugin.dart` checks all of this before upload.

## Install manifest (format 1)

`GET /listings/{id}/versions/{v}/manifest` returns an `InstallManifest`: listing, version, publisher, licenses, the archive (`url`, `sha256`, `size`) and every file with its `path`, `size`, `sha256`, `url` and install `target`.

| `installKind` | `targetRoot` |
|---|---|
| `project_contents` | `contents/Marketplace/<publisher username>/<Listing>/`, relative to the project root |
| `plugin` | `plugins/<package>/`, relative to the editor's plugin folder (a single top-level folder in the archive names the package and is stripped, else the root `<package>.lmplugin` does) |
| `theme` | `themes/<listing>.json` |
| `game_template` | `templates/<Listing>/` |

Folder names go through `installFolderName`; every path passes `isSafeRelativePath` on upload, and installers should check it again.

## Tests

```bash
dart test
```

## License

GPL-3.0 (see [LICENSE](LICENSE)).
