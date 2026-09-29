import 'dart:convert';
import 'dart:io';

/// Structured logs: one JSON object per line (`ts`, `level`, `msg`, fields).
class MarketplaceLog {
  MarketplaceLog(this._sink);

  /// JSON lines on stdout.
  factory MarketplaceLog.stdout() => MarketplaceLog(stdout.writeln);

  /// Drops everything (tests).
  factory MarketplaceLog.silent() => MarketplaceLog((_) {});

  /// Keeps every line in [lines] (smoke evidence).
  factory MarketplaceLog.collecting(List<String> lines, {bool echo = false}) => MarketplaceLog((l) {
        lines.add(l);
        if (echo) stdout.writeln(l);
      });

  final void Function(String line) _sink;

  void info(String msg, [Map<String, Object?> fields = const {}]) => _write('info', msg, fields);
  void warn(String msg, [Map<String, Object?> fields = const {}]) => _write('warn', msg, fields);
  void error(String msg, [Map<String, Object?> fields = const {}]) => _write('error', msg, fields);

  void _write(String level, String msg, Map<String, Object?> fields) {
    _sink(jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), 'level': level, 'msg': msg, ...fields},
        toEncodable: (o) => o.toString()));
  }
}
