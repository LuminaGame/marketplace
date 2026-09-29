import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

/// Zips real files from test-assets into a temp dir and returns the path.
String zipOf(Directory tmp, String name, Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((path, bytes) => archive.addFile(ArchiveFile.bytes(path, bytes)));
  final file = File('${tmp.path}/$name')..writeAsBytesSync(ZipEncoder().encode(archive));
  return file.path;
}

void main() {
  late TestBackend backend;
  late Directory tmp;
  setUpAll(() async {
    backend = await TestBackend.start();
    tmp = Directory.systemTemp.createTempSync('mkt_web_publish_');
  });
  tearDownAll(() async {
    await backend.stop();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('the publish flow refuses to continue without a license per kind and without the attestation; '
      'the price field is disabled "Free only for now"; publishing a CC0 model shows it under My listings and in search',
      (tester) async {
    final client = backend.client();
    await tester.runAsync(() => signUpUser(client, 'candlemaker'));
    final candles = Directory('$testAssetsDir/Props/Candles').listSync().whereType<File>().where((f) => f.path.endsWith('.glb')).toList();
    final zip = zipOf(tmp, 'candles.zip', {for (final f in candles) f.uri.pathSegments.last: f.readAsBytesSync()});
    final files = QueuedFileSource([logoPng, zip]);
    await pumpApp(tester, client, location: '/publish', files: files);

    // Price: disabled, free only.
    final price = tester.widget<TextField>(find.byKey(const ValueKey('publish_price')));
    expect(price.enabled, isFalse);
    expect(find.text('Free only for now'), findsOneWidget);

    // Details → the draft listing.
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')));
    expect(find.text('Pick a category.'), findsOneWidget);
    await choose(tester, const ValueKey('publish_category'), const ValueKey('publish_category_model'));
    await tester.enterText(find.byKey(const ValueKey('publish_title')), 'Candle Collection');
    await tester.enterText(find.byKey(const ValueKey('publish_description')), '# Candles\n\nWax candles for **cosy** scenes.');
    await tester.enterText(find.byKey(const ValueKey('publish_tags')), 'candle, light, prop');
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_add_screenshot')));

    // Screenshot (a real PNG).
    await tapOn(tester, find.byKey(const ValueKey('publish_add_screenshot')), until: find.bySemanticsLabel(RegExp('Candle Collection screenshot 1')));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_choose_file')));

    // Upload: required.
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')));
    expect(find.text('Upload the .zip archive first.'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_choose_file')), until: find.byKey(const ValueKey('publish_upload_summary')));
    expect(find.textContaining('candles.zip'), findsOneWidget);
    expect(find.text('Contains: content.'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_license_content')));

    // Licenses: a content license is required; no code picker for a mesh-only zip.
    expect(find.byKey(const ValueKey('publish_license_code')), findsNothing);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')));
    expect(find.textContaining('A content license is required'), findsOneWidget);
    await choose(tester, const ValueKey('publish_license_content'), const ValueKey('publish_license_option_CC0-1.0'));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_attestation')));

    // Attestation: required; the penalty is explained.
    expect(find.byKey(const ValueKey('publish_penalty')), findsOneWidget);
    expect(find.textContaining('remove all of your listings'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_submit')));
    expect(find.textContaining('Tick the ownership attestation'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_attestation')));
    await tapOn(tester, find.byKey(const ValueKey('publish_submit')), until: find.byKey(const ValueKey('publish_done')));
    expect(find.text('Candle Collection v1.0.0 is live.'), findsOneWidget);

    // My listings.
    await tapOn(tester, find.byKey(const ValueKey('publish_my_listings')), until: find.byKey(const ValueKey('my_listing_candle-collection')));
    expect(find.descendant(of: find.byKey(const ValueKey('my_listing_candle-collection')), matching: find.text('Published')), findsOneWidget);

    // Search.
    await tester.enterText(find.byKey(const ValueKey('shell_search')), 'candle');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, until: find.byKey(const ValueKey('listing_card_candle-collection')));

    // The server holds what the flow sent.
    final published = await tester.runAsync(() => client.listing('candle-collection'));
    expect(published!.licenses.content, 'CC0-1.0');
    expect(published.tags, ['candle', 'light', 'prop']);
    expect(published.screenshots, hasLength(1));
    expect(published.latestVersion!.fileCount, candles.length);
    expect(files.paths, isEmpty);
  });

  testWidgets('a game template is checked against the template format when it is uploaded; '
      'a valid one publishes with a content and a code license', (tester) async {
    final client = backend.client();
    await tester.runAsync(() => signUpUser(client));
    // The server's fixture: a real Lumina project packed as a game template.
    final fixture = Directory('../server/test/fixtures/game_template/Arena');
    final arena = {
      for (final f in fixture.listSync(recursive: true).whereType<File>())
        'Arena/${f.path.substring(fixture.path.length + 1).replaceAll(r'\', '/')}': f.readAsBytesSync(),
    };
    final broken = zipOf(tmp, 'arena_broken.zip', Map.of(arena)..removeWhere((path, _) => path.startsWith('Arena/contents/')));
    final valid = zipOf(tmp, 'arena.zip', arena);
    await pumpApp(tester, client, location: '/publish', files: QueuedFileSource([broken, valid]));
    await choose(tester, const ValueKey('publish_category'), const ValueKey('publish_category_game_template'));
    await tester.enterText(find.byKey(const ValueKey('publish_title')), 'Arena Starter');
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_add_screenshot')));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_choose_file')));
    expect(find.byKey(const ValueKey('publish_template_format')), findsOneWidget);
    expect(find.textContaining('contents/ (levels and assets)'), findsOneWidget);

    // Without contents/: refused on upload with the server's template message.
    await tapOn(tester, find.byKey(const ValueKey('publish_choose_file')),
        until: find.textContaining('The game template was refused: it has no contents/ folder'));
    expect(find.byKey(const ValueKey('publish_upload_summary')), findsNothing);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')));
    expect(find.text('Upload the .zip archive first.'), findsOneWidget);

    // The valid template uploads and publishes (content + code licenses).
    await tapOn(tester, find.byKey(const ValueKey('publish_choose_file')), until: find.byKey(const ValueKey('publish_upload_summary')));
    expect(find.textContaining('arena.zip'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_license_code')));
    await choose(tester, const ValueKey('publish_license_content'), const ValueKey('publish_license_option_CC-BY-4.0'));
    await choose(tester, const ValueKey('publish_license_code'), const ValueKey('publish_license_option_MIT'));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_attestation')));
    await tapOn(tester, find.byKey(const ValueKey('publish_attestation')));
    await tapOn(tester, find.byKey(const ValueKey('publish_submit')), until: find.byKey(const ValueKey('publish_done')));
    final l = await tester.runAsync(() => client.listing('arena-starter'));
    expect(l!.category, ListingCategory.gameTemplate);
    expect(l.latestVersion!.fileCount, arena.length);
    final manifest = await tester.runAsync(() => client.manifest(l.id, '1.0.0'));
    expect(manifest!.targetRoot, 'templates/Arena/');
  });

  testWidgets('choosing Plugin asks for the package first and fills the listing from its .lmplugin; '
      'the declared license is locked; the version and release notes come from the manifest and CHANGELOG.md', (tester) async {
    final client = backend.client();
    await tester.runAsync(() => signUpUser(client, 'pcg_publisher'));
    // The workspace's real lumina_plugin_pcg: with a non-free LICENSE and no
    // "license" key (as it was before its commit 7d66ca2); with a stray
    // executable; then as a user zips the folder today (MIT, dot
    // files, test/, generated build/ and .dart_tool/ files).
    final nonFree = zipOf(tmp, 'lumina_plugin_pcg_non_free.zip',
        pcgPluginFiles(manifestExtra: {'license': null}, license: allRightsReservedText));
    final withExe = zipOf(tmp, 'lumina_plugin_pcg_exe.zip',
        pcgPluginFiles(asFolder: true)..['lumina_plugin_pcg/tools/run.exe'] = [0x4D, 0x5A, 0x90, 0]);
    final mit = zipOf(tmp, 'lumina_plugin_pcg.zip', pcgPluginFiles(asFolder: true));
    final files = QueuedFileSource([nonFree, withExe, mit, logoPng]);
    await pumpApp(tester, client, location: '/publish', files: files);

    // Plugin → the Upload step comes first.
    await choose(tester, const ValueKey('publish_category'), const ValueKey('publish_category_plugin'));
    await settle(tester, until: find.byKey(const ValueKey('publish_choose_file')));
    expect(find.byKey(const ValueKey('publish_plugin_format')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('publish_step_upload')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('publish_step_details')), matching: find.text('2')), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')));
    expect(find.text('Upload the plugin package (a .zip of the plugin folder) first.'), findsOneWidget);

    // The package as it is: refused with the server's message.
    await tapOn(tester, find.byKey(const ValueKey('publish_choose_file')),
        until: find.textContaining('The plugin package was refused: LICENSE reads "All rights reserved"'));
    expect(find.byKey(const ValueKey('publish_plugin_summary')), findsNothing);

    // An executable is refused, and the message names it.
    await tapOn(tester, find.byKey(const ValueKey('publish_choose_file')),
        until: find.textContaining('.exe files are not allowed (lumina_plugin_pcg/tools/run.exe)'));

    // The folder zip: build/ and .dart_tool/ are left out (a note says so).
    await tapOn(tester, find.byKey(const ValueKey('publish_choose_file')), until: find.byKey(const ValueKey('publish_plugin_summary')));
    expect(find.byKey(const ValueKey('publish_upload_skipped')), findsOneWidget);
    expect(find.textContaining('lumina_plugin_pcg/.dart_tool/, lumina_plugin_pcg/build/'), findsOneWidget);
    expect(find.textContaining('lumina_plugin_pcg/.gitignore'), findsOneWidget, reason: 'listed with the stored files');
    expect(find.text('Read from lumina_plugin_pcg.lmplugin'), findsOneWidget);
    expect(find.textContaining('MIT (from lumina_plugin_pcg.lmplugin)'), findsOneWidget);
    expect(find.textContaining('0.1.0 section of CHANGELOG.md'), findsOneWidget);

    // Details: filled from the manifest.
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_title')));
    String field(String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    expect(field('publish_title'), 'Procedural Content Generation');
    expect(field('publish_description'), startsWith('PCG Graph assets and PCG Volume actors'));
    expect(field('publish_tags'), 'procedural, plugin');
    expect(field('publish_engine'), '0.0.1');
    expect(find.byKey(const ValueKey('publish_details_from_manifest')), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_add_screenshot')));
    await tapOn(tester, find.byKey(const ValueKey('publish_add_screenshot')),
        until: find.bySemanticsLabel(RegExp('Procedural Content Generation screenshot 1')));

    // Screenshots → Licenses (the upload is done): MIT locked, content picked for the icon.
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_license_code')));
    expect(tester.widget<Select<String>>(find.byKey(const ValueKey('publish_license_code'))).enabled, isFalse);
    expect(find.byKey(const ValueKey('publish_license_source_code')), findsOneWidget);
    expect(find.textContaining('Declared by lumina_plugin_pcg.lmplugin'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')));
    expect(find.textContaining('A content license is required'), findsOneWidget);
    await choose(tester, const ValueKey('publish_license_content'), const ValueKey('publish_license_option_CC-BY-4.0'));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_attestation')));

    // Publish: the manifest version (read-only) and the changelog's notes.
    final versionField = tester.widget<TextField>(find.byKey(const ValueKey('publish_version')));
    expect(versionField.controller!.text, '0.1.0');
    expect(versionField.enabled, isFalse);
    expect(field('publish_release_notes'), startsWith('- Initial release'));
    await tapOn(tester, find.byKey(const ValueKey('publish_changelog_toggle')), until: find.byKey(const ValueKey('publish_changelog')));
    expect(find.descendant(of: find.byKey(const ValueKey('publish_changelog')), matching: find.text('Unreleased')), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_attestation')));
    await tapOn(tester, find.byKey(const ValueKey('publish_submit')), until: find.byKey(const ValueKey('publish_done')));
    expect(find.text('Procedural Content Generation v0.1.0 is live.'), findsOneWidget);

    final l = await tester.runAsync(() => client.listing('procedural-content-generation'));
    expect(l!.category, ListingCategory.plugin);
    expect(l.tags, ['procedural', 'plugin']);
    expect(l.engineVersion, '0.0.1');
    expect(l.description, startsWith('PCG Graph assets'));
    expect(l.licenses.ids, ['CC-BY-4.0', 'MIT']);
    expect(l.versions!.single.version, '0.1.0');
    expect(l.versions!.single.releaseNotes, contains('`pcg.generate` console command'));
    expect(files.paths, isEmpty);
  }, skip: skipUnlessPluginBuilt('lumina_plugin_pcg') != null);

  testWidgets('a plugin package that declares no license: the publisher picks them, and a code license is required',
      (tester) async {
    final client = backend.client();
    await tester.runAsync(() => signUpUser(client));
    final zip = zipOf(tmp, 'spinner.zip', {
      'spinner/spinner.lmplugin': utf8.encode(jsonEncode({
        'name': 'spinner',
        'friendly_name': 'Spinner Plugin',
        'version': '1.0.0',
        'description': 'Spins actors.',
        'engine_version': '^0.0.1',
      })),
      'spinner/pubspec.yaml': utf8.encode('name: spinner\n'),
      'spinner/lib/spinner.dart': utf8.encode('// spins actors\n'),
      'spinner/resources/icon.png': File(logoPng).readAsBytesSync(),
    });
    await pumpApp(tester, client, location: '/publish', files: QueuedFileSource([zip]));
    await choose(tester, const ValueKey('publish_category'), const ValueKey('publish_category_plugin'));
    await tapOn(tester, find.byKey(const ValueKey('publish_choose_file')), until: find.byKey(const ValueKey('publish_plugin_summary')));
    expect(find.textContaining('none declared'), findsOneWidget);
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_title')));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_add_screenshot')));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_license_code')));
    expect(find.byKey(const ValueKey('publish_license_content')), findsOneWidget, reason: 'the icon is content');
    expect(find.byKey(const ValueKey('publish_license_hint')), findsOneWidget);
    expect(tester.widget<Select<String>>(find.byKey(const ValueKey('publish_license_code'))).enabled, isTrue);

    await choose(tester, const ValueKey('publish_license_content'), const ValueKey('publish_license_option_CC-BY-4.0'));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')));
    expect(find.textContaining('A code license is required'), findsOneWidget);
    await choose(tester, const ValueKey('publish_license_code'), const ValueKey('publish_license_option_MIT'));
    await tapOn(tester, find.byKey(const ValueKey('publish_continue')), until: find.byKey(const ValueKey('publish_attestation')));
    await tapOn(tester, find.byKey(const ValueKey('publish_attestation')));
    await tapOn(tester, find.byKey(const ValueKey('publish_submit')), until: find.byKey(const ValueKey('publish_done')));
    final l = await tester.runAsync(() => client.listing('spinner-plugin'));
    expect(l!.licenses.ids, ['CC-BY-4.0', 'MIT']);
    expect(l.category, ListingCategory.plugin);
    expect(l.latestVersion!.version, '1.0.0');
  });
}
