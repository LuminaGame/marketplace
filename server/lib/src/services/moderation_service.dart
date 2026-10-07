import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:lumina_marketplace_server/src/db/database.dart';
import 'package:lumina_marketplace_server/src/errors.dart';
import 'package:lumina_marketplace_server/src/repositories/records.dart';
import 'package:lumina_marketplace_server/src/repositories/repositories.dart';
import 'package:lumina_marketplace_server/src/util.dart';
import 'package:lumina_marketplace_server/src/services/auth_service.dart';
import 'package:lumina_marketplace_server/src/services/listing_service.dart';

/// Reports, the moderator queue, unlist/restore, suspension (the terms'
/// penalty clause) and the audit log.
class ModerationService {
  ModerationService({
    required this.db,
    required this.listings,
    required this.users,
    required this.sessions,
    required this.reports,
    required this.audit,
    required this.listingService,
  });

  final Database db;
  final ListingRepository listings;
  final UserRepository users;
  final SessionRepository sessions;
  final ReportRepository reports;
  final AuditRepository audit;
  final ListingService listingService;

  void _requireModerator(AuthContext caller) {
    if (!caller.canModerate) throw ApiException.forbidden('Moderators only.');
  }

  ListingReport toDto(ReportRecord r) {
    final listing = listings.findById(r.listingId)!;
    return ListingReport(
      id: r.id,
      listingId: r.listingId,
      listingTitle: listing.title,
      listingStatus: listing.status,
      publisher: users.findById(listing.publisherId)!.toPublisher(),
      reporter: users.findById(r.reporterId)?.username ?? 'unknown',
      reason: r.reason,
      details: r.details,
      status: r.status,
      createdAt: DateTime.parse(r.createdAt),
      resolvedBy: r.resolvedBy == null ? null : users.findById(r.resolvedBy!)?.username,
      resolvedAt: r.resolvedAt == null ? null : DateTime.parse(r.resolvedAt!),
      resolutionNote: r.resolutionNote,
    );
  }

  ReportRecord report(AuthContext caller, String listingId, Map<String, Object?> body) {
    final listing = listingService.findVisible(listingId, caller);
    final reason = ReportReason.tryParse(body['reason'] as String?);
    if (reason == null) {
      throw ApiException.validation(
          'Pick a reason: ${ReportReason.values.map((r) => r.wire).join(', ')}.', {'field': 'reason'});
    }
    final details = (body['details'] as String? ?? '').trim();
    if (details.length > 4000) throw ApiException.validation('The details are too long.');
    return transaction(db, () {
      final record = ReportRecord(
        id: newId(),
        listingId: listing.id,
        reporterId: caller.user.id,
        reason: reason,
        details: details,
        status: ReportStatus.open,
        createdAt: nowIso(),
      );
      reports.create(record);
      audit.append(caller.user.id, 'report.create', 'listing', listing.id, {'reportId': record.id, 'reason': reason.wire});
      return record;
    });
  }

  List<ListingReport> queue(AuthContext caller, {ReportStatus? status}) {
    _requireModerator(caller);
    return [for (final r in reports.list(status: status)) toDto(r)];
  }

  ReportRecord resolve(AuthContext caller, String reportId, Map<String, Object?> body) {
    _requireModerator(caller);
    final report = reports.find(reportId);
    if (report == null) throw ApiException.notFound('No such report.');
    if (report.status != ReportStatus.open) throw ApiException.conflict('This report is already resolved.');
    final action = body['action'] as String?;
    final note = (body['note'] as String? ?? '').trim();
    if (action != 'dismiss' && action != 'unlist') throw ApiException.validation('action is "dismiss" or "unlist".');
    return transaction(db, () {
      if (action == 'unlist') {
        final listing = listings.findById(report.listingId)!;
        if (listing.status != ListingStatus.unlisted || listing.unlistedBy != 'moderator') {
          _unlist(caller.user.id, listing, note.isEmpty ? 'Report ${report.id}: ${report.reason.wire}' : note);
        }
      }
      final resolved = reports.resolve(reportId,
          status: action == 'unlist' ? ReportStatus.actioned : ReportStatus.dismissed,
          resolvedBy: caller.user.id,
          note: note);
      audit.append(caller.user.id, 'report.resolve', 'report', reportId, {'action': action, 'listingId': report.listingId});
      return resolved;
    });
  }

  void _unlist(String? actorId, ListingRecord listing, String reason, [Map<String, Object?> extra = const {}]) {
    listings.update(listing.id, {'status': ListingStatus.unlisted.wire, 'unlisted_by': 'moderator', 'unlisted_reason': reason});
    audit.append(actorId, 'listing.unlist', 'listing', listing.id, {'reason': reason, 'previousStatus': listing.status.wire, ...extra});
  }

