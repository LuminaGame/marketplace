import 'package:markdown/markdown.dart' as md;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/marketplace_theme.dart';

/// Renders listing descriptions (Markdown) with shadcn typography: headings,
/// paragraphs, emphasis, inline code, code blocks, lists, quotes and rules.
/// Links render as accent text with their URL in a tooltip; raw HTML is shown
/// as text, never interpreted.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false).parse(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final n in nodes) ?_block(context, n)],
    );
  }

  Widget? _block(BuildContext context, md.Node node) {
    if (node is md.Text) {
      final t = node.text.trim();
      return t.isEmpty ? null : _para(Text(t));
    }
    if (node is! md.Element) return null;
    switch (node.tag) {
      case 'h1':
        return Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: _rich(node, const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)));
      case 'h2':
        return Padding(padding: const EdgeInsets.only(top: 12, bottom: 8), child: _rich(node, const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)));
      case 'h3' || 'h4' || 'h5' || 'h6':
        return Padding(padding: const EdgeInsets.only(top: 10, bottom: 6), child: _rich(node, const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)));
      case 'p':
        return _para(_rich(node, const TextStyle(fontSize: 14, height: 1.55)));
      case 'hr':
        return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider());
      case 'pre':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MarketColors.rail,
            border: Border.all(color: MarketColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(node.textContent, style: MarketType.mono(fontSize: 12.5)),
        );
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: MarketColors.primary, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in node.children ?? const <md.Node>[]) ?_block(context, c),
          ]),
        );
      case 'ul' || 'ol':
        final ordered = node.tag == 'ol';
        var i = 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final item in node.children ?? const <md.Node>[])
              if (item is md.Element && item.tag == 'li')
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 20, child: Text(ordered ? '${++i}.' : '•', style: const TextStyle(color: MarketColors.primary))),
                    Expanded(child: _listItem(context, item)),
                  ]),
                ),
          ]),
        );
      case 'table':
        return _para(Text(node.textContent));
      default:
        return _para(_rich(node, const TextStyle(fontSize: 14)));
    }
  }

  Widget _listItem(BuildContext context, md.Element li) {
    final blocks = li.children ?? const <md.Node>[];
    if (blocks.every((c) => c is md.Text || (c is md.Element && !{'p', 'ul', 'ol', 'pre', 'blockquote'}.contains(c.tag)))) {
      return _rich(li, const TextStyle(fontSize: 14, height: 1.5));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in blocks) ?_block(context, c)]);
  }

  Widget _para(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 10), child: child);

  Widget _rich(md.Element element, TextStyle base) =>
      Text.rich(TextSpan(style: base, children: [for (final c in element.children ?? const <md.Node>[]) _inline(c)]));

  InlineSpan _inline(md.Node node) {
    if (node is md.Text) return TextSpan(text: node.text);
    if (node is! md.Element) return TextSpan(text: node.textContent);
    final children = [for (final c in node.children ?? const <md.Node>[]) _inline(c)];
    return switch (node.tag) {
      'strong' => TextSpan(style: const TextStyle(fontWeight: FontWeight.w700), children: children),
      'em' => TextSpan(style: const TextStyle(fontStyle: FontStyle.italic), children: children),
      'del' => TextSpan(style: const TextStyle(decoration: TextDecoration.lineThrough), children: children),
      'code' => TextSpan(
          text: node.textContent,
          style: MarketType.mono(fontSize: 12.5, color: MarketColors.accentForeground).copyWith(backgroundColor: MarketColors.secondary),
        ),
      'a' => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Tooltip(
            tooltip: (context) => TooltipContainer(child: Text(node.attributes['href'] ?? '')),
            child: Text(node.textContent, style: const TextStyle(color: MarketColors.accent, decoration: TextDecoration.underline)),
          ),
        ),
      'br' => const TextSpan(text: '\n'),
      'img' => TextSpan(text: node.attributes['alt'] ?? ''),
      _ => TextSpan(children: children),
    };
  }
}
