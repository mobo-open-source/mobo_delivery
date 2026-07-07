import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../Dashboard/screens/dashboard/bloc/dashboard_bloc.dart';
import '../../../Dashboard/screens/dashboard/bloc/dashboard_event.dart';
import '../../../Dashboard/screens/dashboard/bloc/dashboard_state.dart';
import '../../../Dashboard/screens/configuration.dart';
import '../../../shared/theme/mobo_home_theme.dart';
import '../../MapBox/services/route_plan_bus.dart';
import '../../Pickings/CreateNewPicking/pages/create_picking_page.dart';
import '../../Pickings/PickingFormPage/pages/picking_details_page.dart';
import '../../Pickings/PickingFormPage/services/odoo_picking_form_service.dart';
import '../../Pickings/PickingListPage/services/picking_service.dart';
import '../../Pickings/PickingListPage/services/pickings_filter_bus.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../widgets/all_caught_up.dart';
import '../widgets/header_banner.dart';
import '../widgets/picking_row.dart';
import '../widgets/quick_action_button.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_tile.dart';

/// Bottom-nav index of the Pickings tab after Home is prepended.
/// Kept as a named constant so the Home screen and any future deep-link
/// code don't reintroduce hardcoded integers.
const int _kPickingsTabIndex = 1;

/// Home — first tab of the dashboard.
///
/// Composition:
///   1. Maroon greeting header (embeds the existing `CompanySelectorWidget`)
///   2. Sync-status strip (online/offline, pending count, "Sync now")
///   3. 2×2 stat tiles → open Pickings tab pre-filtered via `PickingsFilterBus`
///   4. Quick-action row (New picking, Plan route, Attach doc — 3 tiles;
///      Scan barcode is intentionally omitted — no scanner in the app.)
///   5. "Needs attention" section → picking rows or empty / skeleton state.
///
/// All navigation routes into existing screens; nothing new is created here.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeBloc()..add(const LoadHome()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(

      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<HomeBloc, HomeState>(
          builder: (context, state) {
            final dashState = context.watch<DashboardBloc>().state;
            return RefreshIndicator(
              onRefresh: () async {
                context.read<HomeBloc>().add(const LoadHome(forceRefresh: true));

                await Future.delayed(const Duration(milliseconds: 400));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HeaderBanner(
                      name: dashState.userName ?? 'User',
                      avatarBytes: dashState.profilePicBytes,
                      online: state.online,
                      onAvatarTap: () => _openConfiguration(context, dashState),
                    ),
                    const SizedBox(height: 16),
                    _StatGrid(state: state),
                    const SizedBox(height: 11),
                    _QuickActions(),
                    const SizedBox(height: 20),
                    SectionHeader(
                      title: 'Needs attention',
                      trailingLabel: 'View all',
                      onTrailingTap: () => _openPickings(context, null),
                    ),
                    const SizedBox(height: 10),
                    _AttentionList(state: state),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openConfiguration(BuildContext context, DashboardState dashState) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Configuration(
          profileImageBytes: dashState.profilePicBytes,
          userName: dashState.userName,
          mail: dashState.mail,
        ),
      ),
    ).then((_) {
      if (context.mounted) {
        context.read<DashboardBloc>().add(RefreshUserProfile());
      }
    });
  }

  void _openPickings(BuildContext context, String? chip) {

    PickingsFilterBus.request(chip);
    context.read<DashboardBloc>().add(const ChangeTab(_kPickingsTabIndex));
  }
}

class _StatGrid extends StatelessWidget {
  final HomeState state;
  const _StatGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;

    if (state.status == HomeStatus.loading) {
      return const _Grid(
        children: [
          StatTileSkeleton(),
          StatTileSkeleton(),
          StatTileSkeleton(),
          StatTileSkeleton(),
        ],
      );
    }

