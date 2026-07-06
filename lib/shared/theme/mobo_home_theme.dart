import 'package:flutter/material.dart';

import '../utils/globals.dart';

/// Theme tokens for the Home screen.
///
/// One source of truth for surface / text / status-accent / banner / sync-strip
/// colors, light and dark siblings. Read via
/// `Theme.of(context).extension<MoboHomeTheme>()!` inside Home widgets so no
/// hex values leak into individual widgets. Registered on `AppTheme.lightTheme`
/// and `darkTheme`.
class MoboHomeTheme extends ThemeExtension<MoboHomeTheme> {
  final Color screen;
  final Color surface;
  final Color border;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color skeletonBase;
  final Color skeletonHighlight;

  final Color readyFg;
  final Color readyBg;
  final Color waitFg;
  final Color waitBg;
  final Color lateFg;
  final Color lateBg;
  final Color lateTileBg;
  final Color lateBorder;
  final Color doneFg;
  final Color doneBg;

  final Color banner;
  final Color avatarBg;
  final Color chipBg;
  final Color chipBorder;

  /// Foreground for quick-action icons. The tile itself now uses the standard
  /// [MoboCard] surface + border, so no dedicated qaBg/qaBorder tokens.
  final Color qaFg;

  final Color syncOfflineBg;
  final Color syncOfflineBorder;

  final List<BoxShadow> cardShadow;

  const MoboHomeTheme({
    required this.screen,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.readyFg,
    required this.readyBg,
    required this.waitFg,
    required this.waitBg,
    required this.lateFg,
    required this.lateBg,
    required this.lateTileBg,
    required this.lateBorder,
    required this.doneFg,
    required this.doneBg,
    required this.banner,
    required this.avatarBg,
    required this.chipBg,
    required this.chipBorder,
    required this.qaFg,
    required this.syncOfflineBg,
    required this.syncOfflineBorder,
    required this.cardShadow,
  });

  static const _primary = AppStyle.primaryColor; // #C03355 — the app's brand.

  /// Light variant. Maroon slots use the app's canonical primary (#C03355);
  /// remaining values follow the Mobo Home design tokens.
  static final MoboHomeTheme light = MoboHomeTheme(
    screen: const Color(0xFFF3F3F5),
    surface: const Color(0xFFFFFFFF),
    border: const Color(0xFFECECEE),
    textPrimary: const Color(0xFF1A1A18),
    textSecondary: const Color(0xFF5B5B57),
    textMuted: const Color(0xFF9C9C95),
    skeletonBase: const Color(0xFFEDEDF0),
    skeletonHighlight: const Color(0xFFE2E2E6),
    readyFg: _primary,
    readyBg: _primary.withValues(alpha: 0.10),
    waitFg: const Color(0xFFB27400),
    waitBg: const Color(0xFFFBEFD5),
    lateFg: const Color(0xFFC73E3E),
    lateBg: const Color(0xFFFBE7E7),
    lateTileBg: const Color(0xFFFEF5F5),
    lateBorder: const Color(0xFFF1C4C4),
    doneFg: const Color(0xFF1F6840),
    doneBg: const Color(0xFFE5F3EC),
    banner: _primary,
    avatarBg: const Color(0xFF7C1638),
    chipBg: const Color(0x26FFFFFF), // white @ 15%
    chipBorder: const Color(0x4DFFFFFF), // white @ 30%
    qaFg: _primary,
    syncOfflineBg: const Color(0xFFFDF6E7),
    syncOfflineBorder: const Color(0xFFEDD9A8),
    // Match the sales-app dashboard tile shadow exactly — tight blur, small
    // downward offset, 5% black. Applied via the theme extension so every
    // Home card (stat tile, quick action, attention row, empty state) uses
    // the same values from one source.
    cardShadow: const [
      BoxShadow(
        color: Color(0x0D000000), // black @ 5%
        offset: Offset(0, 2),
        blurRadius: 4,
        spreadRadius: 2,
      ),
    ],
  );

