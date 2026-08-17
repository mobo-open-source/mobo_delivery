import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../Dashboard/screens/dashboard/bloc/dashboard_bloc.dart';
import '../../../Dashboard/screens/dashboard/bloc/dashboard_event.dart';
import '../../../Dashboard/screens/dashboard/bloc/dashboard_state.dart';
import '../../../Dashboard/screens/configuration.dart';
import '../../../shared/theme/mobo_home_theme.dart';
import '../../../shared/widgets/greeting_header.dart';
import '../../Pickings/PickingFormPage/pages/picking_details_page.dart';
import '../../Pickings/PickingFormPage/services/odoo_picking_form_service.dart';
import '../../Pickings/PickingListPage/services/pickings_filter_bus.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../widgets/all_caught_up.dart';
import '../widgets/home_speed_dial.dart';
import '../widgets/picking_row.dart';
import '../widgets/section_error_state.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_tile.dart';

/// Bottom inset so the [HomeSpeedDial] never covers the last attention row.
const double _kFabScrollInset = 32;

/// Bottom-nav index of the Pickings tab after Home is prepended.
/// Kept as a named constant so the Home screen and any future deep-link
/// code don't reintroduce hardcoded integers.
const int _kPickingsTabIndex = 1;

/// Home — first tab of the dashboard.
///
/// Composition:
///   1. Maroon `GreetingHeader` — the shared sales-app greeting card; its
///      subtitle doubles as the online/offline indicator
///   2. "Overview" section → 2×2 stat tiles, each opening the Pickings tab
///      pre-filtered via `PickingsFilterBus`
///   3. "Needs attention" section → picking rows or empty / skeleton state.
///   4. Corner [HomeSpeedDial] — New picking, Plan route.
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
                context.read<HomeBloc>().add(
                  const LoadHome(forceRefresh: true),
                );

                await Future.delayed(const Duration(milliseconds: 400));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  _kFabScrollInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GreetingHeader(
                      userName: dashState.userName,
                      imageBytes: dashState.profilePicBytes,
                      isOffline: !state.online,
                      isLoading: state.status == HomeStatus.loading,
                      subtitle: state.online
                          ? "Let's clear today's deliveries"
                          : 'Working offline — cached data',
                      onAvatarTap: () => _openConfiguration(context, dashState),
                    ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: 'Overview',
                      titleFontSize: 18,
                      titleColor: isDark ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(height: 12),
                    _StatGrid(state: state),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: 'Needs attention',
                      trailingLabel: 'View all',
                      onTrailingTap: () => _openPickings(context, null),
                    ),
                    const SizedBox(height: 12),
                    _AttentionList(state: state),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: const HomeSpeedDial(),
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

    if (state.status == HomeStatus.error) {
      return SectionErrorState(
        sectionTitle: 'Overview',
        message: homeSectionErrorMessage(
          online: state.online,
          error: state.errorMessage,
          offlineDetail:
              'Dashboard counts require network access to load from your '
              'Odoo server.',
          genericDetail: 'Failed to load dashboard data. Please try again.',
        ),
        icon: HugeIcons.strokeRoundedDashboardSquare02,
      );
    }

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
          subtitle: 'Orders ready for pickup',
          accentFg: home.readyFg,
          accentBg: home.readyBg,
          onTap: () => _tap(context, 'ready'),
        ),
        StatTile(
          icon: HugeIcons.strokeRoundedClock01,
          value: counts.waiting,
          label: 'Waiting',
          subtitle: 'Confirmed, not yet ready',
          accentFg: home.waitFg,
          accentBg: home.waitBg,
          onTap: () => _tap(context, 'waiting'),
        ),
        StatTile(
          icon: HugeIcons.strokeRoundedAlert02,
          value: counts.late,
          label: 'Late',
          subtitle: 'Overdue deliveries',
          accentFg: home.lateFg,
          accentBg: home.lateBg,
          prominent: true,
          onTap: () => _tap(context, 'late'),
        ),
        StatTile(
          icon: HugeIcons.strokeRoundedCheckmarkCircle02,
          value: counts.doneToday,
          label: 'Done today',
          subtitle: 'Completed today',
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

  /// Matches the sales-app dashboard grid's phone aspect ratio.
  static const double _cardAspectRatio = 1.15;

  @override
  Widget build(BuildContext context) {
    assert(children.length == 4);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: _cardAspectRatio,
                child: children[0],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AspectRatio(
                aspectRatio: _cardAspectRatio,
                child: children[1],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: _cardAspectRatio,
                child: children[2],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AspectRatio(
                aspectRatio: _cardAspectRatio,
                child: children[3],
              ),
            ),
          ],
        ),
      ],
    );
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
      return SectionErrorState(
        sectionTitle: 'Needs attention',
        message: homeSectionErrorMessage(
          online: state.online,
          error: state.errorMessage,
          offlineDetail:
              'Pickings require network access to load from your Odoo server.',
          genericDetail: 'Failed to load pickings. Please try again.',
        ),
        icon: HugeIcons.strokeRoundedAlert02,
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
    final picking = <String, dynamic>{'id': row.id, 'name': row.reference};
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
