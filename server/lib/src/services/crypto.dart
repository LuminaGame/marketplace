import 'dart:convert';

import 'package:cryptography/cryptography.dart' as c;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as j;

import 'package:lumina_marketplace_server/src/util.dart';

/// Argon2id password hashes in the PHC string format
/// (`$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>`), with the OWASP minimum
/// parameters by default. Verification reads the parameters from the stored
/// hash, so they can be raised later without invalidating old hashes.
class PasswordHasher {
  const PasswordHasher({this.memoryKiB = 19456, this.iterations = 2, this.parallelism = 1});

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  static String _b64(List<int> bytes) => base64.encode(bytes).replaceAll('=', '');
  static List<int> _unb64(String s) => base64.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));

  Future<List<int>> _derive(String password, List<int> salt, int m, int t, int p) async {
    final algorithm = c.Argon2id(memory: m, iterations: t, parallelism: p, hashLength: 32);
    final key = await algorithm.deriveKey(secretKey: c.SecretKey(utf8.encode(password)), nonce: salt);
    return key.extractBytes();
  }

  Future<String> hash(String password) async {
    final salt = randomBytes(16);
    final digest = await _derive(password, salt, memoryKiB, iterations, parallelism);
    return '\$argon2id\$v=19\$m=$memoryKiB,t=$iterations,p=$parallelism\$${_b64(salt)}\$${_b64(digest)}';
  }

  Future<bool> verify(String password, String phc) async {
    final parts = phc.split('\$');
    // ['', 'argon2id', 'v=19', 'm=..,t=..,p=..', salt, hash]
    if (parts.length != 6 || parts[1] != 'argon2id' || parts[2] != 'v=19') return false;
    final params = {for (final kv in parts[3].split(',')) kv.split('=')[0]: int.parse(kv.split('=')[1])};
    final expected = _unb64(parts[5]);
    final actual = await _derive(password, _unb64(parts[4]), params['m']!, params['t']!, params['p']!);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }
}

/// The claims of a verified access token.
class AccessClaims {
  const AccessClaims(this.userId, this.sessionId, this.role);
  final String userId;
  final String sessionId;
  final String role;
}

class TokenExpiredException implements Exception {}

class TokenInvalidException implements Exception {}

/// HS256 access tokens: `sub` (user id), `sid` (session id, checked against
/// the sessions table on every request so revocation is immediate), `role`.
class TokenService {
  TokenService(String secret, this.ttl) : _key = j.SecretKey(secret);

  final j.SecretKey _key;
  final Duration ttl;
  static const issuer = 'lumina-marketplace';

  String issue({required String userId, required String sessionId, required String role}) =>
      j.JWT({'sid': sessionId, 'role': role}, subject: userId, issuer: issuer, jwtId: newId())
          .sign(_key, algorithm: j.JWTAlgorithm.HS256, expiresIn: ttl);

  AccessClaims verify(String token) {
    try {
      final jwt = j.JWT.verify(token, _key, issuer: issuer);
      if (jwt.header?['alg'] != 'HS256') throw TokenInvalidException();
      final payload = (jwt.payload as Map).cast<String, Object?>();
      final sub = jwt.subject;
      final sid = payload['sid'];
      if (sub == null || sid is! String) throw TokenInvalidException();
      return AccessClaims(sub, sid, payload['role'] as String? ?? 'user');
    } on j.JWTExpiredException {
      throw TokenExpiredException();
    } on j.JWTException {
      throw TokenInvalidException();
    }
  }
}
