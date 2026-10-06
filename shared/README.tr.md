[English](README.md)

# lumina_marketplace_shared

Lumina Marketplace server'ı, web front end'i ve Lumina Studio arasında paylaşılan kod. Saf Dart'tır (yalnızca `http` ve `yaml` paketlerine bağımlı):

- listing'ler, version'lar, kullanıcılar, library, report'lar, audit log ve install manifest'leri için DTO'lar;
- ücretsiz lisans kataloğu ve lisans tespiti;
- listing kategorileri;
- kurulum path'i helper'ları (`installFolderName`, `isSafeRelativePath`);
- game template formatı (`checkGameTemplate`, `GameTemplateManifest`, `GameTemplateKeys`, `kGameTemplateFormatVersion`);
- plugin paketi formatı (`checkPluginPackage`, `PluginPackageInfo`, `detectLicenseText`, `changelogSection`);
- tüm API için HTTP client'ı `MarketplaceClient`.

```yaml
dependencies:
  lumina_marketplace_shared:
    git:
      url: https://github.com/LuminaGame/marketplace.git
      path: shared
```

## Client'ı kullanmak

```dart
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

final client = MarketplaceClient(baseUrl: Uri.parse('http://127.0.0.1:8787/'));

final page = await client.search(const SearchQuery(q: 'barrel', category: ListingCategory.model));
for (final listing in page.items) {
  print('${listing.title} (${listing.slug}), ${listing.downloadCount} download');
}

await client.logIn(login: 'me@example.com', password: password);
final listing = page.items.first;
await client.getListing(listing.id);                      // "Get (Free)": library'ye ekler

final manifest = await client.manifest(listing.id, listing.latestVersion!.version);
for (final file in manifest.files) {
  if (!isSafeRelativePath(file.target)) continue;          // installer'lar path'leri tekrar kontrol eder
  final bytes = await client.downloadUrl(file.url);
  // file.sha256'yı doğrulayın, sonra byte'ları <kurulum root'u>/<file.target> altına yazın
}
```

Client ayrıca kayıt, session'lar (`refresh`, `restoreSession`, `logOut`), profiller, publishing (`createListing`, `upload`, `publishVersion`, screenshot'lar, `unlist` / `relist`), library, report'lar ve moderasyon endpoint'lerini de kapsar. API hataları, server'ın hata `code`'unu taşıyan `MarketplaceException` olarak fırlatılır.

## Çökme raporları

`MarketplaceClient.submitCrashReport(Map report)` bir Lumina Studio çökme raporunu oturum açmadan `POST /api/v1/crash-reports` ucuna gönderir ve `CrashReportReceipt` (`id`, `receivedAt`) döner. Haritanın anahtarları metodun üzerinde listelenir.

## Lisanslar

