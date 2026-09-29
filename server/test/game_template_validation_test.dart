import 'dart:convert';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

/// Game template archives are checked against the template format
/// (v1) when a version is published — and, when the upload names the
/// category, already on upload — so Lumina Studio never installs a template
/// it cannot turn into a project.
///
/// The template is `test/fixtures/game_template/Arena/`: a real Lumina
/// project scaffolded by lumina's `ProjectRepository` (first-person template)
/// and packed in the format — see [arenaTemplateFiles].
void main() {
  late TestServer server;
  late MarketplaceClient publisher;
  late Terms terms;

  setUp(() async {
    server = await TestServer.start();
    publisher = server.client();
    await signUp(publisher, username: 'arena_maker');
    terms = await publisher.terms();
  });

  const bothLicenses = LicenseSelection(content: 'CC-BY-4.0', code: 'MIT');

  /// Creates a game template listing and publishes [zip] as 1.0.0.
  Future<(Listing, ListingVersion)> publishTemplate(List<int> zip, {String title = 'Arena Template', ListingCategory? uploadCategory}) async {
    final listing = await publisher.createListing(NewListing(category: ListingCategory.gameTemplate, title: title));
    final upload = await publisher.upload(zip, fileName: 'arena.zip', category: uploadCategory);
    final v = await publisher.publishVersion(listing.id,
        NewVersion(version: '1.0.0', uploadId: upload.id, licenses: bothLicenses, attestation: true, termsVersion: terms.version));
    return (listing, v);
  }

  /// Expects publishing [zip] to be refused with 422 invalid_template whose
  /// details name [problem] (and [path], when given); returns the error.
  Future<MarketplaceException> refused(List<int> zip, String problem, {String? path}) async {
    try {
      await publishTemplate(zip);
      fail('the template was published');
    } on MarketplaceException catch (e) {
      expect(e.statusCode, 422, reason: e.message);
      expect(e.code, 'invalid_template', reason: e.message);
      expect(e.details['problem'], problem, reason: e.message);
      if (path != null) expect(e.details['path'], path, reason: e.message);
      expect(e.message, startsWith('The game template was refused: '));
      return e;
    }
  }

  test('Arena/{template.json, arena.lmproject, pubspec.yaml, contents/levels/L_DefaultLevel.lmas, lib/main.dart} '
      'publishes with CC-BY-4.0 + MIT → 201, and its manifest targets templates/Arena/…', () async {
    final files = arenaTemplateFiles();
    expect(files.keys, containsAll(['template.json', 'arena.lmproject', 'pubspec.yaml', 'contents/levels/L_DefaultLevel.lmas', 'lib/main.dart']));
    final (listing, v) = await publishTemplate(templateZip(files));
    expect(v.licenses.ids, ['CC-BY-4.0', 'MIT']);
    expect(v.fileCount, files.length);

    final buyer = server.client();
    await signUp(buyer);
    await buyer.getListing(listing.id);
    final manifest = await buyer.manifest(listing.id, '1.0.0');
    expect(manifest.installKind, InstallKind.gameTemplate);
    expect(manifest.targetRoot, 'templates/Arena/');
    expect(manifest.files.map((f) => f.target),
        containsAll(['templates/Arena/template.json', 'templates/Arena/arena.lmproject', 'templates/Arena/contents/levels/L_DefaultLevel.lmas']));
    expect(manifest.files.every((f) => f.target.startsWith('templates/Arena/')), isTrue);
  });

  test('without contents/ → 422; template.json without a title and no .lmproject → 422; two .lmproject files → 422', () async {
    final noContents = arenaTemplateFiles()..removeWhere((path, _) => path.startsWith('contents/'));
    final e = await refused(templateZip(noContents), 'missing_contents');
    expect(e.message, contains('contents/'));

    final untitled = arenaTemplateFiles()
      ..remove('arena.lmproject')
      ..['template.json'] = utf8.encode(jsonEncode({'format': 1, 'description': 'No title', 'thumbnail': 'thumbnail.png'}));
    await refused(templateZip(untitled), 'manifest_no_title', path: 'Arena/template.json');

    final twoProjects = arenaTemplateFiles()..['arena_copy.lmproject'] = arenaTemplateFiles()['arena.lmproject']!;
    final two = await refused(templateZip(twoProjects), 'multiple_projects');
    expect(two.message, contains('2 .lmproject files'));

    final brokenProject = arenaTemplateFiles()..['arena.lmproject'] = utf8.encode('{"engine_version": "0.0.1"}');
    await refused(templateZip(brokenProject), 'project_invalid', path: 'Arena/arena.lmproject');
  });

  test('a zip carrying linux/CMakeLists.txt or build/app.so → 422 naming the path', () async {
    final linux = arenaTemplateFiles()..['linux/CMakeLists.txt'] = utf8.encode('project(arena)\n');
    final e = await refused(templateZip(linux), 'excluded_path', path: 'Arena/linux/CMakeLists.txt');
    expect(e.message, contains('Arena/linux/CMakeLists.txt'));

    final dartTool = arenaTemplateFiles()..['.dart_tool/package_config.json'] = utf8.encode('{}');
    await refused(templateZip(dartTool), 'excluded_path', path: 'Arena/.dart_tool/package_config.json');

    // The publisher's local pub overrides name folders on their machine.
    final overrides = arenaTemplateFiles()
      ..['pubspec_overrides.yaml'] = utf8.encode('dependency_overrides:\n  lumina:\n    path: D:/lumina/lumina\n');
    final o = await refused(templateZip(overrides), 'excluded_path', path: 'Arena/pubspec_overrides.yaml');
    expect(o.message, contains('pubspec_overrides.yaml'));

    // .so is never an allowed upload; with the category the template rule
    // answers first, so the publisher learns why the folder does not belong.
    final build = templateZip(arenaTemplateFiles()..['build/app.so'] = [0x7f, 0x45, 0x4c, 0x46]);
    await expectLater(
        publisher.upload(build, fileName: 'arena.zip', category: ListingCategory.gameTemplate),
        throwsA(isA<MarketplaceException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.code, 'code', 'invalid_template')
            .having((e) => e.details['path'], 'path', 'Arena/build/app.so')
            .having((e) => e.message, 'message', contains('Arena/build/app.so'))));
    await expectLater(
        publisher.upload(build, fileName: 'arena.zip'),
        throwsA(isA<MarketplaceException>()
            .having((e) => e.code, 'code', 'invalid_archive')
            .having((e) => e.details['path'], 'path', 'Arena/build/app.so')));
  });

  test('a template.json thumbnail that is not in the archive → 422', () async {
    final files = arenaTemplateFiles()..remove('thumbnail.png');
    final e = await refused(templateZip(files), 'thumbnail_missing', path: 'Arena/template.json');
    expect(e.message, contains('thumbnail.png'));
  });

  test('pubspec path dependencies: lumina is linked by Studio; others must be vendored inside the template', () async {
    final pubspec = utf8.decode(arenaTemplateFiles()['pubspec.yaml']!);
    expect(pubspec, contains('lumina:\n    git:\n      url: $kLuminaEngineGitUrl\n      path: lumina\n'),
        reason: 'the scaffolded project depends on the engine through git');
    String withDep(String dep) => pubspec.replaceFirst('dependencies:\n', 'dependencies:\n$dep');

    final outside = arenaTemplateFiles()..['pubspec.yaml'] = utf8.encode(withDep('  my_utils:\n    path: /home/publisher/my_utils\n'));
    final e = await refused(templateZip(outside), 'path_dependency', path: 'Arena/pubspec.yaml');
    expect(e.message, allOf(contains('my_utils'), contains('vendor')));

    final vendored = arenaTemplateFiles()
      ..['pubspec.yaml'] = utf8.encode(withDep('  my_utils:\n    path: packages/my_utils\n'))
      ..['packages/my_utils/pubspec.yaml'] = utf8.encode('name: my_utils\nenvironment:\n  sdk: ^3.9.0\n')
      ..['packages/my_utils/lib/my_utils.dart'] = utf8.encode('int answer() => 42;\n');
    final (_, v) = await publishTemplate(templateZip(vendored), title: 'Arena Vendored');
    expect(v.fileCount, vendored.length);
  });

  test('with ?category=game_template an invalid template is refused already on upload, with the publish-time message', () async {
    final noContents = templateZip(arenaTemplateFiles()..removeWhere((path, _) => path.startsWith('contents/')));
    final atPublish = await refused(noContents, 'missing_contents');
    await expectLater(
        publisher.upload(noContents, fileName: 'arena.zip', category: ListingCategory.gameTemplate),
        throwsA(isA<MarketplaceException>()
            .having((e) => e.code, 'code', 'invalid_template')
            .having((e) => e.message, 'message', atPublish.message)));
    // Valid templates and other categories upload as before.
    await publisher.upload(templateZip(arenaTemplateFiles()), fileName: 'arena.zip', category: ListingCategory.gameTemplate);
    final model = await publisher.upload(propsZip('Barrels', limit: 1), fileName: 'barrels.zip', category: ListingCategory.model);
    expect(model.files, hasLength(1));
  });

  test('a template without a top folder installs under the listing name; a dot top folder is refused', () async {
    final (listing, _) = await publishTemplate(templateZip(arenaTemplateFiles(), top: null), title: 'Loose Arena');
    final manifest = await publisher.manifest(listing.id, '1.0.0');
    expect(manifest.targetRoot, 'templates/Loose_Arena/');
    expect(manifest.files.map((f) => f.target), contains('templates/Loose_Arena/template.json'));

    await refused(templateZip(arenaTemplateFiles(), top: '.Arena'), 'top_folder_invalid');
  });

  test('other categories do not get the template rules', () async {
    final (_, v) = await publish(publisher,
        title: 'Loose Level', zip: rawZip({'L_Arena.lmas': arenaTemplateFiles()['contents/levels/L_DefaultLevel.lmas']!}),
        licenses: const LicenseSelection(content: 'CC0-1.0'));
    expect(v.fileCount, 1);
  });
}
