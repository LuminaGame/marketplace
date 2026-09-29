import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:yaml/yaml.dart';

/// Finds `openapi.yaml` next to this package (dart run / dart test), in the
/// working directory, or next to a compiled executable.
String? locateOpenApi() {
  final candidates = <String>[];
  try {
    final lib = Isolate.resolvePackageUriSync(Uri.parse('package:lumina_marketplace_server/lumina_marketplace_server.dart'));
    if (lib != null) candidates.add(File.fromUri(lib).parent.parent.uri.resolve('openapi.yaml').toFilePath());
  } catch (_) {}
  candidates
    ..add('openapi.yaml')
    ..add(File(Platform.resolvedExecutable).parent.uri.resolve('openapi.yaml').toFilePath());
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

String _esc(Object? s) => const HtmlEscape(HtmlEscapeMode.element).convert('${s ?? ''}');

/// A readable API reference rendered from the OpenAPI document — no external
/// scripts, so it works offline.
String renderDocsHtml(String yamlText) {
  final spec = loadYaml(yamlText) as YamlMap;
  final info = spec['info'] as YamlMap;
  final buffer = StringBuffer()
    ..write('<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>${_esc(info['title'])} — API</title><style>'
        ':root{color-scheme:dark;--bg:#020202;--card:#070707;--fg:#d6d6d6;--muted:#8a8a8a;--border:#1c1c1c;--primary:#fb7c01;--accent:#0099c8}'
        'body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,sans-serif}'
        'main{max-width:960px;margin:0 auto;padding:24px 16px}h1{margin:0 0 4px}h2{margin-top:32px;border-bottom:1px solid var(--border);padding-bottom:4px}'
        '.op{background:var(--card);border:1px solid var(--border);border-radius:4px;padding:10px 12px;margin:8px 0}'
        '.m{display:inline-block;min-width:60px;font:600 12px ui-monospace,monospace;color:var(--bg);background:var(--accent);border-radius:3px;padding:1px 6px;text-align:center}'
        '.m.POST,.m.PUT,.m.PATCH{background:var(--primary)}.m.DELETE{background:#ee3533}'
        'code,.path{font-family:ui-monospace,monospace}.path{margin-left:8px}.muted{color:var(--muted)}.lock{color:var(--primary);font-size:12px;margin-left:8px}'
        'a{color:var(--accent)}p{margin:6px 0}</style></head><body><main>')
    ..write('<h1>${_esc(info['title'])}</h1><p class="muted">Version ${_esc(info['version'])} · '
        '<a href="/openapi.yaml">openapi.yaml</a></p><p>${_esc(info['description'])}</p>');
  final byTag = <String, List<String>>{};
  (spec['paths'] as YamlMap).forEach((path, ops) {
    (ops as YamlMap).forEach((method, op) {
      if (method == 'parameters') return;
      final o = op as YamlMap;
      final tag = ((o['tags'] as YamlList?)?.first ?? 'other').toString();
      final secured = o['security'] != null;
      byTag.putIfAbsent(tag, () => []).add('<div class="op"><span class="m ${_esc(method.toString().toUpperCase())}">'
          '${_esc(method.toString().toUpperCase())}</span><span class="path">${_esc(path)}</span>'
          '${secured ? '<span class="lock">requires sign-in</span>' : ''}'
          '<p><strong>${_esc(o['summary'])}</strong></p>'
          '${o['description'] == null ? '' : '<p class="muted">${_esc(o['description'])}</p>'}</div>');
    });
  });
  byTag.forEach((tag, ops) {
    buffer.write('<h2>${_esc(tag)}</h2>');
    ops.forEach(buffer.write);
  });
  buffer.write('</main></body></html>');
  return buffer.toString();
}
