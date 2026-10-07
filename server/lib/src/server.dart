import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:lumina_marketplace_server/src/config.dart';
import 'package:lumina_marketplace_server/src/errors.dart';
import 'package:lumina_marketplace_server/src/http/api.dart';
import 'package:lumina_marketplace_server/src/http/docs.dart';
import 'package:lumina_marketplace_server/src/http/middleware.dart';
import 'package:lumina_marketplace_server/src/http/router.dart';
import 'package:lumina_marketplace_server/src/http/static_files.dart';
import 'package:lumina_marketplace_server/src/log.dart';
import 'package:lumina_marketplace_server/src/services/services.dart';

/// The running marketplace: `/api/v1/*` (the API), `/openapi.yaml` and
/// `/docs` (its documentation), and — when [MarketplaceConfig.webDir] is set —
/// the built web front end at `/`.
class MarketplaceServer {
  MarketplaceServer._(this.services, this._http, this.previewBackfill);

  final MarketplaceServices services;
  final HttpServer _http;

  /// Completes when the start-up backfill of preview models is done.
  final Future<void> previewBackfill;

  int get port => _http.port;

  /// `http://<host>:<port>/`.
  Uri get url => Uri(scheme: 'http', host: services.config.host == '0.0.0.0' ? '127.0.0.1' : services.config.host, port: port, path: '/');

  static Future<MarketplaceServer> start(MarketplaceConfig config, {MarketplaceLog? log}) async {
    final logger = log ?? MarketplaceLog.stdout();
    final services = MarketplaceServices.open(config, logger);
    final handler = buildHandler(services);
    final http = await shelf_io.serve(handler, config.host, config.port, shared: false);
    http.autoCompress = true;
    final backfill = services.listingService.backfillPreviews().then((n) {
      if (n > 0) logger.info('preview models backfilled', {'versions': n});
    }, onError: (Object e) => logger.warn('preview backfill failed', {'error': '$e'}));
    final server = MarketplaceServer._(services, http, backfill);
    logger.info('listening', {
      'url': '${server.url}',
      'database': config.databasePath,
      'storage': config.storageDir,
      'web': ?config.webDir,
    });
    return server;
  }

  /// The whole request pipeline (exposed for in-process use).
  static Handler buildHandler(MarketplaceServices services) {
    final context = ApiContext(services);
    final api = apiRouter(context, apiRoutes);
    final openApiPath = locateOpenApi();
    final web = services.config.webDir == null ? null : webAppHandler(services.config.webDir!);
    String? docsHtml;

    Response root(Request request) {
      final path = request.url.path;
      if (path == 'openapi.yaml' && openApiPath != null) {
        return Response.ok(File(openApiPath).readAsStringSync(), headers: {'content-type': 'application/yaml; charset=utf-8'});
      }
      if ((path == 'docs' || path == 'docs/') && openApiPath != null) {
        docsHtml ??= renderDocsHtml(File(openApiPath).readAsStringSync());
        return Response.ok(docsHtml, headers: {'content-type': 'text/html; charset=utf-8'});
      }
      throw ApiException.notFound();
    }

    return const Pipeline()
        .addMiddleware(requestLogging(services.log))
        .addMiddleware(errorHandling(services.log))
        .addMiddleware(cors(services.config.corsOrigins))
        .addHandler((request) async {
      final path = request.url.path;
      if (path == 'api' || path.startsWith('api/')) return api(request);
      if (path == 'openapi.yaml' || path == 'docs' || path == 'docs/') return root(request);
      if (web != null) return web(request);
      throw ApiException.notFound();
    });
  }

  Future<void> close() async {
    await _http.close(force: true);
    await previewBackfill;
    services.close();
    services.log.info('stopped');
  }
}
