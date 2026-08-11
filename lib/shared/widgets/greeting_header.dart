import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../utils/globals.dart';
import 'loaders/loading_indicator.dart';
import 'odoo_avatar.dart';

/// A greeting banner shown at the top of a main screen, in the sales-app style.
///
/// Presentational: pass [userName] and [imageBytes] from the same source the
/// rest of the app uses for the current user.
class GreetingHeader extends StatelessWidget {
  /// Full name of the current user; only the first word is shown.
  final String? userName;

  /// Decoded profile image bytes. When null the avatar falls back to an initial.
  final Uint8List? imageBytes;

  /// Short line shown under the greeting.
  final String subtitle;

  /// Tints [subtitle] amber to flag a degraded connection.
  final bool isOffline;

  /// Swaps the greeting and subtitle for shimmer bars while loading.
  final bool isLoading;

  /// Outer margin around the card.
  final EdgeInsetsGeometry margin;

  /// Called when the avatar is tapped.
  final VoidCallback? onAvatarTap;

  const GreetingHeader({
    super.key,
    this.userName,
    this.imageBytes,
    this.subtitle = 'Manage your deliveries efficiently',
    this.isOffline = false,
    this.isLoading = false,
    this.margin = EdgeInsets.zero,
    this.onAvatarTap,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = (userName ?? '').trim();
    final firstName = trimmed.isEmpty ? '' : trimmed.split(' ').first;
    final greetingText = firstName.isEmpty
        ? '${_greeting()}!'
        : '${_greeting()} $firstName!';

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppStyle.primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: isLoading
                ? const _GreetingShimmer()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        greetingText,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: GoogleFonts.manrope(
                          color: isOffline
                              ? Colors.orange[200]
                              : Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 10),
          _Avatar(
            imageBytes: imageBytes,
            fallbackName: trimmed,
            onTap: onAvatarTap,
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder for the greeting block — two shimmer bars.
class _GreetingShimmer extends StatelessWidget {
  const _GreetingShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _bar(
          height: 28,
          width: 200,
          radius: 6,
          base: 0.3,
          highlight: 0.6,
          fill: 0.4,
        ),
        const SizedBox(height: 12),
        _bar(
          height: 18,
          width: 280,
          radius: 4,
          base: 0.2,
          highlight: 0.4,
          fill: 0.3,
        ),
      ],
    );
  }

  Widget _bar({
    required double height,
    required double width,
    required double radius,
    required double base,
    required double highlight,
    required double fill,
  }) {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: base),
      highlightColor: Colors.white.withValues(alpha: highlight),
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: fill),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// 56px avatar with a white ring; falls back to an initial, or a spinner
/// while the profile is still loading.
class _Avatar extends StatelessWidget {
  static const double _diameter = 56;

  final Uint8List? imageBytes;
  final String fallbackName;
  final VoidCallback? onTap;

  const _Avatar({
    required this.imageBytes,
    required this.fallbackName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null && imageBytes!.isNotEmpty;

    final avatar = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: _diameter,
          height: _diameter,
          child: hasImage
              ? OdooAvatar(
                  key: const ValueKey('greeting_avatar_image'),
                  imageBytes: imageBytes,
                  size: _diameter,
                  iconSize: 26,
                  placeholderColor: AppStyle.primaryColor,
                  iconColor: Colors.white,
                )
              : ColoredBox(
                  color: AppStyle.primaryColor,
                  child: Center(
                    child: fallbackName.isEmpty
                        ? const SmallLoadingIndicator(color: Colors.white)
                        : Text(
                            fallbackName.substring(0, 1).toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: _diameter * 0.4,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                  ),
                ),
        ),
      ),
    );

    if (onTap == null) return avatar;
    return InkResponse(onTap: onTap, radius: 32, child: avatar);
  }
}
