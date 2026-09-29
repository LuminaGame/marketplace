import 'dart:convert';
import 'dart:io';

import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:test/test.dart';

/// The Lumina plugin package format the marketplace reads — the
/// `.lmplugin` manifest (the same rules lumina's PluginRepository applies),
/// the declared license (manifest `license`, else the root LICENSE text) and
/// the changelog section of the published version.
void main() {
  // The real example plugin of the plugins checkout (LuminaGame/plugins:
  // `LUMINA_PLUGINS_DIR`, else `../plugins` next to this repository; read
  // only). Since its commit 7d66ca2 it is MIT: LICENSE holds the MIT text and
  // the manifest declares "license": "MIT" and "changelog": "CHANGELOG.md".
  final pcgDir = Directory('${Platform.environment['LUMINA_PLUGINS_DIR'] ?? '../../plugins'}/lumina_plugin_pcg');
  if (!File('${pcgDir.path}/lumina_plugin_pcg.lmplugin').existsSync()) {
    test('the plugin package format', () {},
        skip: 'lumina_plugin_pcg is not checked out at ${pcgDir.path}: clone LuminaGame/plugins next to this '
            'repository (../plugins) or set LUMINA_PLUGINS_DIR');
    return;
  }
  final realManifest = File('${pcgDir.path}/lumina_plugin_pcg.lmplugin').readAsStringSync();
  final pcgChangelog = File('${pcgDir.path}/CHANGELOG.md').readAsStringSync();
  final realLicense = File('${pcgDir.path}/LICENSE').readAsStringSync();
  // What the package looked like before (no license, no changelog key): the
  // base of the rule tests below.
  final pcgManifest = jsonEncode((jsonDecode(realManifest) as Map)..remove('license')..remove('changelog'));
  const pcgLicense = 'Copyright (c) 2026 Lumina. All rights reserved.\n';

  PluginPackageCheck check(Map<String, String> files) =>
      checkPluginPackage(files.keys, read: (path) => files.containsKey(path) ? utf8.encode(files[path]!) : null);

  Map<String, Object?> manifestOf(String json) => (jsonDecode(json) as Map).cast<String, Object?>();
  String withKeys(String json, Map<String, Object?> extra) => jsonEncode({...manifestOf(json), ...extra});

  Map<String, String> pcg({String top = 'lumina_plugin_pcg/', String? manifest, bool license = false}) => {
        '${top}lumina_plugin_pcg.lmplugin': manifest ?? pcgManifest,
        '${top}CHANGELOG.md': pcgChangelog,
        '${top}pubspec.yaml': 'name: lumina_plugin_pcg\n',
        '${top}lib/lumina_plugin_pcg.dart': '// PCG\n',
        if (license) '${top}LICENSE': pcgLicense,
      };

  List<String> codes(PluginPackageCheck c) => [for (final p in c.problems) p.code];

  group('the manifest', () {
    test('lumina_plugin_pcg (as the workspace has it) is a valid MIT package; the listing data comes from it', () {
      final c = check(pcg(manifest: realManifest)..['lumina_plugin_pcg/LICENSE'] = realLicense);
      expect(c.problems, isEmpty);
      final info = c.info!;
      expect(info.license!.code, 'MIT');
      expect(info.license!.source, PluginLicenseSource.manifest);
      expect(info.licenseFile, 'lumina_plugin_pcg/LICENSE');
      expect(info.licenseFileVerdict, LicenseTextVerdict.free);
      expect(info.changelogPath, 'lumina_plugin_pcg/CHANGELOG.md');
      expect(info.releaseNotes, startsWith('- Initial release'));
    });

    test('lumina_plugin_pcg without license keys is a valid package; the listing data comes from it', () {
      final c = check(pcg());
      expect(c.problems, isEmpty);
      final info = c.info!;
      expect(info.name, 'lumina_plugin_pcg');
      expect(info.title, 'Procedural Content Generation');
      expect(info.version, '0.1.0');
      expect(info.description, startsWith('PCG Graph assets and PCG Volume actors'));
      expect(info.category, 'Procedural');
      expect(info.authors, ['Lumina']);
      expect(info.engineVersionConstraint, '>=0.0.1 <1.0.0');
      expect(info.minEngineVersion, '0.0.1');
      expect(info.tags, ['procedural', 'plugin']);
      expect(info.manifestPath, 'lumina_plugin_pcg/lumina_plugin_pcg.lmplugin');
      expect(info.topFolder, 'lumina_plugin_pcg');
      // The changelog: the 0.1.0 section, not "Unreleased".
      expect(info.changelogPath, 'lumina_plugin_pcg/CHANGELOG.md');
      expect(info.changelog, pcgChangelog.trim());
      expect(info.releaseNotes, startsWith('- Initial release, generated from the Lumina plugin wizard'));
      expect(info.releaseNotes, contains('`pcg.generate` console command'));
      expect(info.releaseNotes, isNot(contains('Plugins → PCG')));
      // No license declared anywhere: the publisher picks one.
      expect(info.license, isNull);
      expect(info.licenseFile, isNull);
      // Round trip (the upload DTO carries it).
      final back = PluginPackageInfo.fromJson(jsonDecode(jsonEncode(info.toJson())) as Map<String, Object?>);
      expect(back.toJson(), info.toJson());
    });

    test('a package without a top folder is valid too', () {
      final c = check(pcg(top: ''));
      expect(c.problems, isEmpty);
      expect(c.info!.topFolder, isNull);
      expect(c.info!.manifestPath, 'lumina_plugin_pcg.lmplugin');
    });

    test('broken packages name the problem', () {
      expect(codes(check({'my_plugin/pubspec.yaml': 'name: my_plugin\n', 'my_plugin/lib/a.dart': '//'})), ['no_manifest']);
      final two = pcg()..['lumina_plugin_pcg/other.lmplugin'] = withKeys(pcgManifest, {'name': 'other'});
      expect(codes(check(two)), ['multiple_manifests']);
      expect(codes(check(pcg(manifest: withKeys(pcgManifest, {'name': 'pcg'})))), contains('name_mismatch'));
      final renamed = {
        for (final e in pcg().entries) e.key.replaceFirst('lumina_plugin_pcg/', 'PCG/'): e.value,
      };
      expect(codes(check(renamed)), ['top_folder_mismatch']);
      expect(codes(check(pcg(manifest: withKeys(pcgManifest, {'version': '0.1'})))), ['version_invalid']);
      expect(codes(check(pcg(manifest: withKeys(pcgManifest, {'engine_version': 'soon'})))), ['engine_version_invalid']);
      expect(codes(check(pcg(manifest: '{"name": "lumina_plugin_pcg",'))), ['manifest_invalid']);
      final badName = {'Bad-Name/Bad-Name.lmplugin': withKeys(pcgManifest, {'name': 'Bad-Name'})};
      expect(codes(check(badName)), ['name_invalid']);
      final problem = check(pcg(manifest: withKeys(pcgManifest, {'version': '0.1'}))).problems.single;
      expect(problem.path, 'lumina_plugin_pcg/lumina_plugin_pcg.lmplugin');
      expect(problem.message, contains('"0.1"'));
    });

    test('a manifest in a vendored subfolder does not count as the package manifest', () {
      final files = pcg()..['lumina_plugin_pcg/packages/helper/helper.lmplugin'] = '{"name": "helper", "version": "1.0.0"}';
      expect(check(files).problems, isEmpty);
    });

    test('minimumEngineVersion reads the lower bound of a constraint', () {
      expect(minimumEngineVersion('>=0.0.1 <1.0.0'), '0.0.1');
      expect(minimumEngineVersion('^0.2.0'), '0.2.0');
      expect(minimumEngineVersion('1.4.2'), '1.4.2');
      expect(minimumEngineVersion('any'), isNull);
      expect(minimumEngineVersion('<2.0.0'), isNull);
      expect(isVersionConstraint('>=0.0.1 <1.0.0'), isTrue);
      expect(isVersionConstraint('soon'), isFalse);
    });
  });

  group('the license', () {
    test('"license" in the manifest: one SPDX id, or one content AND one code license', () {
      final mit = check(pcg(manifest: withKeys(pcgManifest, {'license': 'MIT'})));
      expect(mit.problems, isEmpty);
      expect(mit.info!.license!.code, 'MIT');
      expect(mit.info!.license!.content, isNull);
      expect(mit.info!.license!.source, PluginLicenseSource.manifest);
      expect(mit.info!.license!.path, 'lumina_plugin_pcg/lumina_plugin_pcg.lmplugin');

      final both = check(pcg(manifest: withKeys(pcgManifest, {'license': 'MIT AND CC-BY-4.0'})));
      expect(both.problems, isEmpty);
      expect(both.info!.license!.selection.ids, ['CC-BY-4.0', 'MIT']);

      expect(codes(check(pcg(manifest: withKeys(pcgManifest, {'license': 'GPL-3.0'})))), ['license_unknown']);
      expect(codes(check(pcg(manifest: withKeys(pcgManifest, {'license': 'MIT OR Apache-2.0'})))), ['license_unknown']);
      expect(codes(check(pcg(manifest: withKeys(pcgManifest, {'license': 'MIT AND Zlib'})))), ['license_unknown'],
          reason: 'one license per kind');
    });

    test('the standard texts of the allow-list are recognised', () {
      expect(detectLicenseText(_mitText).id, 'MIT');
      expect(detectLicenseText(_apacheText).id, 'Apache-2.0');
      expect(detectLicenseText(_bsd3Text).id, 'BSD-3-Clause');
      expect(detectLicenseText(_bsd3Text.replaceAll(RegExp(r'3\. Neither the name[^.]*\.'), '')).id, 'BSD-2-Clause');
      expect(detectLicenseText(_cc0Text).id, 'CC0-1.0');
      expect(detectLicenseText('// SPDX-License-Identifier: Zlib\n').id, 'Zlib');
      expect(detectLicenseText(pcgLicense).verdict, LicenseTextVerdict.notFree);
      expect(detectLicenseText(realLicense).id, 'MIT');
      expect(detectLicenseText('Attribution-NonCommercial 4.0 International').verdict, LicenseTextVerdict.notFree);
      expect(detectLicenseText('Do what you like, but be nice.').verdict, LicenseTextVerdict.unrecognised);
    });

    test('a recognised LICENSE declares the license when the manifest does not', () {
      final files = pcg()..['lumina_plugin_pcg/LICENSE'] = _mitText;
      final c = check(files);
      expect(c.problems, isEmpty);
      expect(c.info!.license!.code, 'MIT');
      expect(c.info!.license!.source, PluginLicenseSource.licenseFile);
      expect(c.info!.license!.path, 'lumina_plugin_pcg/LICENSE');
      expect(c.info!.licenseFile, 'lumina_plugin_pcg/LICENSE');
    });

    test('"All rights reserved" is not a free license: refused, and it contradicts a manifest license', () {
      final c = check(pcg(license: true));
      expect(codes(c), ['license_not_free']);
      expect(c.problems.single.path, 'lumina_plugin_pcg/LICENSE');
      expect(c.problems.single.message, contains('All rights reserved'));
      expect(codes(check(pcg(license: true, manifest: withKeys(pcgManifest, {'license': 'MIT'})))), ['license_conflict']);
      final apache = pcg(manifest: withKeys(pcgManifest, {'license': 'MIT'}))..['lumina_plugin_pcg/LICENSE'] = _apacheText;
      expect(codes(check(apache)), ['license_conflict']);
    });

    test('an unrecognised LICENSE leaves the choice to the publisher; the manifest license wins over it', () {
      final custom = pcg()..['lumina_plugin_pcg/LICENSE.md'] = 'Do what you like, but be nice.';
      final c = check(custom);
      expect(c.problems, isEmpty);
      expect(c.info!.license, isNull);
      expect(c.info!.licenseFile, 'lumina_plugin_pcg/LICENSE.md');
      expect(c.info!.licenseFileVerdict, LicenseTextVerdict.unrecognised);
      final declared = pcg(manifest: withKeys(pcgManifest, {'license': 'Zlib'}))..['lumina_plugin_pcg/LICENSE.md'] = 'Do what you like.';
      expect(check(declared).info!.license!.code, 'Zlib');
    });
  });

  group('the changelog', () {
    test('sections: "## 1.0.0", "## [1.0.0] - date", "## v1.0.0"; Unreleased is not a release', () {
      const md = '# Changelog\n\n## [Unreleased]\n\n- next\n\n## [1.1.0] - 2026-09-01\n\n### Added\n- more\n\n'
          '## v1.0.0\n\n- first\n';
      expect(changelogSection(md, '1.1.0'), '### Added\n- more');
      expect(changelogSection(md, '1.0.0'), '- first');
      expect(changelogSection(md, '2.0.0'), isNull);
    });

    test('"changelog" in the manifest names the file; a missing one is a problem', () {
      final files = pcg(manifest: withKeys(pcgManifest, {'changelog': 'docs/HISTORY.md'}))
        ..remove('lumina_plugin_pcg/CHANGELOG.md')
        ..['lumina_plugin_pcg/docs/HISTORY.md'] = '## 0.1.0\n\n- from history\n';
      final c = check(files);
      expect(c.problems, isEmpty);
      expect(c.info!.changelogPath, 'lumina_plugin_pcg/docs/HISTORY.md');
      expect(c.info!.releaseNotes, '- from history');
      files.remove('lumina_plugin_pcg/docs/HISTORY.md');
      expect(codes(check(files)), ['changelog_missing']);
    });

    test('no changelog: no release notes, still valid', () {
      final c = check(pcg()..remove('lumina_plugin_pcg/CHANGELOG.md'));
      expect(c.problems, isEmpty);
      expect(c.info!.changelog, isNull);
      expect(c.info!.releaseNotes, isNull);
    });
  });
}

const _mitText = '''MIT License

Copyright (c) 2026 Lumina

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
''';

const _apacheText = '''
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION
''';

const _bsd3Text = '''Copyright (c) 2026, Lumina. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice.
2. Redistributions in binary form must reproduce the above copyright notice.
3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.
''';

const _cc0Text = '''Creative Commons Legal Code

CC0 1.0 Universal

    CREATIVE COMMONS CORPORATION IS NOT A LAW FIRM AND DOES NOT PROVIDE
    LEGAL SERVICES.
''';
