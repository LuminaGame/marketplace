import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lumina_marketplace_server/lumina_marketplace_server.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/test_server.dart';

void main() {
  test('every API route is documented in openapi.yaml, which is served at /openapi.yaml and /docs', () async {
    final spec = loadYaml(File('openapi.yaml').readAsStringSync()) as YamlMap;
    expect(spec['openapi'], startsWith('3.'));
    final documented = <String>{};
    (spec['paths'] as YamlMap).forEach((path, ops) {
      for (final method in (ops as YamlMap).keys) {
        if (method == 'parameters') continue;
        documented.add('${method.toString().toUpperCase()} $path');
      }
    });
    final routes = {for (final r in apiRoutes) '${r.method} ${r.openApiPath}'};
    expect(documented.difference(routes), isEmpty, reason: 'documented but not implemented');
    expect(routes.difference(documented), isEmpty, reason: 'implemented but not documented');

    final server = await TestServer.start();
    final yaml = await http.get(server.url.resolve('openapi.yaml'));
    expect(yaml.statusCode, 200);
    expect(yaml.body, File('openapi.yaml').readAsStringSync());
    final docs = await http.get(server.url.resolve('docs'));
    expect(docs.statusCode, 200);
    expect(docs.headers['content-type'], startsWith('text/html'));
    expect(docs.body, contains('/api/v1/listings/{id}/versions/{version}/manifest'));
    expect((await http.get(server.url.resolve('api/v1/health'))).statusCode, 200);
  });

  test('the server serves a built web app with an SPA fallback, never escaping its dir', () async {
    final web = Directory.systemTemp.createTempSync('mkt_web_');
    addTearDown(() => web.deleteSync(recursive: true));
    File('${web.path}/index.html').writeAsStringSync('<html>marketplace</html>');
    File('${web.path}/main.dart.js').writeAsStringSync('console.log(1)');
    final server = await TestServer.start(webDir: web.path);
    expect((await http.get(server.url)).body, '<html>marketplace</html>');
    final js = await http.get(server.url.resolve('main.dart.js'));
    expect(js.headers['content-type'], startsWith('text/javascript'));
    expect((await http.get(server.url.resolve('listings/barrel'))).body, '<html>marketplace</html>', reason: 'SPA route');
    final escape = await http.get(Uri.parse('${server.url}..%2F..%2Fetc%2Fpasswd'));
    expect(escape.body, isNot(contains('root:')));
    expect((await http.get(server.url.resolve('api/v1/nope'))).statusCode, 404, reason: 'API 404s are not the SPA');
  });
}
