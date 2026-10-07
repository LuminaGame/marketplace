[Türkçe](README.tr.md)

# lumina_marketplace_web

The Lumina Marketplace web front end: a Flutter web app built with [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) (the same version and palette as Lumina Studio) and `go_router`, talking to the server through `MarketplaceClient` from the shared package.

| Route | Page |
|---|---|
| `/` | home: featured and newest listings |
| `/search` | search and filters (category, license kind, license, engine version, free only, sort) |
| `/listings/:slug` | listing page: screenshots or the 3D view, versions, licenses, "Get (Free)", report |
| `/login`, `/signup`, `/profile` | accounts |
| `/publish`, `/publish/:id` | the publish flow: listing details, archive upload, licenses and the ownership attestation; plugin listings are filled from the package's `.lmplugin` |
| `/my/listings`, `/my/library` | the user's listings and the listings they got |
| `/moderation` | reports, unlist / restore / feature, suspensions, the audit log (moderators) |

## Requirements

- Flutter SDK (Dart `^3.12.0`) with web support.
- A checkout of the [lumina](https://github.com/LuminaGame/lumina) repository next to this repository (`../lumina`): `lumina` and `flutter_filament` are path dependencies (`../../lumina/lumina`, `../../lumina/flutter_filament`), used by the 3D view. A gitignored root `pubspec_overrides.yaml` can point them elsewhere.
- For the 3D view: flutter_filament's WebAssembly module (`flutter_filament/web/flutter_filament.{js,wasm}`), built in the lumina repository.
- A running marketplace server (see the [repository README](../README.md#running-it-locally)).

## Building and running

```bash
dart run tool/sync_filament_module.dart                 # copies the wasm module into web/filament/ (gitignored)
flutter build web --release --no-web-resources-cdn      # -> build/web
```

The server serves the build at `/` when started with `MARKETPLACE_WEB_DIR=../web/build/web`; this is the production setup, with the API on the same origin. `melos run build:web` builds from the repository root.

For development with hot reload against a separately running server:

```bash
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5000 \
  --dart-define=MARKETPLACE_API=http://127.0.0.1:8787
```

Without `MARKETPLACE_API` the app talks to the origin it was served from. Use the same host name for the app and the API, otherwise the refresh cookie becomes cross-site. The access token is kept in memory only; a reload restores the session from the httpOnly refresh cookie.

## The 3D view

Model listing pages have an **Images / 3D view** toggle when the version has a preview model. The 3D view runs the Lumina engine in the browser (`package:lumina_widgets/lumina_game.dart`, the engine runtime plus its game widget, on flutter_filament's WebGL2 WebAssembly module) and renders the preview GLB the server derived from the archive: drag to orbit, right-drag or Shift+drag to pan, wheel to zoom, double-click or **Reset view** to re-frame, and **Fullscreen**. The runtime is a deferred library and the wasm module (`filament/flutter_filament.{js,wasm}`) loads only when someone opens the 3D view; the server serves it as `application/wasm` with an ETag.

## Tests

```bash
flutter test                                                        # or: melos run test:flutter
dart test integration_test/smoke/marketplace_web_smoke_test.dart    # browser smoke
```

The widget tests run against a real seeded server started in `setUpAll`, with real meshes from `../test-assets` (or `LUMINA_TEST_ASSETS`) and the `lumina_plugin_pcg` folder of a plugins checkout at `../../plugins` (or `LUMINA_PLUGINS_DIR`).

The smoke test is a plain Dart test: it builds the release app (`MKT_SKIP_WEB_BUILD=1` reuses `build/web`, `MKT_WEB_DIR` points at another build), starts a seeded server that serves it, and drives Chrome (or Chromium) with puppeteer through browsing, searching, accounts, publishing, the plugin publish flow and the 3D view. Evidence goes to `build/smoke_artifacts/` (PNG screenshots, a WebM walkthrough, a sidecar JSON per artifact) and `build/smoke_report.html`. `--plain-name 'listing 3D view'` runs the 3D view scenario alone.

## License

GPL-3.0 (see [LICENSE](LICENSE)).
