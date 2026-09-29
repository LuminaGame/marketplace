[English](README.md)

# lumina_marketplace_server

Lumina Marketplace API'si: hesaplar, version'lı upload'larıyla listing'ler, ücretsiz lisanslar, sahiplik beyanı, moderasyon, arama, library ve install manifest'leri. Şunları içeren bir Dart [`shelf`](https://pub.dev/packages/shelf) server'ı:

- repository interface'lerinin arkasında SQLite (`package:sqlite3` ile, FTS5 full-text search);
- arşivler, screenshot'lar, avatar'lar ve preview model'ler için diskte content-addressed bir blob store;
- argon2id şifre hash'leri, 15 dakikalık HS256 JWT access token'ları ve rotate edilen refresh token'lar (httpOnly cookie olarak da set edilir);
- `/openapi.yaml` ve bir `/docs` referans sayfası, isteğe bağlı olarak da `/` altında build edilmiş web front end.

## Çalıştırmak

`MARKETPLACE_JWT_SECRET` (en az 32 rastgele karakter) environment'tan gelmek zorundadır; hiçbir zaman varsayılan bir değeri yoktur ve commit'lenmez. Repo root'undaki `.env.example`'a bakın.

```bash
export MARKETPLACE_JWT_SECRET=$(openssl rand -hex 32)
dart run bin/server.dart            # http://127.0.0.1:8787
dart run bin/server.dart --seed     # ek olarak örnek CC0 listing'ler ve lumina / moderator hesapları
dart run tool/seed.dart             # server'ı başlatmadan seed eder
```

Diğer tüm ayarların varsayılanı vardır ve `MARKETPLACE_*` değişkenlerinden okunur (host, port, veri path'leri, base URL, web klasörü, CORS origin'leri, upload ve preview limitleri, proxy güveni); tablo [repo README'sinde](../README.tr.md#konfigürasyon). Veri `data/marketplace.db` ve `data/storage/` altına gider (gitignore'da).

Docker ile repo root'undan build edin: `docker compose up --build`, server'ı `dart build cli` ile derleyen (FTS5'li, doğrulanmış bir SQLite'ı bundle ederek) `server/Dockerfile`'ı kullanır ve veriyi bir volume'da tutarak 8787 port'undan servis eder.

### Gömülü kullanım

```dart
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';

final server = await MarketplaceServer.start(MarketplaceConfig(
  port: 0,                                  // boş herhangi bir port
  databasePath: 'build/tmp/marketplace.db',
  storageDir: 'build/tmp/storage',
  jwtSecret: secretFromEnvironment,         // >= 32 karakter
));
print(server.url);                          // http://127.0.0.1:<port>/
await server.close();
```

`MarketplaceConfig.fromEnvironment()` konfigürasyonu `bin/server.dart`'ın yaptığı gibi kurar; `seedSampleContent(server.services, testAssetsDir: ...)` örnek listing'leri yayınlar.

## API'ye genel bakış

Tüm route'lar `/api/v1` altındadır; hatalar `{"error": {"code", "message", "details"}}` biçimindedir. [`openapi.yaml`](openapi.yaml) her route'u body'leriyle listeler; bir test onu route tablosuyla senkron tutar.

