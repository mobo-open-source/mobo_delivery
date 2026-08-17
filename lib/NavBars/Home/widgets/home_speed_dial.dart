import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../Dashboard/screens/dashboard/bloc/dashboard_bloc.dart';
import '../../../Dashboard/screens/dashboard/bloc/dashboard_event.dart';
import '../../../shared/theme/mobo_home_theme.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/dialogs/loading_dialog.dart';
import '../../MapBox/services/route_plan_bus.dart';
import '../../Pickings/CreateNewPicking/pages/create_picking_page.dart';
import '../../Pickings/PickingListPage/services/picking_service.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';

/// Dashboard tab index the "Plan route" action jumps to.
const int _kRouteTabIndex = 2;

/// Home's corner speed dial — New picking, Plan route.
class HomeSpeedDial extends StatelessWidget {
  const HomeSpeedDial({super.key});

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const triggerBg = AppStyle.primaryColor;
    const triggerFg = Colors.white;
    final childBg = isDark ? Colors.grey[800]! : AppStyle.primaryColor;
    const childFg = Colors.white;
    final labelBg = isDark ? Colors.grey[800]! : home.surface;
    final labelFg = isDark ? Colors.white : home.textPrimary;

    return SpeedDial(
      heroTag: 'homeSpeedDial',
      tooltip: 'Actions',
      animatedIcon: AnimatedIcons.menu_close,
      animatedIconTheme: IconThemeData(size: 22, color: triggerFg),
      backgroundColor: triggerBg,
      foregroundColor: triggerFg,
      overlayColor: Colors.black,
      overlayOpacity: isDark ? 0.30 : 0.20,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      direction: SpeedDialDirection.up,
      spacing: 8,
      spaceBetweenChildren: 8,
      childPadding: const EdgeInsets.all(6),
      childMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      closeManually: false,
      useRotationAnimation: true,
      animationCurve: Curves.easeOutCubic,
      animationDuration: const Duration(milliseconds: 160),
      onOpen: () => HapticFeedback.lightImpact(),
      onClose: () => HapticFeedback.selectionClick(),
      children: [
        _child(
          icon: HugeIcons.strokeRoundedPackageAdd,
          label: 'New picking',
          childBg: childBg,
          childFg: childFg,
          labelBg: labelBg,
          labelFg: labelFg,
          onTap: () => _newPicking(context),
        ),
        _child(
          icon: HugeIcons.strokeRoundedRoute02,
          label: 'Plan route',
          childBg: childBg,
          childFg: childFg,
          labelBg: labelBg,
          labelFg: labelFg,
          onTap: () {
            context.read<DashboardBloc>().add(const ChangeTab(_kRouteTabIndex));
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => RoutePlanBus.request(),
            );
          },
        ),
      ],
    );
  }

  SpeedDialChild _child({
    required IconData icon,
    required String label,
    required Color childBg,
    required Color childFg,
    required Color labelBg,
    required Color labelFg,
    required VoidCallback onTap,
  }) {
    return SpeedDialChild(
      child: Icon(icon, size: 20, color: childFg),
      backgroundColor: childBg,
      elevation: 3,
      label: label,
      labelBackgroundColor: labelBg,
      labelStyle: TextStyle(
        color: labelFg,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      onTap: onTap,
    );
  }

  /// Opens the create-picking flow, then refreshes Home.
  Future<void> _newPicking(BuildContext context) async {
    final homeBloc = context.read<HomeBloc>();
    LoadingDialog.show(context);
    final service = PickingService();
    await service.initializeOdooClient();
    await service.checkNetworkConnectivity();
    if (!context.mounted) return;
    LoadingDialog.hide(context);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreatePickingPage(url: service.url)),
    );
    homeBloc.add(const LoadHome(forceRefresh: true));
  }
}
