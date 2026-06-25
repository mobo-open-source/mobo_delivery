import 'package:flutter/material.dart';

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({
    super.key,
    this.message,
    this.color,
    this.size = 40,
    this.variant = LoadingVariant.staggeredDots,
    this.overlay = false,
    this.barrierDismissible = false,
  });

  final String? message;
  final Color? color;
  final double size;
  final LoadingVariant variant;
  final bool overlay;
  final bool barrierDismissible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolvedColor = color ?? theme.primaryColor;

    if (!overlay) return _buildSpinner(resolvedColor, isDark);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Center(child: _buildSpinner(resolvedColor, isDark));
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
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 20,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: resolvedColor,
                          strokeWidth: 3,
                        ),
                      ),
                      if (message != null && message!.trim().isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text(
                            message!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.grey[300] : Colors.black87,
                            ),
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

  Widget _buildSpinner(Color resolvedColor, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              color: resolvedColor,
              strokeWidth: 3,
            ),
          ),
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
}

enum LoadingVariant { staggeredDots, fourRotatingDots, threeArchedCircle }
