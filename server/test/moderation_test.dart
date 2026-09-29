import 'package:http/http.dart' as http;
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  late TestServer server;
  late MarketplaceClient mod;
  late MarketplaceClient thief;
  late MarketplaceClient reporter;

  setUp(() async {
    server = await TestServer.start();
    await server.seed();
    mod = server.client();
    await mod.logIn(login: 'moderator', password: 'seed-moderator-password');
    expect(mod.currentUser!.role, UserRole.moderator);
    thief = server.client();
    await signUp(thief, username: 'thief');
    reporter = server.client();
    await signUp(reporter, username: 'reporter');
  });

  test('reporting then unlisting hides a listing from search; the audit log records it', () async {
    final (stolen, _) = await publish(thief, title: 'Totally Original Access Cards', zip: propsZip('Access_cards'), tags: ['keycard']);
    expect((await reporter.search(const SearchQuery(q: 'original'))).items.map((l) => l.id), [stolen.id]);

    final report = await reporter.report(stolen.id, ReportReason.stolenContent, details: 'Copied from a paid pack.');
    expect(report.status, ReportStatus.open);
    await expectLater(reporter.reports(), throwsApi(403, 'forbidden'), reason: 'only moderators see the queue');

    final queue = await mod.reports();
    expect(queue.map((r) => r.id), contains(report.id));
    expect(queue.firstWhere((r) => r.id == report.id).reporter, 'reporter');

    final resolved = await mod.resolveReport(report.id, action: 'unlist', note: 'Confirmed stolen.');
    expect(resolved.status, ReportStatus.actioned);
    expect(resolved.resolvedBy, 'moderator');
    expect(resolved.listingStatus, ListingStatus.unlisted);
    expect((await reporter.search(const SearchQuery(q: 'original'))).items, isEmpty);
    await expectLater(reporter.listing(stolen.id), throwsApi(404));
    await expectLater(thief.relist(stolen.id), throwsApi(403, 'forbidden'), reason: 'a moderator unlist is not undone by the owner');

    final restored = await mod.moderatorRestore(stolen.id);
    expect(restored.status, ListingStatus.published);
    expect((await reporter.search(const SearchQuery(q: 'original'))).items, hasLength(1));

    final audit = await mod.auditLog();
    final actions = audit.map((e) => '${e.actor} ${e.action} ${e.targetId}').toList();
    expect(actions, containsAll([
      'reporter report.create ${stolen.id}',
      'moderator listing.unlist ${stolen.id}',
      'moderator report.resolve ${report.id}',
      'moderator listing.restore ${stolen.id}',
    ]));
    expect(audit.first.createdAt.isAfter(audit.last.createdAt) || audit.length == 1, isTrue, reason: 'newest first');
    await expectLater(reporter.auditLog(), throwsApi(403));
  });

  test('suspending a publisher unlists all their listings and revokes their tokens', () async {
    final (a, _) = await publish(thief, title: 'Stolen Barrel Set', zip: propsZip('Barrels', limit: 2));
    final (b, _) = await publish(thief, title: 'Stolen Chairs', zip: propsZip('Chair'));
    final accessToken = thief.accessToken!;
    final refreshToken = thief.refreshToken!;

    final suspended = await mod.suspend('thief', reason: 'Published paid assets they do not own.');
    expect(suspended.status, UserStatus.suspended);

    for (final id in [a.id, b.id]) {
      await expectLater(reporter.listing(id), throwsApi(404));
    }
    expect((await reporter.search(const SearchQuery(publisher: 'thief'))).total, 0);

    final r = await http.get(server.url.resolve('api/v1/me'), headers: {'Authorization': 'Bearer $accessToken'});
    expect(r.statusCode, 401, reason: 'the access token is revoked');
    expect(await server.client().restoreSession(refreshToken: refreshToken), isNull, reason: 'the refresh token is revoked');
    await expectLater(server.client().logIn(login: 'thief', password: 'correct horse battery'),
        throwsApi(403, 'account_suspended'));

    final audit = await mod.auditLog();
    expect(audit.where((e) => e.action == 'user.suspend' && e.targetId == suspended.id), hasLength(1));
    expect(audit.where((e) => e.action == 'listing.unlist' && (e.targetId == a.id || e.targetId == b.id)), hasLength(2),
        reason: 'each cascaded unlist is audited');
    expect(audit.firstWhere((e) => e.action == 'user.suspend').details['unlistedListings'], 2);

    final back = await mod.unsuspend('thief');
    expect(back.status, UserStatus.active);
    await server.client().logIn(login: 'thief', password: 'correct horse battery');
    await expectLater(reporter.listing(a.id), throwsApi(404), reason: 'listings stay unlisted until a moderator restores them');
  });

  test('regular users cannot moderate; admins can grant roles; the audit log is immutable', () async {
    final (listing, _) = await publish(thief, title: 'Some Bananas', zip: propsZip('Banana Bunch'));
    await expectLater(reporter.moderatorUnlist(listing.id, reason: 'x'), throwsApi(403, 'forbidden'));
    await expectLater(reporter.suspend('thief', reason: 'x'), throwsApi(403, 'forbidden'));
    await expectLater(mod.setRole('reporter', UserRole.moderator), throwsApi(403, 'forbidden'), reason: 'admin only');

    final admin = server.client();
    await admin.logIn(login: 'lumina', password: 'seed-admin-password');
    expect((await admin.setRole('reporter', UserRole.moderator)).role, UserRole.moderator);
    await reporter.refresh();
    expect((await reporter.moderatorUnlist(listing.id, reason: 'Testing the new role')).status, ListingStatus.unlisted);
    await expectLater(mod.suspend('lumina', reason: 'x'), throwsApi(403, 'forbidden'), reason: 'moderators cannot suspend admins');

    final db = server.server.services.database;
    expect(() => db.execute("UPDATE audit_log SET action = 'forged'"), throwsA(anything));
    expect(() => db.execute('DELETE FROM audit_log'), throwsA(anything));
  });
}
