import 'dart:convert';
import 'dart:io';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

/// `POST /api/v1/crash-reports`: Lumina Studio's crash reports land as JSON
/// files under the storage folder, without an account.
void main() {
  late TestServer server;

  setUpAll(() async {
    server = await TestServer.start();
  });

  test('a report is stored as one JSON file and answered with a receipt', () async {
    final client = server.client();
    final receipt = await client.submitCrashReport({
      'kind': 'uncaught',
      'error': 'StateError: Bad state: No element',
      'stackTrace': '#0      main (package:lumina_ui/main.dart:12:3)\n#1      _rootRun (dart:async/zone.dart:1399:13)',
      'description': 'Opened the material editor and dragged a node.',
      'email': 'dev@example.test',
      'release': 'v0.0.1-dev.16',
      'commit': '0123456789abcdef',
      'platform': 'windows-x64',
      'osVersion': 'Windows 11 Pro 10.0.26200',
      'gpu': 'NVIDIA RTX PRO 2000',
      'filament': '1.77.2',
      'logTail': ['[12:00:01] [INFO] [Engine] ready', '[12:00:02] [ERROR] [Viewport] device lost'],
      'reportId': 'local-1',
      'createdAt': '2026-10-06T12:00:03.000Z',
    });
    expect(receipt.id, hasLength(32));
    expect(receipt.receivedAt.isUtc, isTrue);

    final files = Directory('${server.root.path}/storage/crash-reports')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('${receipt.id}.json'))
        .toList();
    expect(files, hasLength(1));
    final stored = jsonDecode(files.single.readAsStringSync()) as Map<String, Object?>;
    expect(stored['id'], receipt.id);
    expect(stored['ipHash'], isA<String>());
    final report = stored['report'] as Map<String, Object?>;
    expect(report['error'], 'StateError: Bad state: No element');
    expect(report['kind'], 'uncaught');
    expect(report['email'], 'dev@example.test');
    expect(report['gpu'], 'NVIDIA RTX PRO 2000');
    expect((report['logTail'] as List).length, 2);
    expect(stored.containsKey('ip'), isFalse, reason: 'only the hashed address is kept');
  });

  test('the error is required, the kind is checked and long fields are refused', () async {
    final client = server.client();
    await expectLater(
      client.submitCrashReport({'stackTrace': 'no error text'}),
      throwsA(isA<MarketplaceException>().having((e) => e.statusCode, 'statusCode', 422)),
    );
    await expectLater(
      client.submitCrashReport({'error': 'x', 'kind': 'bogus'}),
      throwsA(isA<MarketplaceException>().having((e) => e.statusCode, 'statusCode', 422)),
    );
    await expectLater(
      client.submitCrashReport({'error': 'x', 'email': 'not an address'}),
      throwsA(isA<MarketplaceException>().having((e) => e.statusCode, 'statusCode', 422)),
    );
    await expectLater(
      client.submitCrashReport({'error': 'x' * (16 * 1024 + 1)}),
      throwsA(isA<MarketplaceException>().having((e) => e.statusCode, 'statusCode', 413)),
    );
    await expectLater(
      client.submitCrashReport({'error': 'x', 'logTail': List.filled(401, 'line')}),
      throwsA(isA<MarketplaceException>().having((e) => e.statusCode, 'statusCode', 413)),
    );
    // A kind-less report is an uncaught error; an over-long log line is cut, not refused.
    final receipt = await client.submitCrashReport({'error': 'y', 'logTail': ['z' * 5000]});
    final file = Directory('${server.root.path}/storage/crash-reports')
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('${receipt.id}.json'));
    final report = (jsonDecode(file.readAsStringSync()) as Map)['report'] as Map;
    expect(report['kind'], 'uncaught');
    expect((report['logTail'] as List).single, hasLength(2000));
  });
}