    final counts = state.counts;
    return _Grid(
      children: [
        StatTile(
          icon: HugeIcons.strokeRoundedPackage,
          value: counts.ready,
          label: 'Ready to ship',
          accentFg: home.readyFg,
          accentBg: home.readyBg,
          onTap: () => _tap(context, 'ready'),
        ),
        StatTile(
          icon: HugeIcons.strokeRoundedClock01,
          value: counts.waiting,
          label: 'Waiting',
          accentFg: home.waitFg,
          accentBg: home.waitBg,
          onTap: () => _tap(context, 'waiting'),
        ),
        StatTile(
          icon: HugeIcons.strokeRoundedAlert02,
          value: counts.late,
          label: 'Late',
          accentFg: home.lateFg,
          accentBg: home.lateBg,
          prominent: true,
          onTap: () => _tap(context, 'late'),
        ),
        StatTile(
          icon: HugeIcons.strokeRoundedCheckmarkCircle02,
          value: counts.doneToday,
          label: 'Done today',
          accentFg: home.doneFg,
          accentBg: home.doneBg,
          onTap: () => _tap(context, 'donetoday'),
        ),
      ],
    );
  }

  void _tap(BuildContext context, String chip) {
    PickingsFilterBus.request(chip);
    context.read<DashboardBloc>().add(const ChangeTab(_kPickingsTabIndex));
  }
}

class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid({required this.children});

  @override
  Widget build(BuildContext context) {
    assert(children.length == 4);
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[0]),
              const SizedBox(width: 11),
              Expanded(child: children[1]),
            ],
          ),
        ),
        const SizedBox(height: 11),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[2]),
              const SizedBox(width: 11),
              Expanded(child: children[3]),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QuickActionButton(
          icon: HugeIcons.strokeRoundedPackageAdd,
          label: 'New picking',
          onTap: () => _newPicking(context),
        ),
        const SizedBox(width: 9),
        QuickActionButton(
          icon: HugeIcons.strokeRoundedRoute02,
          label: 'Plan route',
          onTap: () {

            context.read<DashboardBloc>().add(const ChangeTab(2));
            WidgetsBinding.instance
                .addPostFrameCallback((_) => RoutePlanBus.request());
          },
        ),
        const SizedBox(width: 9),
        QuickActionButton(
          icon: HugeIcons.strokeRoundedDocumentAttachment,
          label: 'Attach doc',
          onTap: () =>
              context.read<DashboardBloc>().add(const ChangeTab(4)),
        ),
      ],
    );
  }

  Future<void> _newPicking(BuildContext context) async {

    final service = PickingService();
    await service.initializeOdooClient();

    await service.checkNetworkConnectivity();
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreatePickingPage(url: service.url)),
    );
    if (!context.mounted) return;
    context.read<HomeBloc>().add(const LoadHome(forceRefresh: true));
  }
}

class _AttentionList extends StatelessWidget {
  final HomeState state;
  const _AttentionList({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.status == HomeStatus.loading) {
      return Column(
        children: List.generate(
          4,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i == 3 ? 0 : 12),
            child: const PickingRowSkeleton(),
          ),
        ),
      );
    }

    if (state.status == HomeStatus.error) {
      return _ErrorCard(
        message: state.errorMessage ?? 'Could not load pickings.',
        onRetry: () =>
            context.read<HomeBloc>().add(const LoadHome(forceRefresh: true)),
      );
    }

    if (state.attention.isEmpty) {
      return const AllCaughtUp();
    }

    return Column(
      children: [
        for (int i = 0; i < state.attention.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == state.attention.length - 1 ? 0 : 12,
            ),
            child: PickingRow(
              row: state.attention[i],
              onTap: () => _openDetails(context, state.attention[i]),
            ),
          ),
      ],
    );
  }

  Future<void> _openDetails(BuildContext context, dynamic row) async {
    final picking = <String, dynamic>{
      'id': row.id,
      'name': row.reference,
    };
    final service = OdooPickingFormService();
    await service.initializeOdooClient();
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickingDetailsPage(
          picking: picking,
          odooService: service,
          isPickingForm: true,
          isReturnPicking: false,
          isReturnCreate: false,
        ),
      ),
    );
    if (!context.mounted) return;
    context.read<HomeBloc>().add(const LoadHome(forceRefresh: true));
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: home.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: home.lateBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: home.lateFg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: home.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: home.qaFg,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
