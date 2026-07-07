import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/mobo_home_theme.dart';
import '../../../shared/widgets/odoo_avatar.dart';

/// Maroon greeting card at the top of the Home screen.
///
/// Displays: date eyebrow, "Good morning, {firstName}" greeting, subtitle
/// (varies with online/offline), and a circular avatar (from the operator's
/// `res.users.image_1920`, falling back to initials).
///
/// The warehouse / company selector lives in the Dashboard AppBar (shared
/// with every other tab) — the banner does not host it.
class HeaderBanner extends StatelessWidget {
  final String name;
  final Uint8List? avatarBytes;
  final bool online;

  /// Called when the avatar is tapped (opens the Configuration screen).
  final VoidCallback? onAvatarTap;

  const HeaderBanner({
    super.key,
    required this.name,
    required this.avatarBytes,
    required this.online,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: home.banner,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _dateEyebrow(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: Color(0xADFFFFFF),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_greetingWord()}, ${_firstName(name)}',
                      style: GoogleFonts.manrope(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: -0.44,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      online
                          ? "Let's clear today's deliveries"
                          : 'Working offline — cached data',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xD1FFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _Avatar(
                bytes: avatarBytes,
                initials: _initials(name),
                bg: home.avatarBg,
                onTap: onAvatarTap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _firstName(String full) {
    final trimmed = full.trim();
    if (trimmed.isEmpty) return 'there';
    final space = trimmed.indexOf(' ');
    return space > 0 ? trimmed.substring(0, space) : trimmed;
  }

  String _initials(String full) {
    final parts =
        full.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'M';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _greetingWord() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _dateEyebrow() {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

class _Avatar extends StatelessWidget {
  final Uint8List? bytes;
  final String initials;
  final Color bg;
  final VoidCallback? onTap;

  const _Avatar({
    required this.bytes,
    required this.initials,
    required this.bg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = bytes != null && bytes!.isNotEmpty;

    final circle = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x59FFFFFF), width: 2),
      ),
      alignment: Alignment.center,
      child: hasImage
          ? ClipOval(
              child: OdooAvatar(
                imageBytes: bytes,
                size: 40,
                iconSize: 20,
                placeholderColor: bg,
                iconColor: Colors.white,
              ),
            )
          : Text(
              initials,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    );

    if (onTap == null) return circle;
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: circle,
    );
  }
}
