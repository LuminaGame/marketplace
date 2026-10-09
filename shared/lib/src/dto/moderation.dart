part of '../dto.dart';

enum ReportReason {
  stolenContent('stolen_content', "Someone else's (paid) work"),
  licenseViolation('license_violation', 'Wrong or violated license'),
  malware('malware', 'Malware or harmful code'),
  broken('broken', 'Broken or not as described'),
  inappropriate('inappropriate', 'Inappropriate content'),
  spam('spam', 'Spam'),
  other('other', 'Other');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;

  static ReportReason? tryParse(String? wire) {
    for (final r in values) {
      if (r.wire == wire) return r;
    }
    return null;
  }
}

enum ReportStatus {
  open('open'),
  dismissed('dismissed'),
  actioned('actioned');

  const ReportStatus(this.wire);
  final String wire;

  static ReportStatus parse(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => ReportStatus.open);
}

class ListingReport {
  const ListingReport({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.listingStatus,
    required this.publisher,
    required this.reporter,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
    this.resolvedBy,
    this.resolvedAt,
    this.resolutionNote,
  });

  final String id;
  final String listingId;
  final String listingTitle;
  final ListingStatus listingStatus;
  final PublisherSummary publisher;
  final String reporter;
  final ReportReason reason;
  final String details;
  final ReportStatus status;
  final DateTime createdAt;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final String? resolutionNote;

  Map<String, Object?> toJson() => {
        'id': id,
        'listingId': listingId,
        'listingTitle': listingTitle,
        'listingStatus': listingStatus.wire,
        'publisher': publisher.toJson(),
        'reporter': reporter,
        'reason': reason.wire,
        'details': details,
        'status': status.wire,
        'createdAt': createdAt.toIso8601String(),
        'resolvedBy': resolvedBy,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'resolutionNote': resolutionNote,
      };

  factory ListingReport.fromJson(Map<String, Object?> j) => ListingReport(
        id: j['id'] as String,
        listingId: j['listingId'] as String,
        listingTitle: j['listingTitle'] as String,
        listingStatus: ListingStatus.parse(j['listingStatus'] as String?),
        publisher: PublisherSummary.fromJson(_map(j['publisher'])),
        reporter: j['reporter'] as String,
        reason: ReportReason.tryParse(j['reason'] as String?) ?? ReportReason.other,
        details: j['details'] as String? ?? '',
        status: ReportStatus.parse(j['status'] as String?),
        createdAt: _date(j['createdAt']),
        resolvedBy: j['resolvedBy'] as String?,
        resolvedAt: _dateOrNull(j['resolvedAt']),
        resolutionNote: j['resolutionNote'] as String?,
      );
}

/// An immutable moderation/audit record.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.details,
    required this.createdAt,
  });

  final int id;

  /// Username of whoever acted (`system` for automatic cascades).
  final String actor;

  /// `listing.unlist`, `listing.restore`, `user.suspend`, `report.resolve`, …
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, Object?> details;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'actor': actor,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'details': details,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AuditEntry.fromJson(Map<String, Object?> j) => AuditEntry(
        id: j['id'] as int,
        actor: j['actor'] as String,
        action: j['action'] as String,
        targetType: j['targetType'] as String,
        targetId: j['targetId'] as String,
        details: _map(j['details'] ?? const <String, Object?>{}),
        createdAt: _date(j['createdAt']),
      );
}

/// `GET /terms`: the publishing terms, including the ownership attestation and
/// its penalty clause.
class Terms {
  const Terms({required this.version, required this.attestationStatement, required this.penalty, required this.text});

  final String version;

  /// The checkbox label the uploader ticks.
  final String attestationStatement;

  /// What happens to a publisher who publishes someone else's work.
  final String penalty;

  /// The full terms (Markdown).
  final String text;

  Map<String, Object?> toJson() =>
      {'version': version, 'attestationStatement': attestationStatement, 'penalty': penalty, 'text': text};

  factory Terms.fromJson(Map<String, Object?> j) => Terms(
        version: j['version'] as String,
        attestationStatement: j['attestationStatement'] as String,
        penalty: j['penalty'] as String,
        text: j['text'] as String,
      );
}

/// A public profile: the user plus their published listings.
class PublisherProfile {
  const PublisherProfile({required this.publisher, required this.listings, required this.joinedAt});

  final PublisherSummary publisher;
  final List<Listing> listings;
  final DateTime joinedAt;

  Map<String, Object?> toJson() => {
        'publisher': publisher.toJson(),
        'joinedAt': joinedAt.toIso8601String(),
        'listings': [for (final l in listings) l.toJson()],
      };

  factory PublisherProfile.fromJson(Map<String, Object?> j) => PublisherProfile(
        publisher: PublisherSummary.fromJson(_map(j['publisher'])),
        joinedAt: _date(j['joinedAt']),
        listings: [for (final l in j['listings'] as List) Listing.fromJson(_map(l))],
      );
}

/// The answer to a crash report (`POST /crash-reports`): the id the server
/// filed it under and when it arrived.
class CrashReportReceipt {
  const CrashReportReceipt({required this.id, required this.receivedAt});

  final String id;
  final DateTime receivedAt;

  Map<String, Object?> toJson() => {'id': id, 'receivedAt': receivedAt.toIso8601String()};

  factory CrashReportReceipt.fromJson(Map<String, Object?> j) =>
      CrashReportReceipt(id: j['id'] as String, receivedAt: _date(j['receivedAt']));
}
