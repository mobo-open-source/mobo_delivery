import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:odoo_delivery_app/shared/widgets/odoo_avatar.dart';

class ProfileHeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String? jobFunction;
  final String? avatarBase64;
  final VoidCallback? onCameraPressed;
  final VoidCallback? onTap;
  final bool showCameraButton;

  const ProfileHeaderCard({
    super.key,
    required this.name,
    required this.email,
    this.jobFunction,
    this.avatarBase64,
    this.onCameraPressed,
    this.onTap,
    this.showCameraButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    double rs(double size) {
      final w = MediaQuery.of(context).size.width;
      final scale = (w / 390.0).clamp(0.85, 1.2);
      return size * scale;
    }

    final content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar Section
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                    ),
                    child: OdooAvatar(
                      imageBase64: avatarBase64,
                      size: 64,
                      iconSize: 28,
                      placeholderColor: Colors.white.withOpacity(0.1),
                      iconColor: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                ),
                if (showCameraButton && onCameraPressed != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: onCameraPressed,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          color: theme.primaryColor,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Info Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: rs(18),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: GoogleFonts.manrope(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: rs(13),
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (jobFunction != null && jobFunction!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      jobFunction!,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: rs(11),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Arrow Icon
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 16,
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }
}