| Tür | İzin verilen lisanslar |
|---|---|
| content | `CC0-1.0`, `CC-BY-4.0`, `CC-BY-SA-4.0` |
| kod | `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `MPL-2.0`, `Zlib` |

Diğer her şey ("Proprietary", CC NonCommercial ya da NoDerivatives, ...) reddedilir.

## Game template formatı (format 1)

`game_template` version'ı, Lumina Studio launcher'ının yeni bir projeye dönüştürdüğü bir Lumina proje klasörüdür. Editor'ün config klasöründe `templates/<Folder>/` altına kurulur.

```
<Folder>/                  opsiyonel tek top-level klasör; kurulum klasörünün adını verir (nokta ile başlamaz)
  template.json            {"format": 1, "title": "Arena", "description": "...", "engine_version": "0.0.1",
                            "thumbnail": "thumbnail.png"}   title zorunlu; diğer key'ler string
  thumbnail.png | .jpg     opsiyonel kart görseli (yoksa thumbnail.* / screenshot.*)
  <source>.lmproject       kaynak projenin manifest'i (ayarlar, input, map'ler ve mode'lar)
  pubspec.yaml             opsiyonel: dependency'ler ve asset klasörleri
  contents/**              zorunlu: level'lar (.lmas) ve asset'ler
  lib/**                   opsiyonel: projenin Dart kodu
```

Bozuk bir template `422 invalid_template` ile reddedilir; `details` ilk sorunun `problem` kodunu ve arşivdeki `path`'ini, `problems` içinde de tüm sorunları taşır:

| `problem` | Ne zaman |
|---|---|
| `missing_contents` | `contents/` altında dosya yok |
| `no_manifest` | template root'unda ne `template.json` ne de bir `.lmproject` var |
| `manifest_no_title` / `manifest_invalid` | boş olmayan bir `title` içermeyen `template.json`; JSON object değil, string olmayan bir key, 1'den farklı `format` ya da görsel olmayan bir thumbnail |
| `thumbnail_missing` | `template.json`'daki `thumbnail` arşivde yok |
| `multiple_projects` / `project_invalid` | root'ta birden fazla `.lmproject`; Lumina proje manifest'i olmayan bir tane (`project_name` yok) |
| `excluded_path` | template root'unda `android/ ios/ linux/ macos/ windows/ web/` ya da `build/` altında dosyalar, ya da herhangi bir `.dart_tool/` |
| `top_folder_invalid` | tek top-level klasör nokta ile başlıyor |
| `pubspec_invalid` / `path_dependency` | YAML map olmayan ya da hatalı `name:` içeren bir `pubspec.yaml`; Studio'nun resolve edemeyeceği bir path dependency |

**Path dependency'ler.** Studio, projeyi oluştururken `lumina:` dependency'sini local engine'e yönlendirir; bu yüzden `lumina` bir path dependency olabilir (`dependencies:` altında, `lumina:` ve bir sonraki satırda `path: ...` olarak). Diğer tüm path dependency'ler template içinde vendored bir kopya olmalıdır; örneğin `pubspec.yaml`'ı arşivde olan `packages/my_utils`. Vendored bir paket de aynı kurala uyar ve `lumina`'ya path ile bağımlı olamaz. Hosted, git ve SDK dependency'leri `flutter pub get`'e bırakılır. `.lmproject` ve `pubspec.yaml` lisans gerektirmez; `.lmas` content lisansı, `.dart` kod lisansı ister; bu yüzden bir game template her zaman ikisini de beyan eder.

## Plugin paketi formatı

`plugin` version'ı, olduğu gibi zip'lenmiş bir Lumina plugin klasörüdür. Lumina Studio onu `plugins/<name>/` altına kurar ve `plugins/<name>/<name>.lmplugin` dosyasını yükler; marketplace listing'i aynı manifest'ten doldurur.

```
<name>/                    opsiyonel tek top-level klasör; adı <name> olmalı
  <name>.lmplugin          {"name", "friendly_name", "version", "description", "category", "authors",
                            "engine_version", "modules", ..., "license": "MIT", "changelog": "CHANGELOG.md"}
  LICENSE | COPYING        opsiyonel lisans metni (.md / .txt de olur)
  CHANGELOG.md             opsiyonel; "## 1.0.0" ya da "## [1.0.0] - 2026-09-01" bölümleri
  pubspec.yaml, lib/**, resources/**
```

Publish akışı manifest'i listing'e şöyle eşler: başlık `friendly_name`'den (yoksa `name`), açıklama `description`'dan, tag'ler `category` ve `plugin`'den, engine version'ı `engine_version`'ın alt sınırından, version `version`'dan, release notes da version'ın `CHANGELOG.md` bölümünden.

**Lisans**: opsiyonel `license` key'i (allow-list'teki bir SPDX id'si ya da `AND` ile birleştirilmiş bir content ve bir kod lisansı, ör. `"CC-BY-4.0 AND MIT"`), yoksa server'ın tanıdığı bir root lisans metni (`SPDX-License-Identifier:` satırı ya da allow-list'teki bir lisansın standart metni). Beyan edilen lisans o version için sabittir. `license` ve `changelog` yalnızca marketplace tarafından okunur; Lumina'nın plugin loader'ı bunları ekstra key olarak tutar.

Media tipleri ve kaynak dosyaların yanında izin verilenler: `.gitignore`, `.gitattributes`, `.metadata`, `.pubignore`, `pubspec.lock`, `analysis_options.yaml`, `LICENSE` / `LICENCE` / `COPYING` / `NOTICE` / `AUTHORS`. Bozuk paketler `422 invalid_plugin` ile reddedilir:

| `problem` | Ne zaman |
|---|---|
| `no_manifest` / `multiple_manifests` | paket root'unda `<name>.lmplugin` yok; birden fazla var |
| `manifest_invalid` | JSON object değil, `name` yok, string olmayan bir key |
| `name_invalid` / `name_mismatch` | `name` geçerli bir Dart paket adı değil; dosyanın basename'inden farklı |
| `top_folder_mismatch` | tek top-level klasörün adı `<name>` değil |
| `version_invalid` / `engine_version_invalid` | `version` `X.Y.Z` değil; `engine_version` bir version constraint'i değil |
| `license_unknown` | `license` allow-list dışında bir id, bir `OR` / `WITH` ifadesi ya da aynı türden iki lisans içeriyor |
| `license_not_free` | `license` key'i yok ve lisans metni ücretsiz değil ("All rights reserved", NonCommercial, NoDerivatives) |
| `license_conflict` | lisans metni, `license`'ın beyan ettiğinden farklı (ya da ücretsiz olmayan) bir lisans |
| `changelog_missing` | `changelog` pakette olmayan bir dosyayı gösteriyor |

Publish'te version manifest'tekiyle aynı olmalıdır (`422 version_mismatch`) ve beyan edilmiş bir lisans değiştirilemez (`422 license_mismatch`). Plugins repo'sundaki `tool/pack_plugin.dart` bunların hepsini upload öncesinde kontrol eder.

## Install manifest'i (format 1)

`GET /listings/{id}/versions/{v}/manifest` bir `InstallManifest` döndürür: listing, version, yayıncı, lisanslar, arşiv (`url`, `sha256`, `size`) ve her dosya için `path`, `size`, `sha256`, `url` ve kurulum `target`'ı.

| `installKind` | `targetRoot` |
|---|---|
| `project_contents` | `contents/Marketplace/<yayıncı kullanıcı adı>/<Listing>/`, proje root'una göre relative |
| `plugin` | `plugins/<package>/`, editor'ün plugin klasörüne göre relative (arşivdeki tek top-level klasör paketin adını verir ve çıkarılır, yoksa root'taki `<package>.lmplugin` verir) |
| `theme` | `themes/<listing>.json` |
| `game_template` | `templates/<Listing>/` |

Klasör adları `installFolderName`'den geçer; her path upload sırasında `isSafeRelativePath` kontrolünden geçer ve installer'lar bunu tekrar kontrol etmelidir.

## Test'ler

```bash
dart test
```

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)).
