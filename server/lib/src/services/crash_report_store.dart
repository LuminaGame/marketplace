import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../errors.dart';
import 'auth_service.dart';

/// A crash report Lumina Studio sent (`POST /api/v1/crash-reports`): checked
/// and written as one JSON file under `<storageDir>/crash-reports/<yyyy>/<mm>/`,
/// never into the database. Nothing identifies the sender beyond the hashed
/// IP and the e-mail the user chose to type.
class CrashReportStore {
  CrashReportStore(this.storageDir, {DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final String storageDir;
  final DateTime Function() _clock;
  final Random _random;

  static const int maxErrorChars = 16 * 1024;
  static const int maxStackChars = 256 * 1024;
  static const int maxDescriptionChars = 4000;
  static const int maxLogLines = 400;
  static const int maxLogLineChars = 2000;
  static const int maxFieldChars = 512;

  /// The report kinds the editor sends: an uncaught error while running, or
  /// a previous session that ended without closing.
  static const Set<String> kinds = {'uncaught', 'previous_run'};

  static const Set<String> _shortFields = {
    'reportId',
    'createdAt',
    'release',
    'commit',
    'editor',
    'platform',
    'osVersion',
    'gpu',
    'filament',
    'project',
    'plugin',
  };

  Directory get root => Directory('$storageDir/crash-reports');

  /// Validates [body], stores it and returns the receipt (`id`, `receivedAt`).
  Future<CrashReportReceiptRecord> store(Map<String, Object?> body, ClientInfo client) async {
    final report = _validate(body);
    final receivedAt = _clock().toUtc();
    final id = _newId();
    final dir = Directory('${root.path}/${receivedAt.year.toString().padLeft(4, '0')}/${receivedAt.month.toString().padLeft(2, '0')}');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$id.json');
    final record = {
      'id': id,
      'receivedAt': receivedAt.toIso8601String(),
      'ipHash': client.ipHash,
      'userAgent': ?client.userAgent,
      'report': report,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(record), flush: true);
    return CrashReportReceiptRecord(id: id, receivedAt: receivedAt, file: file);
  }

  Map<String, Object?> _validate(Map<String, Object?> body) {
    String text(String key, int max, {bool required = false}) {
      final v = body[key];
      if (v == null) {
        if (required) throw ApiException.validation('$key is required.', {'field': key});
        return '';
      }
      if (v is! String) throw ApiException.validation('$key must be a string.', {'field': key});
      if (v.length > max) {
        throw const ApiException(413, 'payload_too_large', 'A crash report field is too long.');
      }
      return v;
    }

    final error = text('error', maxErrorChars, required: true).trim();
    if (error.isEmpty) throw ApiException.validation('error must not be empty.', {'field': 'error'});
    final kind = text('kind', 32);
    if (kind.isNotEmpty && !kinds.contains(kind)) {
      throw ApiException.validation('kind must be one of ${kinds.join(', ')}.', {'field': 'kind'});
    }
    final email = text('email', 254).trim();
    if (email.isNotEmpty && (!email.contains('@') || email.contains(' '))) {
      throw ApiException.validation('email is not an address.', {'field': 'email'});
    }
    final out = <String, Object?>{
      'kind': kind.isEmpty ? 'uncaught' : kind,
      'error': error,
      'stackTrace': text('stackTrace', maxStackChars),
      'description': text('description', maxDescriptionChars),
      if (email.isNotEmpty) 'email': email,
    };
    for (final key in _shortFields) {
      final v = text(key, maxFieldChars);
      if (v.isNotEmpty) out[key] = v;
    }
    final log = body['logTail'];
    if (log != null) {
      if (log is! List) throw ApiException.validation('logTail must be a list of strings.', {'field': 'logTail'});
      if (log.length > maxLogLines) {
        throw const ApiException(413, 'payload_too_large', 'logTail holds too many lines.');
      }
      final lines = <String>[];
      for (final line in log) {
        if (line is! String) throw ApiException.validation('logTail must be a list of strings.', {'field': 'logTail'});
        lines.add(line.length > maxLogLineChars ? line.substring(0, maxLogLineChars) : line);
      }
      out['logTail'] = lines;
    }
    return out;
  }

  String _newId() {
    const hex = '0123456789abcdef';
    final b = StringBuffer();
    for (var i = 0; i < 32; i++) {
      b.write(hex[_random.nextInt(16)]);
    }
    return b.toString();
  }
}

class CrashReportReceiptRecord {
  const CrashReportReceiptRecord({required this.id, required this.receivedAt, required this.file});

  final String id;
  final DateTime receivedAt;
  final File file;

  Map<String, Object?> toJson() => {'id': id, 'receivedAt': receivedAt.toIso8601String()};
}
