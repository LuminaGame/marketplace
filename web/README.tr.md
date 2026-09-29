[English](README.md)

# lumina_marketplace_web

Lumina Marketplace web front end'i: [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) (Lumina Studio ile aynı version ve palet) ve `go_router` ile yazılmış, server ile shared paketteki `MarketplaceClient` üzerinden konuşan bir Flutter web uygulaması.

| Route | Sayfa |
|---|---|
| `/` | ana sayfa: öne çıkan ve en yeni listing'ler |
| `/search` | arama ve filtreler (kategori, lisans türü, lisans, engine version'ı, yalnızca ücretsiz, sıralama) |
| `/listings/:slug` | listing sayfası: screenshot'lar ya da 3D görünüm, version'lar, lisanslar, "Get (Free)", report |
| `/login`, `/signup`, `/profile` | hesaplar |
| `/publish`, `/publish/:id` | publish akışı: listing detayları, arşiv upload'ı, lisanslar ve sahiplik beyanı; plugin listing'leri paketin `.lmplugin` dosyasından doldurulur |
| `/my/listings`, `/my/library` | kullanıcının listing'leri ve edindiği listing'ler |
| `/moderation` | report'lar, unlist / restore / feature, suspend'ler, audit log (moderatörler) |

## Gereksinimler

- Web desteğiyle Flutter SDK (Dart `^3.12.0`).
- Bu repo'nun yanında bir [lumina](https://github.com/LuminaGame/lumina) checkout'u (`../lumina`): `lumina` ve `flutter_filament`, 3D görünüm için path dependency'dir (`../../lumina/lumina`, `../../lumina/flutter_filament`). Gitignore'lu bir root `pubspec_overrides.yaml` bunları başka bir yere yönlendirebilir.
- 3D görünüm için: lumina repo'sunda build edilen flutter_filament WebAssembly modülü (`flutter_filament/web/flutter_filament.{js,wasm}`).
- Çalışan bir marketplace server'ı (bkz. [repo README](../README.tr.md#localde-çalıştırmak)).

## Build ve çalıştırma

```bash
dart run tool/sync_filament_module.dart                 # wasm modülünü web/filament/ altına kopyalar (gitignore'da)
flutter build web --release --no-web-resources-cdn      # -> build/web
```

Server `MARKETPLACE_WEB_DIR=../web/build/web` ile başlatıldığında build'i `/` altında servis eder; API ile aynı origin'de çalışan production kurulumu budur. Repo root'undan `melos run build:web` de build eder.

Ayrı çalışan bir server'a karşı hot reload'lu development için:

```bash
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5000 \
  --dart-define=MARKETPLACE_API=http://127.0.0.1:8787
```

`MARKETPLACE_API` verilmezse uygulama servis edildiği origin ile konuşur. Uygulama ve API için aynı host adını kullanın, yoksa refresh cookie'si cross-site olur. Access token yalnızca bellekte tutulur; sayfa yenilenince session httpOnly refresh cookie'sinden geri yüklenir.

## 3D görünüm

Version'ın bir preview modeli varsa model listing sayfalarında **Images / 3D view** toggle'ı çıkar. 3D görünüm Lumina engine'ini tarayıcıda çalıştırır (flutter_filament'in WebGL2 WebAssembly modülü üzerinde `package:lumina/lumina_runtime.dart`) ve server'ın arşivden çıkardığı preview GLB'yi render eder: orbit için sürükleme, pan için sağ tık ya da Shift ile sürükleme, zoom için tekerlek, yeniden çerçevelemek için çift tık ya da **Reset view**, ve **Fullscreen**. Runtime deferred bir library'dir ve wasm modülü (`filament/flutter_filament.{js,wasm}`) yalnızca biri 3D görünümü açtığında yüklenir; server onu ETag ile `application/wasm` olarak servis eder.

## Test'ler

```bash
flutter test                                                        # ya da: melos run test:flutter
dart test integration_test/smoke/marketplace_web_smoke_test.dart    # tarayıcı smoke'u
```

Widget test'leri `setUpAll` içinde başlatılan, seed edilmiş gerçek bir server'a karşı; `../test-assets` (ya da `LUMINA_TEST_ASSETS`) içindeki gerçek mesh'ler ve `../../plugins` (ya da `LUMINA_PLUGINS_DIR`) altındaki plugins checkout'unun `lumina_plugin_pcg` klasörüyle çalışır.

Smoke test sade bir Dart test'idir: release uygulamasını build eder (`MKT_SKIP_WEB_BUILD=1` mevcut `build/web`'i kullanır, `MKT_WEB_DIR` başka bir build'i gösterir), onu servis eden seed'li bir server başlatır ve puppeteer ile Chrome'u (ya da Chromium'u) gezinme, arama, hesaplar, publishing, plugin publish akışı ve 3D görünüm boyunca sürer. Kanıtlar `build/smoke_artifacts/` (PNG screenshot'lar, bir WebM walkthrough, her artifact için bir sidecar JSON) ve `build/smoke_report.html` altına yazılır. `--plain-name 'listing 3D view'` yalnızca 3D görünüm senaryosunu çalıştırır.

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)).
