import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/globals.dart';
import 'odoo_avatar.dart';

/// A greeting banner shown at the top of a main screen — mirrors the sales
/// app dashboard's "morning section": a brand-colored card with a
/// time-of-day greeting, the user's first name, a short subtitle and the
/// user's avatar on the right.
///
/// This widget is presentational: pass [userName] and [imageBytes] from the
/// same source the rest of the app uses for the current user (the
/// `DashboardBloc` state), so the avatar/name update automatically whenever
/// the profile is refreshed.
class GreetingHeader extends StatelessWidget {
  /// Full name of the current user; only the first word is shown.
  final String? userName;

  /// Decoded profile image bytes. When null the avatar falls back to an icon.
  final Uint8List? imageBytes;

  /// Short line shown under the greeting.
  final String subtitle;

  /// Outer margin around the card.
  final EdgeInsetsGeometry margin;

  const GreetingHeader({
    super.key,
    this.userName,
    this.imageBytes,
    this.subtitle = 'Manage your deliveries efficiently',
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final firstName = (userName ?? '').trim().isEmpty
        ? ''
        : userName!.trim().split(' ').first;
    final greetingText =
        firstName.isEmpty ? '${_greeting()}!' : '${_greeting()} $firstName!';

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppStyle.primaryColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greetingText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Stack(
            clipBehavior: Clip.none,
            children: [
              // White ring + soft shadow around the avatar (sales-app style).
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: OdooAvatar(
                  key: ValueKey(
                    'greeting_avatar_${imageBytes != null ? "image" : "placeholder"}',
                  ),
                  imageBytes: imageBytes,
                  size: 44,
                  iconSize: 24,
                  borderRadius: BorderRadius.circular(22),
                  placeholderColor: Colors.white,
                  iconColor: AppStyle.primaryColor,
                ),
              ),
              // Online status dot.
              Positioned(
                right: 0,
                bottom: 1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppStyle.primaryColor, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
