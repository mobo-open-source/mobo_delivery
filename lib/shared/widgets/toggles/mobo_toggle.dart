import 'package:flutter/material.dart';
import '../../utils/globals.dart';

/// A custom animated toggle switch that matches mobo_inv_app's MoboToggle style.
class MoboToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const MoboToggle({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = AppStyle.primaryColor;

    return Semantics(
      button: true,
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: 56,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: value
                ? primaryColor
                : (isDark ? Colors.transparent : primaryColor.withValues(alpha: 0.06)),
            border: Border.all(
              color: value
                  ? primaryColor
                  : (isDark ? Colors.grey[400]! : primaryColor),
              width: 2,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: 24,
              height: 24,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Colors.white : primaryColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
