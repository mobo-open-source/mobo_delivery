import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:odoo_delivery_app/shared/utils/memory_page_manager.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'Dashboard/models/profile.dart';
import 'Dashboard/services/settings_storage_service.dart';
import 'Dashboard/services/storage_service.dart';
import 'LoginPage/views/login_screen.dart';
import 'LoginPage/views/splash_screen.dart';
import 'NavBars/Pickings/PickingFormPage/models/move_line.dart';
import 'NavBars/Pickings/PickingFormPage/models/return_picking.dart';
import 'NavBars/Pickings/PickingListPage/models/picking_model.dart';
import 'core/company/providers/company_provider.dart';
import 'core/navigation/global_keys.dart';
import 'core/providers/theme_provider.dart';

/// Global Odoo client instance (initialized after login)
OdooClient? client;

/// Base Odoo server URL (set after login)
String url = "";

/// Current authenticated user ID (set after login)
int? userId;

/// Global navigator key for programmatic navigation & snackbars
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global memory page manager for large binary data buffering
final memoryManager = MemoryPageManager();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  GoogleFonts.config.allowRuntimeFetching = false;

  await dotenv.load(fileName: ".env");

  await Hive.initFlutter();

  Hive.registerAdapter(PickingAdapter());
  Hive.registerAdapter(ProfileAdapter());
  Hive.registerAdapter(MoveLineAdapter());
  Hive.registerAdapter(ReturnPickingAdapter());

  await Hive.openBox<Picking>('pickings');

  final settingsStorageService = SettingsStorageService();
  await settingsStorageService.initialize();

  final VideoPlayerController videoController = VideoPlayerController.asset(
    'assets/videos/Delivery.mp4',
  );
  await videoController.initialize();
  videoController.setLooping(false);
  videoController.play();

  runApp(
    MultiProvider(
      providers: [
        Provider<DashboardStorageService>(
          create: (_) => DashboardStorageService(),
        ),
        Provider<SettingsStorageService>.value(value: settingsStorageService),

        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        ChangeNotifierProvider(
          create: (_) {
            final p = CompanyProvider();
            p.initialize();
            return p;
          },
        ),

        ListenableProvider<VideoPlayerController>.value(value: videoController),

        Provider<MemoryPageManager>.value(value: memoryManager),
      ],
      child: LoginApp(),
    ),
  );
}

/// Root widget after providers are set up
///
/// Handles:
/// - Theme switching (light/dark)
/// - Motion reduction (accessibility)
/// - Custom page transitions
/// - Initial route (splash → login)
class LoginApp extends StatefulWidget {
  @override
  _LoginAppState createState() => _LoginAppState();
}

class _LoginAppState extends State<LoginApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Login Page',
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,

      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,

      initialRoute: '/',

      onGenerateRoute: (settings) {
        WidgetBuilder builder;

        switch (settings.name) {
          case '/':
            builder = (context) => SplashScreen();
            break;
          case '/login':
            builder = (context) => LoginScreen();
            break;
          default:
            builder = (context) => SplashScreen();
        }
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
return FadeTransition(opacity: animation, child: child);
          },
        );
      },
    );
  }
}
