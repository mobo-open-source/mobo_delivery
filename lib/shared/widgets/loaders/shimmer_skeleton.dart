import 'package:flutter/material.dart';

/// A base widget for creating shimmer effects by applying a sliding gradient mask to its child.
class Shimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const Shimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xffF0F3F5);
    final highlight = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xffF7FAFC);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (rect) {
            final gradient = LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.3, 0.5, 0.7],
              begin: Alignment(-1 - 2, 0),
              end: Alignment(1 + 2, 0),
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            );
            return gradient.createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0.0,
      0.0,
    );
  }
}

/// A basic rectangular skeleton block with shimmer animation.
class SkeletonBox extends StatelessWidget {
  final double height;
  final double width;
  final BorderRadiusGeometry borderRadius;
  const SkeletonBox({
    super.key,
    required this.height,
    required this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF2A2A2A) : const Color(0xffE8EEF2);
    return ClipRRect(
      borderRadius: borderRadius,
      child: Shimmer(
        child: Container(height: height, width: width, color: color),
      ),
    );
  }
}

/// A convenient skeleton widget representing a single line of text.
class SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  const SkeletonLine({
    super.key,
    this.width = double.infinity,
    this.height = 14,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      height: height,
      width: width,
      borderRadius: BorderRadius.circular(6),
    );
  }
}