  ListingRecord unlist(AuthContext caller, String listingId, Map<String, Object?> body) {
    _requireModerator(caller);
    final listing = listings.findById(listingId);
    if (listing == null) throw ApiException.notFound('No such listing.');
    final reason = (body['reason'] as String? ?? '').trim();
    if (reason.isEmpty) throw ApiException.validation('Give a reason.', {'field': 'reason'});
    return transaction(db, () {
      _unlist(caller.user.id, listing, reason);
      return listings.findById(listingId)!;
    });
  }

  ListingRecord restore(AuthContext caller, String listingId) {
    _requireModerator(caller);
    final listing = listings.findById(listingId);
    if (listing == null) throw ApiException.notFound('No such listing.');
    if (listing.status != ListingStatus.unlisted) throw ApiException.conflict('The listing is not unlisted.');
    final publisher = users.findById(listing.publisherId)!;
    if (publisher.status == UserStatus.suspended) {
      throw ApiException.conflict('The publisher is suspended; unsuspend them first.');
    }
    return transaction(db, () {
      final r = listings.update(listingId, {'status': ListingStatus.published.wire, 'unlisted_by': null, 'unlisted_reason': null});
      audit.append(caller.user.id, 'listing.restore', 'listing', listingId);
      return r;
    });
  }

  ListingRecord feature(AuthContext caller, String listingId, Map<String, Object?> body) {
    _requireModerator(caller);
    if (listings.findById(listingId) == null) throw ApiException.notFound('No such listing.');
    final featured = body['featured'] == true;
    return transaction(db, () {
      final r = listings.update(listingId, {'featured': featured ? 1 : 0});
      audit.append(caller.user.id, featured ? 'listing.feature' : 'listing.unfeature', 'listing', listingId);
      return r;
    });
  }

  /// The penalty clause: suspends [username], unlists **all** of their
  /// listings and revokes every session (so every access and refresh token)
  /// they hold. Each cascaded unlist is audited.
  UserRecord suspend(AuthContext caller, String username, Map<String, Object?> body) {
    _requireModerator(caller);
    final user = users.findByUsername(username);
    if (user == null) throw ApiException.notFound('No such user.');
    if (user.id == caller.user.id) throw ApiException.forbidden('You cannot suspend yourself.');
    if (user.role != UserRole.user && !caller.isAdmin) throw ApiException.forbidden('Only admins can suspend staff.');
    final reason = (body['reason'] as String? ?? '').trim();
    if (reason.isEmpty) throw ApiException.validation('Give a reason.', {'field': 'reason'});
    return transaction(db, () {
      final suspended = users.setStatus(user.id, UserStatus.suspended, reason: reason);
      var unlisted = 0;
      for (final listing in listings.byPublisher(user.id)) {
        if (listing.status == ListingStatus.unlisted && listing.unlistedBy == 'moderator') continue;
        if (listing.status == ListingStatus.draft && listing.latestVersionId == null) {
          listings.update(listing.id, {'status': ListingStatus.unlisted.wire, 'unlisted_by': 'moderator', 'unlisted_reason': reason});
          continue;
        }
        _unlist(caller.user.id, listing, 'Publisher suspended: $reason', {'cascade': 'user.suspend'});
        unlisted++;
      }
      final revoked = sessions.revokeAllForUser(user.id, 'suspended');
      audit.append(caller.user.id, 'user.suspend', 'user', user.id,
          {'username': user.username, 'reason': reason, 'unlistedListings': unlisted, 'revokedSessions': revoked});
      return suspended;
    });
  }

  UserRecord unsuspend(AuthContext caller, String username) {
    _requireModerator(caller);
    final user = users.findByUsername(username);
    if (user == null) throw ApiException.notFound('No such user.');
    return transaction(db, () {
      final r = users.setStatus(user.id, UserStatus.active);
      audit.append(caller.user.id, 'user.unsuspend', 'user', user.id, {'username': user.username});
      return r;
    });
  }

  UserRecord setRole(AuthContext caller, String username, Map<String, Object?> body) {
    if (!caller.isAdmin) throw ApiException.forbidden('Admins only.');
    final user = users.findByUsername(username);
    if (user == null) throw ApiException.notFound('No such user.');
    final role = UserRole.values.where((r) => r.wire == body['role']).firstOrNull;
    if (role == null) throw ApiException.validation('role is user, moderator or admin.');
    return transaction(db, () {
      final r = users.update(user.id, role: role);
      audit.append(caller.user.id, 'user.role', 'user', user.id, {'username': user.username, 'role': role.wire});
      return r;
    });
  }

  List<AuditEntry> auditLog(AuthContext caller, {int limit = 100}) {
    _requireModerator(caller);
    return [
      for (final a in audit.list(limit: limit.clamp(1, 1000)))
        AuditEntry(
          id: a.id,
          actor: a.actorUsername,
          action: a.action,
          targetType: a.targetType,
          targetId: a.targetId,
          details: a.details,
          createdAt: DateTime.parse(a.createdAt),
        ),
    ];
  }
}
