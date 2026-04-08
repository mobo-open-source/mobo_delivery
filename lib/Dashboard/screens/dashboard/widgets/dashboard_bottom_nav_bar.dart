import 'package:flutter/material.dart';
import 'package:flutter_snake_navigationbar/flutter_snake_navigationbar.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../shared/utils/globals.dart';

/// A premium bottom navigation bar using SnakeNavigationBar.
/// 
/// Modeled after the mobo_inv_app navigation bar.
class DashboardBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final List<Map<String, dynamic>> pages;
  final ValueChanged<int> onTap;

  const DashboardBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.pages,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SnakeNavigationBar.color(
      behaviour: SnakeBarBehaviour.pinned,
      snakeShape: SnakeShape.indicator,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      selectedItemColor: isDark ? Colors.white : AppStyle.primaryColor,
      unselectedItemColor: isDark ? Colors.grey[400] : Colors.black54,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      currentIndex: currentIndex,
      onTap: onTap,
      items: _buildNavItems(context, isDark),
      snakeViewColor: AppStyle.primaryColor,
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.grey[400] : Colors.grey[600],
      ),
      selectedLabelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : AppStyle.primaryColor,
      ),
      shadowColor: isDark ? Colors.black26 : Colors.grey[200]!,
      elevation: 8,
      height: 70,
    );
  }

  List<BottomNavigationBarItem> _buildNavItems(
    BuildContext context,
    bool isDark,
  ) {
    return pages.map((page) {
      return _buildItem(
        icon: page['icon'],
        label: page['label'],
        isDark: isDark,
        primaryColor: AppStyle.primaryColor,
      );
    }).toList();
  }

  BottomNavigationBarItem _buildItem({
    required dynamic icon,
    required String label,
    required bool isDark,
    required Color primaryColor,
  }) {
    Widget buildIconWidget(Color? color) {
      if (icon is IconData) {
        return Icon(icon, color: color);
      }
      // Assuming icon is from HugeIcons
      return HugeIcon(
        icon: icon,
        color: color ?? (isDark ? Colors.white : Colors.black54),
        size: 24,
      );
    }

    return BottomNavigationBarItem(
      icon: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        child: buildIconWidget(null),
      ),
      label: label,
      activeIcon: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        child: buildIconWidget(isDark ? Colors.white : primaryColor),
      ),
    );
  }
}
