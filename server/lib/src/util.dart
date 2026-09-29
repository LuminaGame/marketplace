import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final _random = Random.secure();

/// A random 128-bit identifier as 32 hex characters.
String newId() => hex(randomBytes(16));

/// [n] cryptographically secure random bytes.
List<int> randomBytes(int n) => List<int>.generate(n, (_) => _random.nextInt(256));

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A URL-safe random token (refresh tokens).
String newToken() => base64Url.encode(randomBytes(32)).replaceAll('=', '');

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String sha256OfString(String s) => sha256Hex(utf8.encode(s));

/// Timestamps are stored as ISO-8601 UTC with microseconds, so they sort as
/// text.
String nowIso() => DateTime.now().toUtc().toIso8601String();

final _semver = RegExp(r'^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$');

bool isSemver(String v) => _semver.hasMatch(v);

/// `1.2.3` → 1002003, for engine-version comparisons in SQL.
int semverCode(String v) {
  final m = _semver.firstMatch(v);
  if (m == null) throw FormatException('not a version: $v');
  return int.parse(m[1]!) * 1000000 + int.parse(m[2]!) * 1000 + int.parse(m[3]!);
}

/// `Barrel Pack!` → `barrel-pack`.
String slugify(String title) {
  final s = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'listing' : s;
}
