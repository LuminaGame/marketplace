import 'dart:convert';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

/// The game template archive format (v1), checked on file paths
/// and the few manifests it reads — the same rules the server enforces on
/// publish and lumina_ui's InstalledTemplateRepository applies after install.
void main() {
  const lmproject = '{"project_name": "arena", "engine_version": "0.0.1", "active_level": "contents/levels/L_DefaultLevel.lmas"}';
  const pubspec = 'name: arena\n'
      'dependencies:\n'
      '  flutter:\n'
      '    sdk: flutter\n'
      '  lumina:\n'
      '    path: /home/publisher/lumina/lumina\n'
      '  shadcn_flutter: 0.0.53\n';

  Map<String, String> arena({String top = 'Arena/'}) => {
        '${top}template.json': jsonEncode({
          'format': kGameTemplateFormatVersion,
          'title': 'Arena',
          'description': 'A starter arena.',
          'engine_version': '0.0.1',
          'thumbnail': 'thumbnail.png',
        }),
        '${top}thumbnail.png': 'png',
        '${top}arena.lmproject': lmproject,
        '${top}pubspec.yaml': pubspec,
        '${top}contents/levels/L_DefaultLevel.lmas': '{}',
        '${top}lib/main.dart': 'void main() {}',
      };

  GameTemplateCheck check(Map<String, String> files) =>
      checkGameTemplate(files.keys, read: (p) => files[p] == null ? null : utf8.encode(files[p]!));

  List<String> codes(Map<String, String> files) => [for (final p in check(files).problems) p.code];

  test('shares the format version, the manifest keys and the excluded folders', () {
    expect(kGameTemplateFormatVersion, 1);
    expect(kGameTemplateManifestFile, 'template.json');
    expect(GameTemplateKeys.title, 'title');
    expect(GameTemplateKeys.engineVersion, 'engine_version');
    expect(GameTemplateKeys.strings, containsAll(['description', 'engine_version', 'thumbnail', 'publisher', 'version']));
    expect(kGameTemplatePlatformFolders, {'android', 'ios', 'linux', 'macos', 'windows', 'web'});
    expect(kGameTemplateBuildFolders, {'build', '.dart_tool'});
    expect(kGameTemplateThumbnailNames.first, 'thumbnail.png');
    expect(kInvalidTemplateErrorCode, 'invalid_template');
  });

  test('a valid template under one top folder: the folder is stripped, the manifest parsed', () {
    final c = check(arena());
    expect(c.problems, isEmpty);
    expect(c.isValid, isTrue);
    expect(c.topFolder, 'Arena');
    expect(c.projectPath, 'Arena/arena.lmproject');
    expect(c.manifest!.title, 'Arena');
    expect(c.manifest!.thumbnail, 'thumbnail.png');
    expect(c.manifest!.format, 1);
    expect(GameTemplateManifest.fromJson(c.manifest!.toJson()).toJson(), c.manifest!.toJson());
  });

  test('without a top folder the archive root is the template', () {
    final c = check(arena(top: ''));
    expect(c.problems, isEmpty);
    expect(c.topFolder, isNull);
  });

  test('template.json alone, or the .lmproject alone, is a manifest', () {
    expect(check(arena()..remove('Arena/arena.lmproject')).problems, isEmpty);
    expect(check(arena()..remove('Arena/template.json')).problems, isEmpty);
    expect(codes(arena()..remove('Arena/template.json')..remove('Arena/arena.lmproject')), ['no_manifest']);
  });

  test('contents/ needs at least one file', () {
    final files = arena()..remove('Arena/contents/levels/L_DefaultLevel.lmas');
    expect(codes(files), ['missing_contents']);
    expect(check(files).problems.single.message, contains('contents/'));
  });

  test('template.json needs a title and string fields, format 1 and a thumbnail inside the archive', () {
    Map<String, String> withManifest(Map<String, Object?> m) => arena()..['Arena/template.json'] = jsonEncode(m);
    expect(codes(withManifest({'description': 'no title'})), ['manifest_no_title']);
    expect(codes(withManifest({'title': '  '})), ['manifest_no_title']);
    expect(codes(withManifest({'title': 'Arena', 'description': 3})), ['manifest_invalid']);
    expect(codes(withManifest({'title': 'Arena', 'format': 2})), ['manifest_invalid']);
    expect(codes(arena()..['Arena/template.json'] = '[1, 2]'), ['manifest_invalid']);
    expect(codes(arena()..['Arena/template.json'] = '{not json'), ['manifest_invalid']);
    final missing = check(withManifest({'title': 'Arena', 'thumbnail': 'shots/card.png'}));
    expect(missing.problems.single.code, 'thumbnail_missing');
    expect(missing.problems.single.path, 'Arena/template.json');
    expect(missing.problems.single.message, contains('shots/card.png'));
    expect(codes(withManifest({'title': 'Arena', 'thumbnail': '../card.png'})), ['thumbnail_missing']);
    expect(codes(withManifest({'title': 'Arena', 'thumbnail': 'arena.lmproject'})), ['manifest_invalid']);
  });

  test('a template is one project whose .lmproject parses', () {
    final two = check(arena()..['Arena/copy.lmproject'] = lmproject);
    expect(two.problems.single.code, 'multiple_projects');
    expect(two.problems.single.message, contains('2 .lmproject'));
    expect(codes(arena()..['Arena/arena.lmproject'] = '{"engine_version": "0.0.1"}'), ['project_invalid']);
    expect(codes(arena()..['Arena/arena.lmproject'] = 'not json'), ['project_invalid']);
    // Only the template root counts, as in the launcher.
    expect(check(arena()..['Arena/contents/old/old.lmproject'] = '{}').problems, isEmpty);
  });

  test('platform folders, build/ and .dart_tool/ are refused, naming the archive path', () {
    final linux = check(arena()..['Arena/linux/CMakeLists.txt'] = 'project(arena)');
    expect(linux.problems.single.code, 'excluded_path');
    expect(linux.problems.single.path, 'Arena/linux/CMakeLists.txt');
    expect(linux.problems.single.message, contains('Arena/linux/CMakeLists.txt'));
    expect(gameTemplatePathProblems(['Arena/template.json', 'Arena/build/app.so']).single.path, 'Arena/build/app.so');
    expect(codes(arena()..['Arena/lib/.dart_tool/package_config.json'] = '{}'), ['excluded_path']);
    // A contents/ folder that happens to be called "web" or "build" is content.
    expect(check(arena()..['Arena/contents/web/banner.png'] = 'png'..['Arena/contents/build/crate.lmas'] = '{}').problems,
        isEmpty);
  });

  test('a pubspec_overrides.yaml (machine-specific paths) is refused, at the root or in a vendored package', () {
    final root = check(arena()..['Arena/pubspec_overrides.yaml'] = 'dependency_overrides:\n  lumina:\n    path: D:/lumina/lumina\n');
    expect(root.problems.single.code, 'excluded_path');
    expect(root.problems.single.path, 'Arena/pubspec_overrides.yaml');
    expect(root.problems.single.message, allOf(contains('pubspec_overrides.yaml'), contains('machine')));
    expect(gameTemplatePathProblems(['Arena/template.json', 'Arena/packages/utils/pubspec_overrides.yaml']).single.path,
        'Arena/packages/utils/pubspec_overrides.yaml');
  });

  test('a dot top folder is refused: the launcher skips dot folders', () {
    final c = check(arena(top: '.Arena/'));
    expect(c.problems.first.code, 'top_folder_invalid');
  });

  group('pubspec path dependencies', () {
    Map<String, String> withPubspec(String yaml, [Map<String, String> extra = const {}]) =>
        arena()..['Arena/pubspec.yaml'] = yaml..addAll(extra);

    test('lumina may be a block-style path dependency; Studio repoints it', () {
      expect(check(withPubspec(pubspec)).problems, isEmpty);
      expect(codes(withPubspec('name: arena\ndependencies:\n  lumina: {path: /x/lumina}\n')), ['path_dependency']);
      expect(codes(withPubspec('name: arena\ndependencies:\n  lumina: ^0.0.1\n')), ['path_dependency']);
      expect(codes(withPubspec('name: arena\ndependency_overrides:\n  lumina:\n    path: /x/lumina\n')), ['path_dependency']);
    });

    test('lumina may be the engine git dependency Studio writes', () {
      const git = 'name: arena\ndependencies:\n  lumina:\n    git:\n      url: $kLuminaEngineGitUrl\n      path: lumina\n';
      expect(check(withPubspec(git)).problems, isEmpty);
      expect(codes(withPubspec(git.replaceFirst('LuminaGame', 'someone'))), ['path_dependency']);
      expect(codes(withPubspec(git.replaceFirst('path: lumina', 'path: lumina_ui'))), ['path_dependency']);
    });

    test('any other path dependency must be a vendored copy inside the template', () {
      final outside = check(withPubspec('$pubspec  my_utils:\n    path: /home/publisher/my_utils\n'));
      expect(outside.problems.single.code, 'path_dependency');
      expect(outside.problems.single.path, 'Arena/pubspec.yaml');
      expect(outside.problems.single.message, allOf(contains('my_utils'), contains('vendor')));
      expect(codes(withPubspec('$pubspec  my_utils:\n    path: ../my_utils\n')), ['path_dependency']);
      expect(codes(withPubspec('$pubspec  my_utils:\n    path: packages/my_utils\n')), ['path_dependency'],
          reason: 'the folder is not in the archive');
      expect(codes(withPubspec('name: arena\ndev_dependencies:\n  helper:\n    path: C:\\\\tools\\\\helper\n')),
          ['path_dependency']);

      final vendored = withPubspec('$pubspec  my_utils:\n    path: packages/my_utils/\n', {
        'Arena/packages/my_utils/pubspec.yaml': 'name: my_utils\ndependencies:\n  sibling:\n    path: ../sibling\n',
        'Arena/packages/my_utils/lib/my_utils.dart': '',
        'Arena/packages/sibling/pubspec.yaml': 'name: sibling\n',
      });
      expect(check(vendored).problems, isEmpty);
    });

    test('a vendored package cannot reach outside the template or depend on lumina by path', () {
      final escape = check(withPubspec('$pubspec  my_utils:\n    path: packages/my_utils\n', {
        'Arena/packages/my_utils/pubspec.yaml': 'name: my_utils\ndependencies:\n  far:\n    path: ../../../far\n',
      }));
      expect(escape.problems.single.code, 'path_dependency');
      expect(escape.problems.single.path, 'Arena/packages/my_utils/pubspec.yaml');
      final engine = check(withPubspec('$pubspec  my_utils:\n    path: packages/my_utils\n', {
        'Arena/packages/my_utils/pubspec.yaml': 'name: my_utils\ndependencies:\n  lumina:\n    path: /x/lumina\n',
      }));
      expect(engine.problems.single.code, 'path_dependency');
      expect(engine.problems.single.message, contains('lumina'));
    });

    test('a pubspec that is not a YAML map is refused', () {
      expect(codes(withPubspec('name: [unclosed\n')), ['pubspec_invalid']);
      expect(codes(withPubspec('- a list\n')), ['pubspec_invalid']);
      expect(codes(withPubspec('name: not-a-package\n')), ['pubspec_invalid']);
    });
  });

  test('problems serialize for the API error details', () {
    final p = check(arena()..remove('Arena/contents/levels/L_DefaultLevel.lmas')).problems.single;
    expect(GameTemplateProblem.fromJson(p.toJson()).toJson(), p.toJson());
    expect(p.toJson().keys, containsAll(['code', 'message']));
  });

  test('singleTopFolder is the folder every file shares, else null', () {
    expect(singleTopFolder(['A/x', 'A/y/z']), 'A');
    expect(singleTopFolder(['A/x', 'y']), isNull);
    expect(singleTopFolder(['A/x', 'B/y']), isNull);
    expect(singleTopFolder(['x']), isNull);
  });
}