- **Auth**: `POST /auth/signup`, `/auth/login` (email ya da kullanıcı adı), `/auth/refresh`, `/auth/logout`; `GET/PATCH /me`, `POST /me/avatar`, `/me/password`. Refresh, refresh token'ı rotate eder (httpOnly cookie `lm_refresh`, `Path=/api/v1/auth`). Access token'lar session id'lerini taşır; bu yüzden log-out, şifre değişikliği ya da suspend onları anında iptal eder. IP ya da login başına dakikada on başarısız giriş `Retry-After` ile `429` döndürür.
- **Katalog**: `GET /listings` (`q`, `category`, `licenseKind`, `license`, `engineVersion`, `free`, `publisher`, `featured`, `sort=relevance|newest|downloads|name`, `page`, `pageSize`), `GET /listings/{id|slug}`, `/licenses`, `/terms`, `/categories`, `/users/{username}`, `/media/{sha256}`, `/listings/{id|slug}/versions/{v}/preview.glb`.
- **Publishing**: `POST /listings` (draft; `priceCents` 0 olmalı) → `POST /uploads?fileName=x.zip` (raw body) → `{version, uploadId, contentLicense, codeLicense, attestation: {accepted: true, termsVersion}}` ile `POST /listings/{id}/versions`. Ayrıca `PATCH /listings/{id}`, screenshot'lar, `/unlist`, `/relist`, `GET /me/listings`.
- **Library ve kurulum**: `POST /listings/{id}/get` ("Get (Free)"), `GET /library`, `GET /listings/{id}/versions/{v}/manifest`, `/download` (yüklenen byte'ların birebir aynısı; download sayılır), `/files/{path}`.
- **Moderasyon**: `POST /listings/{id}/reports`; moderatörler için `GET /moderation/reports`, `POST /moderation/reports/{id}/resolve`, `/moderation/listings/{id}/unlist|restore|feature`, `/moderation/users/{username}/suspend|unsuspend`, `GET /moderation/audit`; admin'ler için `POST /admin/users/{username}/role`.

## Upload'lar ve doğrulama

Her upload, hiçbir şey saklanmadan önce kontrol edilir: `..`, absolute, sürücü harfli ya da backslash'li path yok, symlink yok, yalnızca izin verilen dosya tipleri, boyut ve zip-bomb limitleri (`MARKETPLACE_MAX_UPLOAD_MB`, varsayılan 256 MB). `?category=<listing kategorisi>` upload sırasında o kategorinin arşiv kurallarını da çalıştırır:

- `game_template`: Lumina proje formatı; `422 invalid_template` ile reddedilir;
- `plugin`: `.lmplugin` paket formatı; `422 invalid_plugin` ile reddedilir, parse edilen manifest `plugin` olarak döner. Tool'ların ürettiği klasörler (her yerde `.dart_tool/`, `.git/`, `.idea/`, `.vscode/`, paket root'unda `build/`) dışarıda bırakılır, arşiv onlarsız yeniden paketlenir ve response bunları `skippedPaths` / `skippedFileCount` olarak bildirir.

Aynı kurallar publish'te tekrar çalışır. Formatlar ve problem kodları, onları implement eden [shared pakette](../shared/README.tr.md) anlatılıyor.

**Lisanslar.** Her version, içerdiği her iş türü için allow-list'teki bir lisansı beyan eder: kategorinin gerektirdiği türler (plugin'ler kod ister; game template'ler ikisini de; diğer her şey content) artı dosyaların içerdikleri (`.dart`, `.js`, shader kaynakları kod; mesh'ler, görseller, ses, `.lmas` content'tir). Listede olmayan her şey `422 license_unknown` ile reddedilir.

**Sahiplik beyanı.** Publish için güncel terms version'ına (`GET /terms`) karşı `attestation.accepted` gerekir. Beyan (kullanıcı, zaman, salt'lı IP hash'i, terms version'ı, listing, version) değiştirilemez şekilde saklanır: audit log'da olduğu gibi SQLite trigger'ları update ve delete'i reddeder. Bir yayıncıyı suspend etmek tüm listing'lerini unlist eder, hesabı askıya alır ve tüm session ve token'larını iptal eder; her adım audit log'a yazılır.

## Preview model'ler

Bir arşiv yüklendiğinde server, web front end'in 3D görünümü için version'ın preview modelini çıkarır: `MARKETPLACE_MAX_PREVIEW_MB` sınırı içinde arşivdeki en büyük self-contained glTF (bir `.glb`, harici buffer ve görselleri tek bir GLB'ye paketlenen bir `.gltf`, ya da bir mesh `.lmas` payload'u). Model listing'leri bunu `previewModelUrl` olarak sunar (version'da ayrıca SHA-256'sı, boyutu ve kaynağı). Screenshot'lar gibi public servis edilir (`model/gltf-binary`, ETag, bir günlük cache); download sayılmaz ve library kaydı gerektirmez. Preview'lar eklenmeden önce yayınlanmış version'lar başlangıçta backfill edilir.

## Test'ler

```bash
dart test                        # ya da repo root'undan: melos run test:dart
dart run tool/e2e_smoke.dart     # end-to-end smoke -> build/smoke_artifacts/e2e_smoke.{log,json}
```

Test'ler gerçek geçici SQLite veritabanları ve storage klasörleri, ephemeral port'larda gerçek server'lar kullanır. Bazıları `../test-assets` (ya da `LUMINA_TEST_ASSETS`) altındaki gerçek mesh'leri `../../plugins` (ya da `LUMINA_PLUGINS_DIR`) altındaki plugins checkout'unun `lumina_plugin_pcg` klasörünü, preview test'leri de `../../lumina` (ya da `LUMINA_ENGINE_DIR`) altındaki lumina checkout'unu okur.

Seed screenshot'ları (`seed/screenshots/*.jpg`) `tool/make_seed_placeholders.py` (Pillow) ile yazılan nötr placeholder'lardır; seed modelleri private test-assets checkout'undan gelir. test-assets ve Blender elindeyse `tool/render_seed_screenshots.py` gerçeklerini yerelde render eder (CPU'da Cycles).

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)).
