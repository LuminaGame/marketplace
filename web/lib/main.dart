import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'src/app.dart';
import 'src/data/session.dart';
import 'src/platform/http_client.dart';

/// The API the app talks to. Served by the backend (production mode), that is
/// the page's own origin; `--dart-define=MARKETPLACE_API=http://127.0.0.1:8787`
/// points a `flutter run -d chrome` build at a separately running server
/// (use the same host name for both, or the refresh cookie is cross-site).
const _apiOverride = String.fromEnvironment('MARKETPLACE_API');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // Accessibility basics: the semantics tree is always on, so screen readers
  // (and the browser smoke) see labelled buttons and fields.
  SemanticsBinding.instance.ensureSemantics();
  final base = _apiOverride.isNotEmpty ? Uri.parse(_apiOverride) : Uri.base.replace(path: '/', query: '', fragment: '');
  final client = MarketplaceClient(baseUrl: base, httpClient: createHttpClient(), keepRefreshToken: !usesRefreshCookie);
  final session = MarketplaceSession(client);
  await session.restore();
  runApp(MarketplaceApp(session: session));
}
