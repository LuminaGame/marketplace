import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Lumina's palette, mirrored from Lumina Studio's
/// `lumina_ui/lib/ui/core/theme/editor_theme.dart` (`EditorColors`, itself the
/// Figma Make prototype's OKLCH tokens in sRGB) so the marketplace and the
/// editor read as one product. Keep the two in step when the editor palette
/// changes.
class MarketColors {
  const MarketColors._();

  // Surfaces.
  static const Color background = Color(0xFF020202);
  static const Color sidebar = Color(0xFF050505);
  static const Color card = Color(0xFF070707);
  static const Color popover = Color(0xFF0C0C0C);
  static const Color muted = popover;
  static const Color cardHeader = Color(0xFF040404);
  static const Color rail = Color(0xFF030303);
  static const Color secondary = Color(0xFF121212);

  // Text.
  static const Color foreground = Color(0xFFD6D6D6);
  static const Color secondaryForeground = Color(0xFFB7B7B7);
  static const Color mutedForeground = Color(0xFF696969);
  static const Color primaryForeground = Color(0xFF030303);
  static const Color accentForeground = Color(0xFFF2F2F2);

  // Accents.
  static const Color primary = Color(0xFFFB7C01);
  static const Color accent = Color(0xFF0099C8);
  static const Color destructive = Color(0xFFEE3533);
  static const Color success = Color(0xFF58A547);
  static const Color violet = Color(0xFF8688FE);
  static const Color warning = Color(0xFFFBBF24);
  static const Color selectionBg = Color(0x33FB7C01);
  static const Color rowHover = Color(0x0AFFFFFF);

  // Lines.
  static const Color border = Color(0x17FFFFFF);
  static const Color input = Color(0x1CFFFFFF);
  static const Color borderSolid = Color(0xFF1C1C1C);

  /// `--radius: 0.1875rem` = 3 px, as shadcn_flutter's radius multiplier.
  static const double radius = 0.1875;

  /// One hue per category, from the prototype's chart ramp.
  static Color category(String wire) => switch (wire) {
        'model' => primary,
        'blueprint' => accent,
        'material' => violet,
        'texture' => success,
        'sound' => warning,
        'animation' => const Color(0xFFE879F9),
        'game_template' => destructive,
        'plugin' => const Color(0xFF2DD4BF),
        'theme' => const Color(0xFFF472B6),
        _ => mutedForeground,
      };
}

/// The editor's type conventions at a web reading size: panel headings stay
/// the editor's uppercase, letter-spaced labels.
class MarketType {
  const MarketType._();

  static const TextStyle panelHeading = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    color: MarketColors.mutedForeground,
  );

  static TextStyle mono({double fontSize = 12, Color? color}) =>
      TextStyle(fontFamily: 'GeistMono', package: 'shadcn_flutter', fontSize: fontSize, color: color);
}

const ColorScheme marketDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  background: MarketColors.background,
  foreground: MarketColors.foreground,
  card: MarketColors.card,
  cardForeground: MarketColors.foreground,
  popover: MarketColors.popover,
  popoverForeground: MarketColors.foreground,
  primary: MarketColors.primary,
  primaryForeground: MarketColors.primaryForeground,
  secondary: MarketColors.secondary,
  secondaryForeground: MarketColors.secondaryForeground,
  muted: MarketColors.muted,
  mutedForeground: MarketColors.mutedForeground,
  accent: MarketColors.accent,
  accentForeground: MarketColors.accentForeground,
  destructive: MarketColors.destructive,
  destructiveForeground: MarketColors.accentForeground,
  border: MarketColors.border,
  input: MarketColors.input,
  ring: MarketColors.primary,
  chart1: MarketColors.primary,
  chart2: MarketColors.accent,
  chart3: MarketColors.success,
  chart4: MarketColors.violet,
  chart5: MarketColors.destructive,
);

/// The marketplace theme: the editor's dark scheme, radius and Geist type.
/// [platform] overrides the host platform (widget tests pin the desktop
/// layout, where selects open as popovers rather than bottom drawers).
ThemeData marketplaceTheme({TargetPlatform? platform}) => ThemeData(
      platform: platform,
      colorScheme: marketDarkColorScheme,
      radius: MarketColors.radius,
      typography: Typography.geist(),
    );