  /// Dark variant. Same slot semantics; surface is one shade **lighter** than
  /// screen (grey[850] on grey[900]) — matches the sales-app dashboard
  /// convention so cards read as elevated surfaces on the dark bg without
  /// needing a border.
  static final MoboHomeTheme dark = MoboHomeTheme(
    screen: const Color(0xFF212121), // Colors.grey[900] — matches Dashboard scaffold
    surface: const Color(0xFF303030), // Colors.grey[850] — cards lift off screen
    border: const Color(0xFF424242), // Colors.grey[800] — one step above surface
    textPrimary: const Color(0xFFF4F4F2),
    textSecondary: const Color(0xFFA6A6A1),
    textMuted: const Color(0xFF6C6C67),
    skeletonBase: const Color(0xFF242428),
    skeletonHighlight: const Color(0xFF2E2E33),
    // Ready + quick-action foregrounds use the actual app primary so nothing
    // reads as a lightened-pink derivative. Late foreground uses the app's
    // status red (#EF4444) rather than a pink-tinted red.
    readyFg: _primary,
    readyBg: const Color(0x33C03355), // primary @ 20%
    waitFg: const Color(0xFFE4B75A),
    waitBg: const Color(0x2EC58B17), // amber @ 18%
    lateFg: const Color(0xFFEF4444), // matches list-tile statusRed
    lateBg: const Color(0x38EF4444), // late-fg @ 22%
    lateTileBg: const Color(0x1AEF4444), // late-fg @ 10%
    lateBorder: const Color(0x59EF4444), // late-fg @ 35%
    doneFg: const Color(0xFF6FCB9F),
    doneBg: const Color(0x2E2E8B57), // green @ 18%
    banner: _primary, // same primary as light — no darkened maroon variant
    avatarBg: const Color(0xFF661230),
    chipBg: const Color(0x21FFFFFF), // white @ 13%
    chipBorder: const Color(0x38FFFFFF), // white @ 22%
    qaFg: _primary,
    syncOfflineBg: const Color(0x21C58B17), // amber @ 13%
    syncOfflineBorder: const Color(0x66C58B17), // amber @ 40%
    // Dark equivalent of the sales-app dashboard tile shadow (30% black
    // instead of 5% since it needs to register against a dark surface).
    cardShadow: const [
      BoxShadow(
        color: Color(0x4D000000), // black @ 30%
        offset: Offset(0, 2),
        blurRadius: 4,
        spreadRadius: 2,
      ),
    ],
  );

  @override
  MoboHomeTheme copyWith({
    Color? screen,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? readyFg,
    Color? readyBg,
    Color? waitFg,
    Color? waitBg,
    Color? lateFg,
    Color? lateBg,
    Color? lateTileBg,
    Color? lateBorder,
    Color? doneFg,
    Color? doneBg,
    Color? banner,
    Color? avatarBg,
    Color? chipBg,
    Color? chipBorder,
    Color? qaFg,
    Color? syncOfflineBg,
    Color? syncOfflineBorder,
    List<BoxShadow>? cardShadow,
  }) {
    return MoboHomeTheme(
      screen: screen ?? this.screen,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      readyFg: readyFg ?? this.readyFg,
      readyBg: readyBg ?? this.readyBg,
      waitFg: waitFg ?? this.waitFg,
      waitBg: waitBg ?? this.waitBg,
      lateFg: lateFg ?? this.lateFg,
      lateBg: lateBg ?? this.lateBg,
      lateTileBg: lateTileBg ?? this.lateTileBg,
      lateBorder: lateBorder ?? this.lateBorder,
      doneFg: doneFg ?? this.doneFg,
      doneBg: doneBg ?? this.doneBg,
      banner: banner ?? this.banner,
      avatarBg: avatarBg ?? this.avatarBg,
      chipBg: chipBg ?? this.chipBg,
      chipBorder: chipBorder ?? this.chipBorder,
      qaFg: qaFg ?? this.qaFg,
      syncOfflineBg: syncOfflineBg ?? this.syncOfflineBg,
      syncOfflineBorder: syncOfflineBorder ?? this.syncOfflineBorder,
      cardShadow: cardShadow ?? this.cardShadow,
    );
  }

  @override
  MoboHomeTheme lerp(ThemeExtension<MoboHomeTheme>? other, double t) {
    if (other is! MoboHomeTheme) return this;
    return MoboHomeTheme(
      screen: Color.lerp(screen, other.screen, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight:
          Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
      readyFg: Color.lerp(readyFg, other.readyFg, t)!,
      readyBg: Color.lerp(readyBg, other.readyBg, t)!,
      waitFg: Color.lerp(waitFg, other.waitFg, t)!,
      waitBg: Color.lerp(waitBg, other.waitBg, t)!,
      lateFg: Color.lerp(lateFg, other.lateFg, t)!,
      lateBg: Color.lerp(lateBg, other.lateBg, t)!,
      lateTileBg: Color.lerp(lateTileBg, other.lateTileBg, t)!,
      lateBorder: Color.lerp(lateBorder, other.lateBorder, t)!,
      doneFg: Color.lerp(doneFg, other.doneFg, t)!,
      doneBg: Color.lerp(doneBg, other.doneBg, t)!,
      banner: Color.lerp(banner, other.banner, t)!,
      avatarBg: Color.lerp(avatarBg, other.avatarBg, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      qaFg: Color.lerp(qaFg, other.qaFg, t)!,
      syncOfflineBg: Color.lerp(syncOfflineBg, other.syncOfflineBg, t)!,
      syncOfflineBorder:
          Color.lerp(syncOfflineBorder, other.syncOfflineBorder, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
    );
  }
}
