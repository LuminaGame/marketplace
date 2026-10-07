import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

import 'package:lumina_marketplace_server/src/repositories/records.dart';
import 'package:lumina_marketplace_server/src/services/auth_service.dart';
import 'package:lumina_marketplace_server/src/services/services.dart';
import 'package:lumina_marketplace_server/src/terms.dart';
import 'package:lumina_marketplace_server/src/util.dart';

/// What [seedSampleContent] created (or found, when run again).
class SeedResult {
  const SeedResult({required this.listings, required this.adminPassword, required this.moderatorPassword, required this.created});

  final List<Listing> listings;

  /// Null when the accounts already existed (their passwords are unknown).
  final String? adminPassword;
  final String? moderatorPassword;
  final bool created;
}

/// A sample listing made from a folder of real meshes in `test-assets/Props`.
class _SampleModel {
  const _SampleModel(this.title, this.folder, this.tags, this.description, {this.featured = false});
  final String title;
  final String folder;
  final List<String> tags;
  final String description;
  final bool featured;
}

const _models = [
  _SampleModel('Barrel', 'Barrels', ['barrel', 'prop', 'industrial', 'container', 'fuel'], '''
# Barrel

Eight steel drums for industrial yards, fuel depots and wastelands: bent, dented and empty barrels, three fuel
barrels (black, red, yellow), a junk loot barrel and a radioactive barrel.

- Format: glTF binary (`.glb`), one mesh per file, PBR materials embedded
- Scale: real-world metres (Lumina imports glTF × 100 into centimetres)
- License: **CC0-1.0** — use them for anything, no credit required
''', featured: true),
  _SampleModel('Access Cards', 'Access_cards', ['keycard', 'sci-fi', 'pickup', 'prop'], '''
# Access Cards

Blue, green and red key cards for locked doors and progression gates.

- Three `.glb` meshes sharing one card design
- Ideal pickups for a Blueprint "has key" check
''', featured: true),
  _SampleModel('AC Units', 'AC_units', ['hvac', 'rooftop', 'industrial', 'prop'], '''
# AC Units

Ten air-conditioning units for rooftops and back alleys: wall-mounted splits, large rooftop units and rusty variants.
'''),
  _SampleModel('Banana Bunch', 'Banana Bunch', ['food', 'fruit', 'prop'], '''
# Banana Bunch

Short, medium and long banana bunches for markets, kitchens and jungle camps.
'''),
  _SampleModel('Chair', 'Chair', ['furniture', 'seat', 'prop'], '''
# Chair

A weathered armchair, plus a variant with a mount point for a sitting character.
'''),
  _SampleModel('Jerry Can', 'JerryCan', ['fuel', 'container', 'prop'], '''
# Jerry Can

Four fuel cans (default, black, blue, yellow). Pairs well with the **Barrel** pack for fuel depots — scatter a few
cans between the barrels.
'''),
];

/// The "Lumina Ember" editor theme, in the `lumina_ui` theme JSON shape.
const Map<String, Object?> emberTheme = {
  'name': 'Lumina Ember',
  'version': 1,
  'colors': {
    'background': '#0A0706',
    'sidebar': '#0E0A08',
    'card': '#120D0A',
    'popover': '#18110D',
    'secondary': '#20170F',
    'foreground': '#E8DCD2',
    'mutedForeground': '#8C7A6B',
    'primary': '#FF7A1A',
    'primaryForeground': '#140A02',
    'accent': '#F2B33D',
    'destructive': '#EE3533',
    'warning': '#FBBF24',
    'border': '#FFFFFF17',
    'chart1': '#FF7A1A',
    'chart2': '#F2B33D',
    'chart3': '#58A547',
    'chart4': '#8688FE',
    'chart5': '#EE3533',
  },
  'radius': 0.1875,
  'density': 'compact',
  'font': 'GeistSans',
};

/// Finds `seed/screenshots` next to this package.
String? _seedScreenshotsDir() {
  final candidates = <String>[];
  try {
    final lib = Isolate.resolvePackageUriSync(Uri.parse('package:lumina_marketplace_server/lumina_marketplace_server.dart'));
    if (lib != null) candidates.add(File.fromUri(lib).parent.parent.uri.resolve('seed/screenshots').toFilePath());
  } catch (_) {}
  candidates.add('seed/screenshots');
  for (final c in candidates) {
    if (Directory(c).existsSync()) return c;
  }
  return null;
}

