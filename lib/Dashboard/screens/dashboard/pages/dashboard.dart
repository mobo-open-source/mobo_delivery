import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../../../shared/widgets/loaders/loading_indicator.dart';
import '../../../../NavBars/AttachDocument/pages/attach_documents_page.dart';
import '../../../../NavBars/PickingNotes/screens/picking_notes_page.dart';
import '../../../../Rating/review_service.dart';
import '../../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../../core/company/providers/company_provider.dart';
import '../../../../core/company/widgets/company_selector_widget.dart';
import '../../../../core/providers/motion_provider.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/storage_service.dart';
import '../../configuration.dart';
import '../bloc/dashboard_bloc.dart';
import '../bloc/dashboard_event.dart';
import '../bloc/dashboard_state.dart';
import '../widgets/dashboard_bottom_nav_bar.dart';
import '../../../../shared/widgets/odoo_avatar.dart';
import '../../../../core/company/session/company_session_manager.dart';

/// Main dashboard screen of the delivery / logistics application.
///
/// Features:
///   • Bottom navigation bar with dynamic tabs
///   • Company selector in AppBar
///   • Profile avatar that opens configuration/settings
///   • Special handling for "More" / "+" tab (shows bottom sheet)
///   • In-app review prompt after delay
///   • Dark mode support
///   • Motion reduction support (accessibility)
///   • Back button handling (return to home tab or exit app)
class Dashboard extends StatefulWidget {
  /// Initial tab index to display when the dashboard is first opened
  final int initialIndex;

  const Dashboard({super.key, this.initialIndex = 0});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          ReviewService().checkAndShowRating(context);
        }
      });
    });
  }

  /// Checks if a given byte array contains SVG content.
  bool isSvgBytes(Uint8List bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    return str.contains('<svg');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

    return BlocProvider(
      create: (_) => DashboardBloc(DashboardStorageService(), (url, session) {
        return OdooDashboardService(url, session);
      })..add(InitializeDashboard(widget.initialIndex)),
      child: BlocListener<DashboardBloc, DashboardState>(
        listenWhen: (previous, current) =>
            !previous.isSessionExpired && current.isSessionExpired,
        listener: (context, state) {
          if (state.isSessionExpired) {
            CompanySessionManager.logout(context);
          }
        },
        child: BlocBuilder<DashboardBloc, DashboardState>(
          builder: (context, state) {
            final bloc = context.read<DashboardBloc>();

          // ── Loading state ────────────────────────────────────────────────
          if (state.isLoading) {
            return Scaffold(
              body: Center(
                child: LoadingIndicator(
                  message: 'Loading Delivery App...',
                  color: isDark ? Colors.white : AppStyle.primaryColor,
                  size: 50,
                ),
              ),
            );
          }

          final currentPage = state.pages[state.currentIndex];
          final showAppBar = currentPage['title'] != 'Route Visualization';

          return WillPopScope(
            // Handle system back button: return to home tab or exit app
            onWillPop: () async {
              final bloc = context.read<DashboardBloc>();
              if (state.currentIndex != 0) {
                bloc.add(ChangeTab(0));
                return false;
              }
              SystemNavigator.pop();
              return false;
            },
            child: Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
              // ── AppBar (hidden on Route Visualization screen) ─────────────
              appBar: showAppBar
                  ? AppBar(
                      forceMaterialTransparency: true,
                      title: Text(
                        currentPage['title'],
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      automaticallyImplyLeading: false,
                      backgroundColor: isDark
                          ? Colors.grey[900]
                          : Colors.grey[50],
                      actions: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CompanySelectorWidget(
                              onCompanyChanged: () async {
                                if (!context.mounted) return;
                                final provider = context.read<CompanyProvider>();
                                final companyName =
                                    provider.selectedCompany?['name']
                                        ?.toString() ??
                                    'company';
                                bloc.add(RefreshUserProfile());
                                CompanyRefreshBus.notify();

                                CustomSnackbar.showSuccess(
                                  context,
                                  'Switched to $companyName',
                                );
                              },
                            ),
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: IconButton(
                                icon: OdooAvatar(
                                  key: ValueKey(
                                    'avatar_${state.profilePicBytes != null ? "image" : "placeholder"}',
                                  ),
                                  imageBytes: state.profilePicBytes,
                                  size: 32,
                                  iconSize: 18,
                                  borderRadius: BorderRadius.circular(16),
                                  placeholderColor: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[300],
                                  iconColor: isDark ? Colors.white70 : Colors.black54,
                                ),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (_, __, ___) => Configuration(
                                        profileImageBytes: state.profilePicBytes,
                                        userName: state.userName,
                                        mail: state.mail,
                                      ),
                                      transitionDuration: motionProvider.reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 300),
                                      reverseTransitionDuration:
                                          motionProvider.reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 300),
                                      transitionsBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                            child,
                                          ) {
                                            if (motionProvider.reduceMotion)
                                              return child;
                                            return FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            );
                                          },
                                    ),
                                  ).then((_) {
                                    bloc.add(RefreshUserProfile());
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : null,

              // ── Main content ─────────────────────────────────────────────────
              body: Column(
                children: [
                  // Offline banner — shown when server is unreachable
                  if (!state.isServerReachable)
                    _OfflineBanner(
                      onRetry: () => bloc.add(RefreshUserProfile()),
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: state.currentIndex,
                      children: state.pages
                          .map<Widget>(
                            (p) => p['route'] as Widget? ??
                                const SizedBox.shrink(),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),

              // ── Bottom Navigation ────────────────────────────────────────────
              bottomNavigationBar: DashboardBottomNavBar(
                currentIndex: state.currentIndex,
                pages: state.pages,
                onTap: (index) {
                  final bloc = context.read<DashboardBloc>();
                  final page = state.pages[index];

                  if (page['route'] != null) {
                    // Normal tab → change page
                    bloc.add(ChangeTab(index));
                  } else {
                    // "More" / "+" tab → show bottom sheet with extra actions
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: isDark ? Colors.black87 : Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      isScrollControlled: true,
                      builder: (context) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: Icon(
                                  HugeIcons.strokeRoundedNote05,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                title: Text(
                                  'Log Notes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const PickingNotesPage(),
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                leading: Icon(
                                  HugeIcons.strokeRoundedLink01,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                title: Text(
                                  'Attach Document',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AttachDocumentsPage(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}
}

/// Slim banner shown at the top of Dashboard body when the server is unreachable.
///
/// Provides a visible offline indicator without blocking any screen content.
/// Tapping "Retry" triggers a profile refresh which re-checks connectivity.
class _OfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _OfflineBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF3A2A00) : const Color(0xFFFFF3CD),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 16,
              color: isDark ? Colors.orange[300] : Colors.orange[800],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Server unreachable — running in offline mode',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.orange[200] : Colors.orange[900],
                ),
              ),
            ),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.orange[300] : Colors.orange[800],
                  decoration: TextDecoration.underline,
                  decorationColor:
                      isDark ? Colors.orange[300] : Colors.orange[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
