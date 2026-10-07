import 'package:go_router/go_router.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/theme/marketplace_theme.dart';

/// A scrolling page body with the store's max width and gutters.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children, this.maxWidth = 1280, this.controller});

  final List<Widget> children;
  final double maxWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final gutter = constraints.maxWidth < 700 ? 16.0 : 32.0;
      return SingleChildScrollView(
        controller: controller,
        padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
    });
  }
}

/// The editor's uppercase, letter-spaced panel heading.
class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(text.toUpperCase(), style: MarketType.panelHeading))),
        ?trailing,
      ]),
    );
  }
}

/// A bordered panel with a darker header strip, like the editor's panels.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MarketColors.card,
        border: Border.all(color: MarketColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: MarketColors.cardHeader,
            border: Border(bottom: BorderSide(color: MarketColors.border)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
          ),
          child: Row(children: [
            Expanded(child: Semantics(header: true, child: Text(title.toUpperCase(), style: MarketType.panelHeading))),
            ?trailing,
          ]),
        ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// A text field with a visible label, exposed to assistive tech (and the
/// browser smoke) under that label.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.placeholder,
    this.obscure = false,
    this.maxLines = 1,
    this.enabled = true,
    this.help,
    this.onSubmitted,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final String? placeholder;
  final bool obscure;
  final int maxLines;
  final bool enabled;
  final String? help;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label).small().semiBold(),
      const SizedBox(height: 6),
      Semantics(
        label: label,
        textField: true,
        child: TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          minLines: maxLines > 1 ? (maxLines ~/ 2).clamp(1, 6) : null,
          enabled: enabled,
          placeholder: placeholder == null ? null : Text(placeholder!),
          onSubmitted: onSubmitted,
          onChanged: onChanged,
        ),
      ),
      if (help != null) ...[const SizedBox(height: 4), Text(help!).xSmall().muted()],
    ]);
  }
}

/// An inline error, instead of a toast (toasts race page changes).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Alert.destructive(
          leading: const Icon(LucideIcons.triangleAlert),
          title: const Text('Something went wrong'),
          content: Text(message),
        ),
      );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.title, this.icon = LucideIcons.info});
  final String message;
  final String? title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Alert(
        leading: Icon(icon),
        title: title == null ? null : Text(title!),
        content: Text(message),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(size: 18),
            const SizedBox(width: 12),
            Text(label).muted(),
          ]),
        ),
      );
}

IconData categoryIcon(ListingCategory c) => switch (c) {
      ListingCategory.model => LucideIcons.box,
      ListingCategory.blueprint => LucideIcons.workflow,
      ListingCategory.material => LucideIcons.palette,
      ListingCategory.texture => LucideIcons.image,
      ListingCategory.sound => LucideIcons.audioLines,
      ListingCategory.animation => LucideIcons.personStanding,
      ListingCategory.gameTemplate => LucideIcons.gamepad2,
      ListingCategory.plugin => LucideIcons.plug,
      ListingCategory.theme => LucideIcons.swatchBook,
    };

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key});
  final ListingCategory category;

  @override
  Widget build(BuildContext context) {
    final color = MarketColors.category(category.wire);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(categoryIcon(category), size: 11, color: color),
        const SizedBox(width: 4),
        Text(category.label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class LicenseBadge extends StatelessWidget {
  const LicenseBadge(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context) {
    final info = licenseById(id);
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(info == null ? id : '${info.name} — ${info.summary}')),
      child: OutlineBadge(child: Text(id, style: MarketType.mono(fontSize: 11))),
    );
  }
}

/// A listing's first screenshot, or its category icon on the card colour.
class ListingImage extends StatelessWidget {
  const ListingImage({super.key, required this.listing, this.index = 0, this.fit = BoxFit.cover});

  final Listing listing;
  final int index;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MarketColors.category(listing.category.wire).withValues(alpha: 0.18), MarketColors.card],
        ),
      ),
      child: Center(
        child: Icon(categoryIcon(listing.category), size: 40, color: MarketColors.category(listing.category.wire)),
      ),
    );
    if (listing.screenshots.length <= index) return placeholder;
    final url = MarketplaceScope.read(context).client.resolve(listing.screenshots[index]).toString();
    return Image.network(
      url,
      fit: fit,
      semanticLabel: '${listing.title} screenshot ${index + 1}',
      errorBuilder: (context, error, stack) => placeholder,
    );
  }
}

String formatCount(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)}M'
    : n >= 1000
        ? '${(n / 1000).toStringAsFixed(1)}k'
        : '$n';

String formatBytes(int n) => n >= 1024 * 1024
    ? '${(n / (1024 * 1024)).toStringAsFixed(1)} MB'
    : n >= 1024
        ? '${(n / 1024).toStringAsFixed(1)} KB'
        : '$n B';

String formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = d.toLocal();
  return '${months[l.month - 1]} ${l.day}, ${l.year}';
}

/// A store card: screenshot, title, publisher, category, license, downloads.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open ${listing.title}',
      child: Clickable(
        key: ValueKey('listing_card_${listing.slug}'),
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        onPressed: () => context.go('/listings/${listing.slug}'),
        child: Container(
          decoration: BoxDecoration(
            color: MarketColors.card,
            border: Border.all(color: MarketColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(aspectRatio: 16 / 9, child: ListingImage(listing: listing)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
                const SizedBox(height: 2),
                Text(listing.publisher.displayName, maxLines: 1, overflow: TextOverflow.ellipsis).xSmall().muted(),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  CategoryBadge(listing.category),
                  for (final id in listing.licenses.ids) LicenseBadge(id),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(LucideIcons.download, size: 12, color: MarketColors.mutedForeground),
                  const SizedBox(width: 4),
                  Text(formatCount(listing.downloadCount)).xSmall().muted(),
                  const Spacer(),
                  Text(listing.isFree ? 'Free' : '', style: const TextStyle(color: MarketColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A responsive grid of listing cards.
class ListingGrid extends StatelessWidget {
  const ListingGrid({super.key, required this.listings, this.minTileWidth = 240});
  final List<Listing> listings;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, 6);
      const gap = 16.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final l in listings) SizedBox(width: width, child: ListingCard(listing: l))],
      );
    });
  }
}
