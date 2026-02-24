import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:provider/provider.dart';
import '../../../../NavBars/AttachDocument/pages/attach_documents_page.dart';
import '../../../../NavBars/PickingNotes/screens/picking_notes_page.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

    return BlocProvider(
      create: (_) => DashboardBloc(DashboardStorageService(), (url, session) {
        return OdooDashboardService(url, session);
      })..add(InitializeDashboard(widget.initialIndex)),
      child: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          final bloc = context.read<DashboardBloc>();

          // ── Loading state ────────────────────────────────────────────────
          if (state.isLoading) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LoadingAnimationWidget.fourRotatingDots(
                      color: isDark ? Colors.white : AppStyle.primaryColor,
                      size: 50,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading Delivery App...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : AppStyle.primaryColor,
                      ),
                    ),
                  ],
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
                        // Company selector (limited width)
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 160,
                          ),
                          child: CompanySelectorWidget(
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
                        ),
                        SizedBox(width: 10),

                        // Profile avatar → opens Configuration screen
                        GestureDetector(
                          onTap: () async {
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
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white,
                            backgroundImage: state.profilePicBytes != null
                                ? MemoryImage(state.profilePicBytes!)
                                : null,
                            child: state.profilePicBytes == null
                                ? const Icon(
                                    Icons.person,
                                    color: AppStyle.primaryColor,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    )
                  : null,

              // ── Main content ─────────────────────────────────────────────────
              body: currentPage['route'] ?? const SizedBox.shrink(),

              // ── Bottom Navigation ────────────────────────────────────────────
              bottomNavigationBar: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                backgroundColor: isDark ? Colors.grey[800] : Colors.white,
                currentIndex: state.currentIndex,
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
                selectedItemColor: isDark
                    ? Colors.white
                    : AppStyle.primaryColor,
                unselectedItemColor: isDark ? Colors.white54 : Colors.black54,
                selectedLabelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                items: state.pages
                    .map(
                      (page) => BottomNavigationBarItem(
                        icon: Icon(page['icon']),
                        label: page['label'],
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
