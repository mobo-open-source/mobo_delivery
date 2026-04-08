import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// A highly configurable loading widget that can be used as a standalone spinner or a full-screen overlay.
class LoadingWidget extends StatelessWidget {
  const LoadingWidget({
    super.key,
    this.message,
    this.color,
    this.size = 40,
    this.variant = LoadingVariant.staggeredDots,
    this.reduceMotion = false,
    this.overlay = false,
    this.barrierDismissible = false,
  });

  final String? message;

  final Color? color;

  final double size;

  final LoadingVariant variant;

  final bool reduceMotion;

  final bool overlay;

  final bool barrierDismissible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolvedColor = color ?? theme.primaryColor;

    final loader = _buildLoader(resolvedColor, isDark);

    if (!overlay) return loader;

    // LayoutBuilder guards against unbounded-height parents (e.g. a Column
    // without tight constraints). ModalBarrier uses ConstrainedBox.expand()
    // internally and throws if it receives an infinite-height constraint.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          // Unbounded context (e.g. inside a Column) — show spinner only.
          return Center(child: _buildAnimated(resolvedColor, isDark));
        }
        return Stack(
          children: [
            Semantics(
              container: true,
              label: 'Loading overlay',
              child: ModalBarrier(
                dismissible: barrierDismissible,
                color: Colors.black.withValues(alpha: 0.2),
              ),
            ),

            Center(
              child: Card(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildAnimated(resolvedColor, isDark),
                      if (message != null &&
                          message!.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color:
                                isDark ? Colors.grey[300] : Colors.black87,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoader(Color resolvedColor, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAnimated(resolvedColor, isDark),
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.black87,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimated(Color resolvedColor, bool isDark) {
    if (reduceMotion) {
      return Icon(
        Icons.hourglass_empty_rounded,
        color: resolvedColor,
        size: size,
      );
    }

    switch (variant) {
      case LoadingVariant.fourRotatingDots:
        return LoadingAnimationWidget.fourRotatingDots(
          color: resolvedColor,
          size: size,
        );
      case LoadingVariant.staggeredDots:
        return LoadingAnimationWidget.staggeredDotsWave(
          color: resolvedColor,
          size: size,
        );
      case LoadingVariant.threeArchedCircle:
        return LoadingAnimationWidget.threeArchedCircle(
          color: resolvedColor,
          size: size,
        );
    }
  }
}

/// Defines the visual variant of the loading animation.
enum LoadingVariant { staggeredDots, fourRotatingDots, threeArchedCircle }
