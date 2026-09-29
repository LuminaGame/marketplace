import 'dart:async';
import 'dart:io';

import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';

/// Runs the marketplace. Configuration comes from the environment (see
/// [MarketplaceConfig.fromEnvironment]); `MARKETPLACE_JWT_SECRET` is required.
///
///   MARKETPLACE_JWT_SECRET=$(openssl rand -hex 32) dart run bin/server.dart
///
/// `--seed` seeds the sample CC0 listings from `MARKETPLACE_TEST_ASSETS`
/// (default: the repository's `test-assets/`) on first start.
Future<void> main(List<String> args) async {
  final MarketplaceConfig config;
  try {
    config = MarketplaceConfig.fromEnvironment();
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
    return;
  }
  final log = MarketplaceLog.stdout();
  final server = await MarketplaceServer.start(config, log: log);
  if (args.contains('--seed')) {
    final assets = Platform.environment['MARKETPLACE_TEST_ASSETS'] ?? '../test-assets';
    final result = await seedSampleContent(
      server.services,
      testAssetsDir: assets,
      adminPassword: Platform.environment['MARKETPLACE_SEED_ADMIN_PASSWORD'],
      moderatorPassword: Platform.environment['MARKETPLACE_SEED_MODERATOR_PASSWORD'],
    );
    if (result.created) {
      log.info('seed accounts', {
        'admin': 'lumina',
        'adminPassword': result.adminPassword,
        'moderator': 'moderator',
        'moderatorPassword': result.moderatorPassword,
      });
    }
  }
  final done = Completer<void>();
  // Windows has no catchable SIGTERM (watching it throws), only Ctrl+C.
  for (final signal in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      if (done.isCompleted) return;
      await server.close();
      done.complete();
    });
  }
  await done.future;
  exit(0);
}
