/// Whether a license covers content (models, images, sounds) or code.
enum LicenseKind {
  content('content', 'Content'),
  code('code', 'Code');

  const LicenseKind(this.wire, this.label);
  final String wire;
  final String label;

  static LicenseKind? tryParse(String? wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

/// One entry of the free-license allow-list.
class LicenseInfo {
  const LicenseInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    required this.attributionRequired,
    required this.shareAlike,
    required this.summary,
  });

  /// The SPDX identifier (`CC0-1.0`, `MIT`, …).
  final String id;
  final String name;
  final LicenseKind kind;

  /// The canonical license text.
  final String url;

  /// The SPDX page for the identifier.
  String get spdxUrl => 'https://spdx.org/licenses/$id.html';

  /// Users must credit the author (CC-BY, MIT notice, …).
  final bool attributionRequired;

  /// Derivatives must use the same license (CC-BY-SA, MPL file-level).
  final bool shareAlike;

  /// One line for pickers.
  final String summary;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.wire,
        'url': url,
        'spdxUrl': spdxUrl,
        'attributionRequired': attributionRequired,
        'shareAlike': shareAlike,
        'summary': summary,
      };

  factory LicenseInfo.fromJson(Map<String, Object?> json) => LicenseInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: LicenseKind.tryParse(json['kind'] as String?) ?? LicenseKind.content,
        url: json['url'] as String,
        attributionRequired: json['attributionRequired'] as bool? ?? false,
        shareAlike: json['shareAlike'] as bool? ?? false,
        summary: json['summary'] as String? ?? '',
      );

  @override
  String toString() => id;
}

/// The only licenses a listing version may declare: free licenses, split by
/// kind. Publishing is free-only for now, so non-free licenses ("Proprietary",
/// "All rights reserved", CC-NC/ND) are not on the list and the API rejects
/// them.
const List<LicenseInfo> licenseCatalogue = [
  LicenseInfo(
    id: 'CC0-1.0',
    name: 'Creative Commons Zero v1.0 Universal',
    kind: LicenseKind.content,
    url: 'https://creativecommons.org/publicdomain/zero/1.0/legalcode',
    attributionRequired: false,
    shareAlike: false,
    summary: 'Public domain dedication: use for anything, no credit required.',
  ),
  LicenseInfo(
    id: 'CC-BY-4.0',
    name: 'Creative Commons Attribution 4.0 International',
    kind: LicenseKind.content,
    url: 'https://creativecommons.org/licenses/by/4.0/legalcode',
    attributionRequired: true,
    shareAlike: false,
    summary: 'Use for anything, including commercially, with credit to the author.',
  ),
  LicenseInfo(
    id: 'CC-BY-SA-4.0',
    name: 'Creative Commons Attribution Share Alike 4.0 International',
    kind: LicenseKind.content,
    url: 'https://creativecommons.org/licenses/by-sa/4.0/legalcode',
    attributionRequired: true,
    shareAlike: true,
    summary: 'Use with credit; adaptations must be shared under the same license.',
  ),
  LicenseInfo(
    id: 'MIT',
    name: 'MIT License',
    kind: LicenseKind.code,
    url: 'https://opensource.org/license/mit',
    attributionRequired: true,
    shareAlike: false,
    summary: 'Permissive: keep the copyright and license notice.',
  ),
  LicenseInfo(
    id: 'Apache-2.0',
    name: 'Apache License 2.0',
    kind: LicenseKind.code,
    url: 'https://www.apache.org/licenses/LICENSE-2.0',
    attributionRequired: true,
    shareAlike: false,
    summary: 'Permissive with an explicit patent grant; keep the NOTICE file.',
  ),
  LicenseInfo(
    id: 'BSD-2-Clause',
    name: 'BSD 2-Clause "Simplified" License',
    kind: LicenseKind.code,
    url: 'https://opensource.org/license/bsd-2-clause',
    attributionRequired: true,
    shareAlike: false,
    summary: 'Permissive: keep the copyright notice.',
  ),
  LicenseInfo(
    id: 'BSD-3-Clause',
    name: 'BSD 3-Clause "New" or "Revised" License',
    kind: LicenseKind.code,
    url: 'https://opensource.org/license/bsd-3-clause',
    attributionRequired: true,
    shareAlike: false,
    summary: 'Permissive: keep the notice; no endorsement using the author\'s name.',
  ),
  LicenseInfo(
    id: 'MPL-2.0',
    name: 'Mozilla Public License 2.0',
    kind: LicenseKind.code,
    url: 'https://www.mozilla.org/en-US/MPL/2.0/',
    attributionRequired: true,
    shareAlike: true,
    summary: 'File-level copyleft: changes to MPL files stay MPL.',
  ),
  LicenseInfo(
    id: 'Zlib',
    name: 'zlib License',
    kind: LicenseKind.code,
    url: 'https://opensource.org/license/zlib',
    attributionRequired: false,
    shareAlike: false,
    summary: 'Permissive: altered versions must be marked as such.',
  ),
];

LicenseInfo? licenseById(String? id) {
  if (id == null) return null;
  for (final l in licenseCatalogue) {
    if (l.id == id) return l;
  }
  return null;
}

List<LicenseInfo> licensesOfKind(LicenseKind kind) =>
    [for (final l in licenseCatalogue) if (l.kind == kind) l];

/// A version's declared licenses: at most one per kind.
class LicenseSelection {
  const LicenseSelection({this.content, this.code});

  /// SPDX id of the content license, or null.
  final String? content;

  /// SPDX id of the code license, or null.
  final String? code;

  String? operator [](LicenseKind kind) => kind == LicenseKind.content ? content : code;

  List<String> get ids => [?content, ?code];
}

/// One reason a [LicenseSelection] cannot be published.
class LicenseProblem {
  const LicenseProblem(this.code, this.kind, this.message);

  /// `license_required`, `license_unknown` (not on the free allow-list) or
  /// `license_wrong_kind` (a code license in the content slot, …).
  final String code;
  final LicenseKind kind;
  final String message;

  Map<String, Object?> toJson() => {'code': code, 'kind': kind.wire, 'message': message};

  @override
  String toString() => message;
}

/// Checks [selection] against the kinds a version needs. The server and the
/// web publish flow run the same check, so the UI refuses exactly what the API
/// would refuse.
List<LicenseProblem> licenseProblems(Set<LicenseKind> required, LicenseSelection selection) {
  final problems = <LicenseProblem>[];
  for (final kind in LicenseKind.values) {
    final id = selection[kind];
    if (id == null || id.isEmpty) {
      if (required.contains(kind)) {
        problems.add(LicenseProblem(
          'license_required',
          kind,
          'A ${kind.wire} license is required: this version contains ${kind.wire}.',
        ));
      }
      continue;
    }
    final info = licenseById(id);
    if (info == null) {
      problems.add(LicenseProblem(
        'license_unknown',
        kind,
        '"$id" is not on the free-license allow-list (${licensesOfKind(kind).map((l) => l.id).join(', ')}).',
      ));
    } else if (info.kind != kind) {
      problems.add(LicenseProblem(
        'license_wrong_kind',
        kind,
        '$id is a ${info.kind.wire} license, not a ${kind.wire} license.',
      ));
    }
  }
  return problems;
}
