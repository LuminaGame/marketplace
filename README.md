[Türkçe](README.tr.md)

# Lumina Marketplace

The asset marketplace of the [Lumina](https://github.com/LuminaGame/lumina) game engine. People publish and get models, Blueprints, materials, textures, sounds, animations, game templates, plugins and editor themes. Lumina Studio installs what users get through the same API.

Publishing is free only for now: every version declares free licenses for the content and/or code it contains, and the publisher confirms that they own the work or have the right to publish it.

| Package | What it is |
|---|---|
| [`server/`](server/) | `lumina_marketplace_server`: the Dart `shelf` API. SQLite with FTS5 search, a content-addressed blob store on disk, argon2id passwords, JWT access tokens with rotating refresh tokens, moderation and an audit log. |
| [`shared/`](shared/) | `lumina_marketplace_shared`: DTOs, the free-license catalogue, listing categories, install-path helpers, the game template and plugin package rules, and `MarketplaceClient`. Pure Dart; used by the web front end and by Lumina Studio. |
| [`web/`](web/) | `lumina_marketplace_web`: the Flutter web front end (shadcn_flutter). Browse and search, listing pages with a 3D view, accounts, the publish flow, My listings, My library, moderation. |

## Requirements

- Dart SDK for the server and the shared package; Flutter SDK (Dart `^3.12.0`) for the web front end and for the workspace as a whole.
- [melos](https://melos.invertase.dev/) 7 (a dev dependency; `dart pub global activate melos`, or `dart run melos`).
- The web front end runs the Lumina engine in the browser for its 3D view, so it takes `lumina` and `flutter_filament` as path dependencies from a checkout of the [lumina](https://github.com/LuminaGame/lumina) repository next to this one (`../lumina`). The 3D view also needs flutter_filament's WebAssembly module, which is built in the lumina repository.
- Optional: Docker with Compose; the [test-assets](https://github.com/LuminaGame/test-assets) repository (Git LFS) for the sample listings and tests.

## Setup

```
<dir>/
  lumina/        https://github.com/LuminaGame/lumina
  tools/         https://github.com/LuminaGame/tools
  plugins/       https://github.com/LuminaGame/plugins (used by the plugin publish tests)
  marketplace/   this repository
  test-assets/   https://github.com/LuminaGame/test-assets
```

```bash
git clone https://github.com/LuminaGame/marketplace.git
cd marketplace
ln -s ../test-assets test-assets      # Windows: mklink /J test-assets ..\test-assets
dart pub get                          # resolves server, shared and web as one pub workspace
```

The repository is a Dart pub workspace: the root `pubspec.yaml` lists `server`, `shared` and `web` under `workspace:` and each has `resolution: workspace`. The engine packages the web front end pulls in depend on the [tools](https://github.com/LuminaGame/tools) packages through git; to use your sibling checkouts instead, add a gitignored `pubspec_overrides.yaml` at the root:

```yaml
dependency_overrides:
  flutter_assimp:
    path: ../tools/flutter_assimp
  flutter_riglogic:
    path: ../tools/flutter_riglogic
  flutter_gstreamer:
    path: ../tools/flutter_gstreamer
```

## Running it locally

### Secrets

Nothing secret is committed. The server needs `MARKETPLACE_JWT_SECRET` (at least 32 random characters) from the environment. Copy `.env.example` to `.env` (gitignored) and fill it in; `docker compose` reads `.env` automatically, for `dart run` export the variables yourself:

```bash
cp .env.example .env
# set MARKETPLACE_JWT_SECRET, e.g. to the output of: openssl rand -hex 32
set -a; . ./.env; set +a
```

### API only

```bash
cd server
dart run bin/server.dart --seed          # http://127.0.0.1:8787
```

(`melos run serve` does the same from the root.) `--seed` publishes the sample CC0 listings on first start: Barrel, Access Cards, AC Units, Banana Bunch, Chair and Jerry Can (zips of the meshes in `test-assets/Props/`, which are only read; `MARKETPLACE_TEST_ASSETS` points elsewhere) and the "Lumina Ember" editor theme. It also creates two accounts, the admin publisher `lumina` and `moderator`, with the passwords from `MARKETPLACE_SEED_ADMIN_PASSWORD` / `MARKETPLACE_SEED_MODERATOR_PASSWORD`, or generated ones printed once in the `seed accounts` log line. `dart run tool/seed.dart` seeds without starting the server.

- API: `http://127.0.0.1:8787/api/v1/...`, reference page at `/docs`, OpenAPI spec at `/openapi.yaml`
- Data: `server/data/marketplace.db` and `server/data/storage/` (gitignored)

### With the web front end

```bash
cd web
dart run tool/sync_filament_module.dart                 # copies flutter_filament's wasm module into web/filament/
flutter build web --release --no-web-resources-cdn      # -> web/build/web
cd ../server
MARKETPLACE_WEB_DIR=../web/build/web dart run bin/server.dart --seed
```

This is also the production setup: the server serves the built app at `/` (client-side routes fall back to `index.html`), so the httpOnly refresh cookie is same-origin with the API.

For development with hot reload, run the server as above and:

```bash
cd web
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5000 \
  --dart-define=MARKETPLACE_API=http://127.0.0.1:8787
```

Use the same host name (`127.0.0.1`) for both; mixing `localhost` and `127.0.0.1` makes the refresh cookie cross-site. The default CORS policy allows any `127.0.0.1` / `localhost` port with credentials. The access token lives only in memory; a reload restores the session from the cookie.

### Docker

```bash
cp .env.example .env                                   # set MARKETPLACE_JWT_SECRET
(cd web && flutter build web --release)
docker compose up --build                              # API + web front end + seed on http://127.0.0.1:8787
```

The compose file fails fast when `MARKETPLACE_JWT_SECRET` is not set. Data lives in the `marketplace-data` volume; `LUMINA_TEST_ASSETS` in `.env` selects the host folder mounted for the seed (default `./test-assets`).

### Configuration

| Variable | Default | |
|---|---|---|
| `MARKETPLACE_JWT_SECRET` | required | HS256 key for access tokens; also salts stored IP hashes |
| `MARKETPLACE_HOST` / `MARKETPLACE_PORT` | `127.0.0.1` / `8787` | port `0` picks a free port |
| `MARKETPLACE_DATA_DIR` | `data` | parent of the two below |
| `MARKETPLACE_DB` / `MARKETPLACE_STORAGE` | `data/marketplace.db` / `data/storage` | SQLite file, blob folder |
| `MARKETPLACE_BASE_URL` | `http://<host>:<port>` | an `https` URL makes the refresh cookie `Secure` |
| `MARKETPLACE_WEB_DIR` | none | serve a `flutter build web` output at `/` |
| `MARKETPLACE_CORS_ORIGINS` | `http://localhost:*,http://127.0.0.1:*` | browser origins allowed with credentials |
| `MARKETPLACE_MAX_UPLOAD_MB` | `256` | version archive limit (images: 8 MB) |
| `MARKETPLACE_MAX_PREVIEW_MB` | `32` | largest preview model a version gets; bigger means no 3D view |
| `MARKETPLACE_TRUST_PROXY` | `false` | take the client IP from `X-Forwarded-For` |
| `MARKETPLACE_TEST_ASSETS` | `../test-assets` | where `--seed` reads the sample meshes |
| `MARKETPLACE_SEED_ADMIN_PASSWORD` / `MARKETPLACE_SEED_MODERATOR_PASSWORD` | generated | seed account passwords |

## How it works

- **Listings and versions.** A listing is created as a draft, an archive is uploaded and validated, then a version is published with its licenses and the ownership attestation. The [server README](server/README.md) summarises the API; [`server/openapi.yaml`](server/openapi.yaml) has every route with its bodies.
- **Free licenses only.** Content: `CC0-1.0`, `CC-BY-4.0`, `CC-BY-SA-4.0`. Code: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `MPL-2.0`, `Zlib`. Anything else is refused.
- **Ownership attestation.** A version is only published when the uploader confirms "I own this work or have the right to publish it under the chosen license." against the current terms version. The attestation is stored immutably. Suspending a publisher unlists all of their listings, suspends the account and revokes every session, each step audited.
- **Game templates and plugins** have their own archive formats (a Lumina project folder with `template.json`; a plugin folder with its `<name>.lmplugin` manifest), checked on upload and at publish. The rules live in the shared package; see the [shared README](shared/README.md).
- **3D view.** Model listing pages can show the version's preview model (the largest self-contained glTF in the archive) rendered by the Lumina engine in the browser, on flutter_filament's WebGL2 WebAssembly module. See the [web README](web/README.md).
- **Install manifests** tell Lumina Studio where each file of a version goes (project contents, the plugin folder, themes, templates).

## Development

```bash
melos run analyze        # dart analyze over every package
melos run test           # test:dart (server, shared) then test:flutter (web)
melos run test:dart      # dart test in server and shared
melos run test:flutter   # flutter test in web
melos run format         # dart format --line-length 120
melos run format:check   # fail on unformatted code
melos run serve          # the API with the sample listings (needs MARKETPLACE_JWT_SECRET)
melos run build:web      # flutter build web --release in web/
```

Every package enables the `always_use_package_imports` lint: a file imports another file of its own package by its `package:` URI (`package:lumina_marketplace_server/src/...`), never by a relative path.

Tests use real temporary SQLite databases and storage folders, real servers on ephemeral ports and the real meshes from `test-assets/` (or `LUMINA_TEST_ASSETS`); the plugin publish tests read `lumina_plugin_pcg` from the plugins checkout at `../plugins` (or `LUMINA_PLUGINS_DIR`).

Smoke tests, with evidence written to `build/smoke_artifacts/`:

```bash
cd server && dart run tool/e2e_smoke.dart
cd web && dart test integration_test/smoke/marketplace_web_smoke_test.dart
```

`e2e_smoke.dart` starts the server and drives it through `MarketplaceClient`: sign up, publish a CC0 model, search, get it, fetch the install manifest and download every file with hash checks, publish a game template and a plugin, and see broken or non-free archives refused. The web smoke builds the release app and walks through it in Chrome with puppeteer, including the 3D view and the plugin publish flow (screenshots and a WebM per scenario with sidecar JSON, and `build/smoke_report.html`, all written with [lumina_smoke](https://github.com/LuminaGame/tools); `MKT_SKIP_WEB_BUILD=1` reuses an existing build; the 3D view scenario is skipped when flutter_filament's WebAssembly module is not built).

## License

GPL-3.0 (see [LICENSE](LICENSE)); `server/`, `shared/` and `web/` carry the same license file. Content published on a marketplace instance is licensed by its publishers under the licenses declared for each version.
