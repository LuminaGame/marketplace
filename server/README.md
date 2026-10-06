[Türkçe](README.tr.md)

# lumina_marketplace_server

The Lumina Marketplace API: accounts, listings with versioned uploads, free licenses, the ownership attestation, moderation, search, the library and install manifests. A Dart [`shelf`](https://pub.dev/packages/shelf) server with:

- SQLite (via `package:sqlite3`, FTS5 full-text search) behind repository interfaces;
- a content-addressed blob store on disk for archives, screenshots, avatars and preview models;
- argon2id password hashes, 15-minute HS256 JWT access tokens and rotating refresh tokens (also set as an httpOnly cookie);
- `/openapi.yaml` and a `/docs` reference page, and optionally the built web front end at `/`.

## Running

`MARKETPLACE_JWT_SECRET` (at least 32 random characters) must come from the environment; it is never defaulted or committed. See `.env.example` at the repository root.

```bash
export MARKETPLACE_JWT_SECRET=$(openssl rand -hex 32)
dart run bin/server.dart            # http://127.0.0.1:8787
dart run bin/server.dart --seed     # plus the sample CC0 listings and the lumina / moderator accounts
dart run tool/seed.dart             # seed without starting the server
```

Every other setting has a default and is read from `MARKETPLACE_*` variables (host, port, data paths, base URL, web folder, CORS origins, upload and preview limits, proxy trust); the table is in the [repository README](../README.md#configuration). Data goes to `data/marketplace.db` and `data/storage/` (gitignored).

With Docker, build from the repository root: `docker compose up --build` uses `server/Dockerfile`, which compiles the server with `dart build cli` (bundling a verified SQLite with FTS5) and serves on port 8787 with its data in a volume.

### Embedding

```dart
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';

final server = await MarketplaceServer.start(MarketplaceConfig(
  port: 0,                                  // any free port
  databasePath: 'build/tmp/marketplace.db',
  storageDir: 'build/tmp/storage',
  jwtSecret: secretFromEnvironment,         // >= 32 characters
));
print(server.url);                          // http://127.0.0.1:<port>/
await server.close();
```

`MarketplaceConfig.fromEnvironment()` builds the configuration the way `bin/server.dart` does; `seedSampleContent(server.services, testAssetsDir: ...)` publishes the sample listings.

## API overview

All routes are under `/api/v1`; errors are `{"error": {"code", "message", "details"}}`. [`openapi.yaml`](openapi.yaml) lists every route with its bodies, and a test keeps it in step with the route table.

- **Auth**: `POST /auth/signup`, `/auth/login` (email or username), `/auth/refresh`, `/auth/logout`; `GET/PATCH /me`, `POST /me/avatar`, `/me/password`. Refresh rotates the refresh token (httpOnly cookie `lm_refresh`, `Path=/api/v1/auth`). Access tokens carry their session id, so log-out, a password change or a suspension revokes them at once. Ten failed log-ins a minute per IP or per login give `429` with `Retry-After`.
- **Catalogue**: `GET /listings` (`q`, `category`, `licenseKind`, `license`, `engineVersion`, `free`, `publisher`, `featured`, `sort=relevance|newest|downloads|name`, `page`, `pageSize`), `GET /listings/{id|slug}`, `/licenses`, `/terms`, `/categories`, `/users/{username}`, `/media/{sha256}`, `/listings/{id|slug}/versions/{v}/preview.glb`.
- **Publishing**: `POST /listings` (a draft; `priceCents` must be 0) → `POST /uploads?fileName=x.zip` (raw body) → `POST /listings/{id}/versions` with `{version, uploadId, contentLicense, codeLicense, attestation: {accepted: true, termsVersion}}`. Also `PATCH /listings/{id}`, screenshots, `/unlist`, `/relist`, `GET /me/listings`.
- **Library and install**: `POST /listings/{id}/get` ("Get (Free)"), `GET /library`, `GET /listings/{id}/versions/{v}/manifest`, `/download` (the exact uploaded bytes; counts a download), `/files/{path}`.
- **Crash reports**: `POST /crash-reports` (no account; per-IP limit `MARKETPLACE_CRASH_REPORTS_PER_MINUTE`, default 10): Lumina Studio's crash report screen files `{error, kind, stackTrace, description, email, release, commit, platform, gpu, logTail, …}` as a JSON file under `<storage>/crash-reports/<yyyy>/<mm>/<id>.json` with the hashed IP; answers `{id, receivedAt}`.
- **Moderation**: `POST /listings/{id}/reports`; for moderators `GET /moderation/reports`, `POST /moderation/reports/{id}/resolve`, `/moderation/listings/{id}/unlist|restore|feature`, `/moderation/users/{username}/suspend|unsuspend`, `GET /moderation/audit`; for admins `POST /admin/users/{username}/role`.

## Uploads and validation

Every upload is checked before anything is stored: no `..`, absolute, drive-letter or backslash paths, no symlinks, allowed file types only, and size and zip-bomb limits (`MARKETPLACE_MAX_UPLOAD_MB`, 256 MB by default). `?category=<listing category>` also runs that category's archive rules on upload:

- `game_template`: the Lumina project format, refused with `422 invalid_template`;
- `plugin`: the `.lmplugin` package format, refused with `422 invalid_plugin`; the parsed manifest comes back as `plugin`. Folders that tools generate (`.dart_tool/`, `.git/`, `.idea/`, `.vscode/` anywhere, `build/` at the package root) are left out, the archive is repacked without them, and the response reports them as `skippedPaths` / `skippedFileCount`.

The same rules run again at publish. The formats and problem codes are documented in the [shared package](../shared/README.md), which implements them.

**Licenses.** Each version declares one allow-listed license per kind of work it contains: the kinds the category requires (plugins need code; game templates need both; everything else needs content) plus what the files contain (`.dart`, `.js`, shader sources are code; meshes, images, audio, `.lmas` are content). Anything off the list is refused with `422 license_unknown`.

**Ownership attestation.** Publishing requires `attestation.accepted` against the current terms version (`GET /terms`). The attestation (user, time, salted IP hash, terms version, listing, version) is stored immutably: SQLite triggers refuse updates and deletes, as they do for the audit log. Suspending a publisher unlists all of their listings, suspends the account and revokes every session and token, each step audited.

## Preview models

When an archive is uploaded, the server derives the version's preview model for the web front end's 3D view: the largest self-contained glTF in it (a `.glb`, a `.gltf` whose external buffers and images are packed into one GLB, or a mesh `.lmas` payload) within `MARKETPLACE_MAX_PREVIEW_MB`. Model listings expose it as `previewModelUrl` (plus its SHA-256, size and source on the version). It is served publicly like screenshots (`model/gltf-binary`, an ETag, a day of caching), is not a download and needs no library entry. Versions published before previews existed are backfilled at start-up.

## Tests

```bash
dart test                        # or: melos run test:dart from the repository root
dart run tool/e2e_smoke.dart     # end-to-end smoke -> build/smoke_artifacts/e2e_smoke.{log,json}
```

The tests use real temporary SQLite databases and storage folders and real servers on ephemeral ports. Some read real meshes from `../test-assets` (or `LUMINA_TEST_ASSETS`) the `lumina_plugin_pcg` folder of a plugins checkout at `../../plugins` (or `LUMINA_PLUGINS_DIR`), and the preview tests a lumina checkout at `../../lumina` (or `LUMINA_ENGINE_DIR`).

The seed screenshots (`seed/screenshots/*.jpg`) are neutral placeholders written by `tool/make_seed_placeholders.py` (Pillow): the seed models come from the private test-assets checkout. With test-assets and Blender at hand, `tool/render_seed_screenshots.py` renders the real ones locally (Cycles on the CPU).

## License

GPL-3.0 (see [LICENSE](LICENSE)).
