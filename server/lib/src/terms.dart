import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

/// The publishing terms. Bump [version] whenever the text changes: an
/// attestation is only accepted against the current version, and every stored
/// attestation records which version its publisher accepted.
const publishingTerms = Terms(
  version: '2026-09-27',
  attestationStatement: 'I own this work or have the right to publish it under the chosen license.',
  penalty: 'Publishing work you do not own — in particular someone else\'s paid assets — lets the marketplace '
      'moderators remove all of your listings from the marketplace, suspend your account and revoke every session '
      'and token it holds. The marketplace cannot delete files on anyone\'s computer: the penalty removes your '
      'marketplace content and your access to it.',
  text: '''
# Lumina Marketplace publishing terms (2026-09-27)

## 1. Free licenses only
Every version you publish declares a free license from the marketplace allow-list, one per kind of work it
contains: a **content** license (CC0-1.0, CC-BY-4.0, CC-BY-SA-4.0) for models, textures, sounds, animations,
materials, themes and other assets, and a **code** license (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, MPL-2.0,
Zlib) for plugins, scripts and game-template code. A listing that contains both declares one of each. Paid
listings are not available yet: every listing is free.

## 2. Ownership attestation
Before a version is published you confirm: *"I own this work or have the right to publish it under the chosen
license."* The marketplace stores that confirmation permanently with your account, the time, a hash of your IP
address, the listing and version, and the version of these terms.

## 3. Penalty
Publishing work you do not own — in particular someone else's paid assets — lets the marketplace moderators remove
**all** of your listings from the marketplace, suspend your account and revoke every session and token it holds.
The marketplace cannot delete files on anyone's computer: the penalty removes your marketplace content and your
access to it.

## 4. Reports and moderation
Anyone signed in can report a listing. Moderators review reports, can unlist and restore listings, and can suspend
publishers. Every moderation action is recorded in an append-only audit log.
''',
);
