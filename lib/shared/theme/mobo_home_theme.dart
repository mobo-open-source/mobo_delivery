import 'package:flutter/material.dart';

import '../utils/globals.dart';

/// Theme tokens for the Home screen.
///
/// One source of truth for surface / text / status-accent / sync-strip
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
  final Color lateBorder;
  final Color doneFg;
  final Color doneBg;

  final Color chipBg;
  final Color chipBorder;

  /// Interactive-accent foreground for section links and retry actions.
  final Color accent;

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
    required this.lateBorder,
    required this.doneFg,
    required this.doneBg,
    required this.chipBg,
    required this.chipBorder,
    required this.accent,
    required this.syncOfflineBg,
    required this.syncOfflineBorder,
    required this.cardShadow,
  });

  static const _primary = AppStyle.primaryColor;

  static const _readyBlue = Color(0xFF2196F3);

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
    readyFg: _readyBlue,
    readyBg: _readyBlue.withValues(alpha: 0.1),
    waitFg: const Color(0xFFB27400),
    waitBg: const Color(0xFFFBEFD5),
    lateFg: const Color(0xFFC73E3E),
    lateBg: const Color(0xFFFBE7E7),
    lateBorder: const Color(0xFFF1C4C4),
    doneFg: const Color(0xFF1F6840),
    doneBg: const Color(0xFFE5F3EC),
    chipBg: const Color(0x26FFFFFF),
    chipBorder: const Color(0x4DFFFFFF),
    accent: _primary,
    syncOfflineBg: const Color(0xFFFDF6E7),
    syncOfflineBorder: const Color(0xFFEDD9A8),

    cardShadow: const [
      BoxShadow(
        color: Color(0x0D000000),
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
    screen: const Color(0xFF212121),
    surface: const Color(0xFF303030),
    border: const Color(0xFF424242),
    textPrimary: const Color(0xFFF4F4F2),
    textSecondary: const Color(0xFFA6A6A1),
    textMuted: const Color(0xFF6C6C67),
    skeletonBase: const Color(0xFF242428),
    skeletonHighlight: const Color(0xFF2E2E33),

    readyFg: _readyBlue,
    readyBg: _readyBlue.withValues(alpha: 0.2),
    waitFg: const Color(0xFFE4B75A),
    waitBg: const Color(0x2EC58B17),
    lateFg: const Color(0xFFEF4444),
    lateBg: const Color(0x38EF4444),
    lateBorder: const Color(0x59EF4444),
    doneFg: const Color(0xFF6FCB9F),
    doneBg: const Color(0x2E2E8B57),
    chipBg: const Color(0x21FFFFFF),
    chipBorder: const Color(0x38FFFFFF),
    accent: _primary,
    syncOfflineBg: const Color(0x21C58B17),
    syncOfflineBorder: const Color(0x66C58B17),

    cardShadow: const [
      BoxShadow(
        color: Color(0x4D000000),
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
    Color? lateBorder,
    Color? doneFg,
    Color? doneBg,
    Color? chipBg,
    Color? chipBorder,
    Color? accent,
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
      lateBorder: lateBorder ?? this.lateBorder,
      doneFg: doneFg ?? this.doneFg,
      doneBg: doneBg ?? this.doneBg,
      chipBg: chipBg ?? this.chipBg,
      chipBorder: chipBorder ?? this.chipBorder,
      accent: accent ?? this.accent,
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
      skeletonHighlight: Color.lerp(
        skeletonHighlight,
        other.skeletonHighlight,
        t,
      )!,
      readyFg: Color.lerp(readyFg, other.readyFg, t)!,
      readyBg: Color.lerp(readyBg, other.readyBg, t)!,
      waitFg: Color.lerp(waitFg, other.waitFg, t)!,
      waitBg: Color.lerp(waitBg, other.waitBg, t)!,
      lateFg: Color.lerp(lateFg, other.lateFg, t)!,
      lateBg: Color.lerp(lateBg, other.lateBg, t)!,
      lateBorder: Color.lerp(lateBorder, other.lateBorder, t)!,
      doneFg: Color.lerp(doneFg, other.doneFg, t)!,
      doneBg: Color.lerp(doneBg, other.doneBg, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      syncOfflineBg: Color.lerp(syncOfflineBg, other.syncOfflineBg, t)!,
      syncOfflineBorder: Color.lerp(
        syncOfflineBorder,
        other.syncOfflineBorder,
        t,
      )!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
    );
  }
}
