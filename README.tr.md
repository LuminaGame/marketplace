[English](README.md)

# Lumina Marketplace

[Lumina](https://github.com/LuminaGame/lumina) game engine'inin asset marketplace'i. Kullanıcılar model, Blueprint, material, texture, ses, animasyon, game template, plugin ve editor teması yayınlar ve edinir. Lumina Studio, kullanıcıların edindiklerini aynı API üzerinden kurar.

Şimdilik yalnızca ücretsiz yayın yapılabiliyor: her version, içerdiği content ve/veya kod için ücretsiz lisanslar beyan eder ve yayıncı, eserin sahibi olduğunu ya da onu yayınlama hakkına sahip olduğunu onaylar.

| Paket | Ne işe yarar |
|---|---|
| [`server/`](server/) | `lumina_marketplace_server`: Dart `shelf` API'si. FTS5 aramalı SQLite, diskte content-addressed bir blob store, argon2id şifreler, rotate edilen refresh token'larla JWT access token'ları, moderasyon ve audit log. |
| [`shared/`](shared/) | `lumina_marketplace_shared`: DTO'lar, ücretsiz lisans kataloğu, listing kategorileri, kurulum path'i helper'ları, game template ve plugin paketi kuralları ve `MarketplaceClient`. Saf Dart; web front end ve Lumina Studio tarafından kullanılır. |
| [`web/`](web/) | `lumina_marketplace_web`: Flutter web front end (shadcn_flutter). Gezinme ve arama, 3D görünümlü listing sayfaları, hesaplar, publish akışı, My listings, My library, moderasyon. |

## Gereksinimler

- Server ve shared paket için Dart SDK; web front end ve workspace'in bütünü için Flutter SDK (Dart `^3.12.0`).
- [melos](https://melos.invertase.dev/) 7 (dev dependency; `dart pub global activate melos` ya da `dart run melos`).
- Web front end, 3D görünüm için Lumina engine'ini tarayıcıda çalıştırır; bu yüzden `lumina` ve `flutter_filament` paketlerini bu repo'nun yanındaki bir [lumina](https://github.com/LuminaGame/lumina) checkout'undan (`../lumina`) path dependency olarak alır. 3D görünüm ayrıca lumina repo'sunda build edilen flutter_filament WebAssembly modülüne ihtiyaç duyar.
- Opsiyonel: Compose'lu Docker; örnek listing'ler ve test'ler için [test-assets](https://github.com/LuminaGame/test-assets) repo'su (Git LFS).

## Kurulum

```
<dir>/
  lumina/        https://github.com/LuminaGame/lumina
  tools/         https://github.com/LuminaGame/tools
  plugins/       https://github.com/LuminaGame/plugins (plugin publish test'leri kullanır)
  marketplace/   bu repo
  test-assets/   https://github.com/LuminaGame/test-assets
```

```bash
git clone https://github.com/LuminaGame/marketplace.git
cd marketplace
ln -s ../test-assets test-assets      # Windows: mklink /J test-assets ..\test-assets
dart pub get                          # server, shared ve web'i tek bir pub workspace olarak resolve eder
```

Repo bir Dart pub workspace'idir: root `pubspec.yaml`, `server`, `shared` ve `web` paketlerini `workspace:` altında listeler ve her birinde `resolution: workspace` vardır. Web front end'in getirdiği engine paketleri [tools](https://github.com/LuminaGame/tools) paketlerine git üzerinden bağımlıdır; bunun yerine yan yana duran checkout'larınızı kullanmak için root'a gitignore'lu bir `pubspec_overrides.yaml` ekleyin:

```yaml
dependency_overrides:
  flutter_assimp:
    path: ../tools/flutter_assimp
  flutter_riglogic:
    path: ../tools/flutter_riglogic
  flutter_gstreamer:
    path: ../tools/flutter_gstreamer
```

## Local'de çalıştırmak

### Secret'lar

Hiçbir secret commit'lenmez. Server, environment'tan `MARKETPLACE_JWT_SECRET` (en az 32 rastgele karakter) bekler. `.env.example`'ı `.env` olarak kopyalayın (gitignore'dadır) ve doldurun; `docker compose` `.env`'i otomatik okur, `dart run` için değişkenleri kendiniz export edin:

```bash
cp .env.example .env
# MARKETPLACE_JWT_SECRET'ı ayarlayın, ör. şunun çıktısıyla: openssl rand -hex 32
set -a; . ./.env; set +a
```

### Yalnızca API

```bash
cd server
dart run bin/server.dart --seed          # http://127.0.0.1:8787
```

(Root'tan `melos run serve` aynı işi yapar.) `--seed`, ilk başlangıçta örnek CC0 listing'leri yayınlar: Barrel, Access Cards, AC Units, Banana Bunch, Chair ve Jerry Can (`test-assets/Props/` içindeki mesh'lerin zip'leri; bu klasör yalnızca okunur, `MARKETPLACE_TEST_ASSETS` başka bir yeri gösterebilir) ve "Lumina Ember" editor teması. Ayrıca iki hesap oluşturur: admin yayıncı `lumina` ve `moderator`; şifreleri `MARKETPLACE_SEED_ADMIN_PASSWORD` / `MARKETPLACE_SEED_MODERATOR_PASSWORD`'dan gelir, yoksa üretilip `seed accounts` log satırında bir kez yazdırılır. `dart run tool/seed.dart` server'ı başlatmadan seed eder.

- API: `http://127.0.0.1:8787/api/v1/...`, referans sayfası `/docs`, OpenAPI spec'i `/openapi.yaml`
- Veri: `server/data/marketplace.db` ve `server/data/storage/` (gitignore'da)

### Web front end ile

```bash
cd web
dart run tool/sync_filament_module.dart                 # flutter_filament'in wasm modülünü web/filament/ altına kopyalar
flutter build web --release --no-web-resources-cdn      # -> web/build/web
cd ../server
MARKETPLACE_WEB_DIR=../web/build/web dart run bin/server.dart --seed
```

Production kurulumu da budur: server build edilmiş uygulamayı `/` altında servis eder (client-side route'lar `index.html`'e düşer), böylece httpOnly refresh cookie'si API ile same-origin olur.

Hot reload'lu development için server'ı yukarıdaki gibi çalıştırın ve:

```bash
cd web
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5000 \
  --dart-define=MARKETPLACE_API=http://127.0.0.1:8787
```

İkisinde de aynı host adını (`127.0.0.1`) kullanın; `localhost` ile `127.0.0.1`'i karıştırmak refresh cookie'sini cross-site yapar. Varsayılan CORS policy'si credential'larla her `127.0.0.1` / `localhost` port'una izin verir. Access token yalnızca bellekte tutulur; sayfa yenilenince session cookie'den geri yüklenir.

### Docker

```bash
cp .env.example .env                                   # MARKETPLACE_JWT_SECRET'ı ayarlayın
(cd web && flutter build web --release)
docker compose up --build                              # API + web front end + seed, http://127.0.0.1:8787
```

`MARKETPLACE_JWT_SECRET` ayarlı değilse compose dosyası hemen hata verir. Veri `marketplace-data` volume'unda durur; `.env` içindeki `LUMINA_TEST_ASSETS`, seed için mount edilen host klasörünü seçer (varsayılan `./test-assets`).

### Konfigürasyon

| Değişken | Varsayılan | |
|---|---|---|
| `MARKETPLACE_JWT_SECRET` | zorunlu | access token'lar için HS256 key'i; saklanan IP hash'lerinin salt'ı da budur |
| `MARKETPLACE_HOST` / `MARKETPLACE_PORT` | `127.0.0.1` / `8787` | port `0` boş bir port seçer |
| `MARKETPLACE_DATA_DIR` | `data` | aşağıdaki ikisinin üst klasörü |
| `MARKETPLACE_DB` / `MARKETPLACE_STORAGE` | `data/marketplace.db` / `data/storage` | SQLite dosyası, blob klasörü |
| `MARKETPLACE_BASE_URL` | `http://<host>:<port>` | `https` bir URL refresh cookie'sini `Secure` yapar |
| `MARKETPLACE_WEB_DIR` | yok | bir `flutter build web` çıktısını `/` altında servis eder |
| `MARKETPLACE_CORS_ORIGINS` | `http://localhost:*,http://127.0.0.1:*` | credential'larla izin verilen tarayıcı origin'leri |
| `MARKETPLACE_MAX_UPLOAD_MB` | `256` | version arşivi limiti (görseller: 8 MB) |
| `MARKETPLACE_MAX_PREVIEW_MB` | `32` | bir version'ın alabileceği en büyük preview model; daha büyüğü 3D görünüm almaz |
| `MARKETPLACE_TRUST_PROXY` | `false` | client IP'sini `X-Forwarded-For`'dan alır |
| `MARKETPLACE_TEST_ASSETS` | `../test-assets` | `--seed`'in örnek mesh'leri okuduğu yer |
| `MARKETPLACE_SEED_ADMIN_PASSWORD` / `MARKETPLACE_SEED_MODERATOR_PASSWORD` | üretilir | seed hesaplarının şifreleri |

## Nasıl çalışır

- **Listing'ler ve version'lar.** Listing draft olarak oluşturulur, bir arşiv yüklenip doğrulanır, sonra lisansları ve sahiplik beyanıyla bir version publish edilir. API'nin özeti [server README'sinde](server/README.tr.md); tüm route'lar body'leriyle birlikte [`server/openapi.yaml`](server/openapi.yaml) içinde.
- **Yalnızca ücretsiz lisanslar.** Content: `CC0-1.0`, `CC-BY-4.0`, `CC-BY-SA-4.0`. Kod: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `MPL-2.0`, `Zlib`. Diğer her şey reddedilir.
- **Sahiplik beyanı.** Bir version ancak yükleyen kişi güncel terms version'ına karşı "I own this work or have the right to publish it under the chosen license." beyanını onayladığında publish edilir. Beyan değiştirilemez şekilde saklanır. Bir yayıncıyı suspend etmek tüm listing'lerini unlist eder, hesabı askıya alır ve tüm session'larını iptal eder; her adım audit log'a yazılır.
- **Game template'ler ve plugin'ler** kendi arşiv formatlarına sahiptir (`template.json` içeren bir Lumina proje klasörü; `<name>.lmplugin` manifest'i olan bir plugin klasörü) ve upload'da ve publish'te kontrol edilir. Kurallar shared pakette; bkz. [shared README](shared/README.tr.md).
- **3D görünüm.** Model listing sayfaları, version'ın preview modelini (arşivdeki en büyük self-contained glTF) tarayıcıda Lumina engine'iyle, flutter_filament'in WebGL2 WebAssembly modülü üzerinde render edebilir. Bkz. [web README](web/README.tr.md).
- **Install manifest'leri**, bir version'ın her dosyasının Lumina Studio'da nereye gideceğini söyler (proje content'i, plugin klasörü, temalar, template'ler).

## Development

```bash
melos run analyze        # tüm paketlerde dart analyze
melos run test           # önce test:dart (server, shared), sonra test:flutter (web)
melos run test:dart      # server ve shared'da dart test
melos run test:flutter   # web'de flutter test
melos run format         # dart format --line-length 120
melos run format:check   # format'lanmamış kod varsa fail eder
melos run serve          # örnek listing'lerle API (MARKETPLACE_JWT_SECRET gerekir)
melos run build:web      # web/ içinde flutter build web --release
```

Her paket `always_use_package_imports` lint'ini açar: bir dosya kendi paketindeki başka bir dosyayı göreli yolla değil, `package:` URI'siyle import eder (`package:lumina_marketplace_server/src/...`).

Test'ler gerçek geçici SQLite veritabanları ve storage klasörleri, ephemeral port'larda gerçek server'lar ve `test-assets/` (ya da `LUMINA_TEST_ASSETS`) içindeki gerçek mesh'lerle çalışır; plugin publish test'leri `lumina_plugin_pcg`'yi `../plugins` altındaki plugins checkout'undan (ya da `LUMINA_PLUGINS_DIR`) okur.

Kanıtları `build/smoke_artifacts/` altına yazılan smoke test'ler:

```bash
cd server && dart run tool/e2e_smoke.dart
cd web && dart test integration_test/smoke/marketplace_web_smoke_test.dart
```

`e2e_smoke.dart` server'ı başlatır ve `MarketplaceClient` üzerinden sürer: kayıt olma, bir CC0 model yayınlama, arama, edinme, install manifest'ini alıp her dosyayı hash kontrolüyle indirme, bir game template ve bir plugin yayınlama, bozuk ya da ücretsiz olmayan arşivlerin reddedildiğini görme. Web smoke'u release uygulamasını build eder ve puppeteer ile Chrome'da gezer; 3D görünüm ve plugin publish akışı da dahil (screenshot'lar ve senaryo başına sidecar JSON'lu bir WebM ile `build/smoke_report.html`, hepsi [lumina_smoke](https://github.com/LuminaGame/tools) ile yazılır; `MKT_SKIP_WEB_BUILD=1` mevcut build'i tekrar kullanır; flutter_filament'in WebAssembly modülü build edilmemişse 3D görünüm senaryosu atlanır).

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)); `server/`, `shared/` ve `web/` aynı lisans dosyasını taşır. Bir marketplace instance'ında yayınlanan content, her version için beyan edilen lisanslar altında yayıncıları tarafından lisanslanır.
