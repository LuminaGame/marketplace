import 'dart:io';

import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';

/// Seeds a marketplace database with the sample CC0 listings built from the
/// workspace's `test-assets/` (read-only), without starting the HTTP server.
///
///   MARKETPLACE_JWT_SECRET=... dart run tool/seed.dart [path/to/test-assets]
Future<void> main(List<String> args) async {
  final config = MarketplaceConfig.fromEnvironment();
  final services = MarketplaceServices.open(config, MarketplaceLog.stdout());
  try {
    final result = await seedSampleContent(
      services,
      testAssetsDir: args.isNotEmpty ? args.first : (Platform.environment['MARKETPLACE_TEST_ASSETS'] ?? '../test-assets'),
      adminPassword: Platform.environment['MARKETPLACE_SEED_ADMIN_PASSWORD'],
      moderatorPassword: Platform.environment['MARKETPLACE_SEED_MODERATOR_PASSWORD'],
    );
    if (!result.created) {
      stdout.writeln('Already seeded (${result.listings.length} sample listings).');
      return;
    }
    stdout.writeln('Seeded ${result.listings.length} listings:');
    for (final l in result.listings) {
      stdout.writeln('  ${l.category.wire.padRight(8)} ${l.title}');
    }
    stdout.writeln('Admin publisher: lumina / ${result.adminPassword}');
    stdout.writeln('Moderator:       moderator / ${result.moderatorPassword}');
  } finally {
    services.close();
  }
}
