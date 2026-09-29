import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  test('sign up → log in → refresh → log out; a revoked refresh token is refused', () async {
    final server = await TestServer.start();
    final a = server.client();
    final signed = await signUp(a, username: 'ada', password: 'correct horse battery');
    expect(signed.user.username, 'ada');
    expect(signed.user.email, 'ada@example.test');
    expect(signed.user.role, UserRole.user);
    expect(signed.accessToken.split('.'), hasLength(3), reason: 'a JWT');
    expect((await a.me()).username, 'ada');

    final b = server.client();
    final login = await b.logIn(login: 'ada@example.test', password: 'correct horse battery');
    expect(login.user.id, signed.user.id);
    final byUsername = await server.client().logIn(login: 'ADA', password: 'correct horse battery');
    expect(byUsername.user.id, signed.user.id, reason: 'usernames are case-insensitive');

    final oldRefresh = b.refreshToken!;
    final refreshed = await b.refresh();
    expect(refreshed.refreshToken, isNot(oldRefresh), reason: 'refresh rotates the token');
    expect((await b.me()).username, 'ada');

    // The rotated-out token is revoked.
    final stale = server.client();
    expect(stale.restoreSession(refreshToken: oldRefresh), completion(isNull));

    final current = b.refreshToken!;
    await b.logOut();
    expect(b.isSignedIn, isFalse);
    final replay = server.client();
    await expectLater(replay.restoreSession(refreshToken: current), completion(isNull),
        reason: 'the refresh token was revoked by log-out');

    // Log-out also kills the access token issued for that session.
    final r = await http.get(server.url.resolve('api/v1/me'),
        headers: {'Authorization': 'Bearer ${refreshed.accessToken}'});
    expect(r.statusCode, 401);

    // Passwords are stored as argon2id hashes, never in plain text.
    final hash = server.server.services.users.findByUsername('ada')!.passwordHash;
    expect(hash, startsWith(r'$argon2id$v=19$'));
    expect(hash, isNot(contains('correct horse')));
  });

  test('bad password, duplicate accounts and weak passwords are refused', () async {
    final server = await TestServer.start();
    final a = server.client();
    await signUp(a, username: 'bob');
    await expectLater(server.client().logIn(login: 'bob', password: 'wrong password!'), throwsApi(401, 'invalid_credentials'));
    await expectLater(signUp(server.client(), username: 'bob'), throwsApi(409, 'conflict'));
    await expectLater(signUp(server.client(), username: 'carol', password: 'short'), throwsApi(422, 'validation_failed'));
    await expectLater(signUp(server.client(), username: 'no spaces allowed'), throwsApi(422, 'validation_failed'));
  });

  test('10 bad logins in a minute are rate-limited', () async {
    final server = await TestServer.start();
    await signUp(server.client(), username: 'dave', password: 'correct horse battery');
    final c = server.client();
    for (var i = 0; i < 10; i++) {
      await expectLater(c.logIn(login: 'dave', password: 'nope nope nope'), throwsApi(401, 'invalid_credentials'));
    }
    // The 11th attempt is refused before the password is checked, even the right one.
    await expectLater(c.logIn(login: 'dave', password: 'correct horse battery'), throwsApi(429, 'rate_limited'));
    final raw = await http.post(server.url.resolve('api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'login': 'dave', 'password': 'x'}));
    expect(raw.statusCode, 429);
    expect(int.parse(raw.headers['retry-after']!), inInclusiveRange(1, 60));
  });

  test('profile, avatar and password change (which revokes other sessions)', () async {
    final server = await TestServer.start();
    final a = server.client();
    await signUp(a, username: 'erin', password: 'first password 1');
    final other = server.client();
    await other.logIn(login: 'erin', password: 'first password 1');

    expect((await a.updateProfile(displayName: 'Erin the Maker')).displayName, 'Erin the Maker');
    final png = File(logoPng);
    final avatarBytes = png.existsSync() ? png.readAsBytesSync() : _tinyPng;
    final withAvatar = await a.uploadAvatar(avatarBytes);
    expect(withAvatar.avatarUrl, startsWith('/api/v1/media/'));
    final served = await http.get(a.resolve(withAvatar.avatarUrl!));
    expect(served.statusCode, 200);
    expect(served.headers['content-type'], 'image/png');
    expect(served.bodyBytes, avatarBytes);
    await expectLater(a.uploadAvatar(utf8.encode('not an image')), throwsApi(422, 'invalid_image'));

    await expectLater(a.changePassword(currentPassword: 'wrong', newPassword: 'second password 2'),
        throwsApi(401, 'invalid_credentials'));
    await a.changePassword(currentPassword: 'first password 1', newPassword: 'second password 2');
    expect(await other.restoreSession(), isNull, reason: 'other sessions are revoked');
    expect((await a.me()).username, 'erin', reason: 'the changing session stays signed in');
    await expectLater(server.client().logIn(login: 'erin', password: 'first password 1'), throwsApi(401));
    await server.client().logIn(login: 'erin', password: 'second password 2');
  });

  test('browsers get the refresh token as an httpOnly cookie and can refresh with it', () async {
    final server = await TestServer.start();
    final r = await http.post(server.url.resolve('api/v1/auth/signup'),
        headers: {'Content-Type': 'application/json', 'Origin': 'http://localhost:5000'},
        body: jsonEncode({'email': 'fay@example.test', 'username': 'fay', 'password': 'correct horse battery'}));
    expect(r.statusCode, 201);
    expect(r.headers['access-control-allow-origin'], 'http://localhost:5000');
    expect(r.headers['access-control-allow-credentials'], 'true');
    final cookie = r.headers['set-cookie']!;
    expect(cookie, contains('lm_refresh='));
    expect(cookie.toLowerCase(), contains('httponly'));
    expect(cookie, contains('Path=/api/v1/auth'));
    final token = RegExp(r'lm_refresh=([^;]+)').firstMatch(cookie)!.group(1)!;

    final refreshed = await http.post(server.url.resolve('api/v1/auth/refresh'),
        headers: {'Cookie': 'lm_refresh=$token', 'Content-Type': 'application/json'}, body: '{}');
    expect(refreshed.statusCode, 200);
    expect((jsonDecode(refreshed.body) as Map)['user']['username'], 'fay');

    final preflight = http.Request('OPTIONS', server.url.resolve('api/v1/auth/login'))
      ..headers.addAll({'Origin': 'http://127.0.0.1:61234', 'Access-Control-Request-Method': 'POST'});
    final pre = await http.Response.fromStream(await preflight.send());
    expect(pre.statusCode, 204);
    expect(pre.headers['access-control-allow-origin'], 'http://127.0.0.1:61234');
    final foreign = http.Request('OPTIONS', server.url.resolve('api/v1/auth/login'))
      ..headers.addAll({'Origin': 'https://evil.example', 'Access-Control-Request-Method': 'POST'});
    final bad = await http.Response.fromStream(await foreign.send());
    expect(bad.headers['access-control-allow-origin'], isNull);
  });
}

/// A 1×1 PNG, used only if the editor logo is not on disk.
const _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