/// Seeds the marketplace with real, free (CC0) sample listings built from the
/// meshes in [testAssetsDir] (read-only: the zips are built in memory), plus an
/// admin publisher `lumina` ("Lumina Samples") and a `moderator` account.
/// Running it again changes nothing.
Future<SeedResult> seedSampleContent(
  MarketplaceServices services, {
  required String testAssetsDir,
  String? adminPassword,
  String? moderatorPassword,
  String? screenshotsDir,
}) async {
  final existing = services.users.findByUsername('lumina');
  if (existing != null) {
    final page = services.listingService.search({'publisher': 'lumina', 'pageSize': '100'});
    return SeedResult(listings: page.items, adminPassword: null, moderatorPassword: null, created: false);
  }
  const client = ClientInfo(ipHash: 'seed', userAgent: 'lumina-marketplace-seed');
  final adminPw = adminPassword ?? newToken().substring(0, 20);
  final modPw = moderatorPassword ?? newToken().substring(0, 20);
  final admin = await services.auth.signUp(
      email: 'samples@lumina.local', username: 'lumina', password: adminPw, displayName: 'Lumina Samples', client: client,
      role: UserRole.admin);
  await services.auth.signUp(
      email: 'moderator@lumina.local', username: 'moderator', password: modPw, displayName: 'Lumina Moderator',
      client: client, role: UserRole.moderator);
  final auth = AuthContext(admin.user, admin.sessionId);
  final shots = screenshotsDir ?? _seedScreenshotsDir();
  final ls = services.listingService;

  Future<ListingRecord> publish({
    required ListingCategory category,
    required String title,
    required String description,
    required List<String> tags,
    required List<int> bytes,
    required String fileName,
    bool featured = false,
  }) async {
    var listing = ls.create(auth, {
      'category': category.wire,
      'title': title,
      'description': description,
      'tags': tags,
      'engineVersion': '0.0.1',
    });
    final shot = shots == null ? null : File('$shots/${listing.slug}.jpg');
    if (shot != null && shot.existsSync()) listing = await ls.addScreenshot(auth, listing.id, shot.openRead());
    final upload = await ls.upload(auth, Stream.value(bytes), fileName: fileName);
    await ls.publishVersion(auth, listing.id, {
      'version': '1.0.0',
      'uploadId': upload.id,
      'contentLicense': 'CC0-1.0',
      'releaseNotes': 'First release.',
      'attestation': {'accepted': true, 'termsVersion': publishingTerms.version},
    }, client);
    if (featured) services.listings.update(listing.id, {'featured': 1});
    return services.listings.findById(listing.id)!;
  }

  for (final m in _models) {
    final dir = Directory('$testAssetsDir/Props/${m.folder}');
    final meshes = dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.glb')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final archive = Archive();
    for (final mesh in meshes) {
      archive.addFile(ArchiveFile.bytes(mesh.uri.pathSegments.last, mesh.readAsBytesSync()));
    }
    await publish(
      category: ListingCategory.model,
      title: m.title,
      description: m.description,
      tags: m.tags,
      bytes: ZipEncoder().encode(archive),
      fileName: '${installFolderName(m.title)}.zip',
      featured: m.featured,
    );
  }
  await publish(
    category: ListingCategory.theme,
    title: 'Lumina Ember',
    description: '''
# Lumina Ember

A warm, ember-tinted take on the Lumina Studio dark theme: deeper browns behind the panels, a brighter orange
primary and an amber accent. Install it from the Marketplace window and pick it under
**Editor Preferences → Appearance**.
''',
    tags: const ['theme', 'dark', 'warm'],
    bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(emberTheme)),
    fileName: 'lumina_ember.json',
    featured: true,
  );
  final page = ls.search({'publisher': 'lumina', 'pageSize': '100'});
  services.log.info('seeded', {'listings': page.total});
  return SeedResult(listings: page.items, adminPassword: adminPw, moderatorPassword: modPw, created: true);
}
