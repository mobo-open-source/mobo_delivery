import 'package:flutter/material.dart';

/// Global navigator key used for navigation without BuildContext.
/// Enables routing actions like push or pop from services or managers.
/// Useful for app-wide navigation handling.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global scaffold messenger key used to show SnackBars globally.
/// Allows showing messages without direct access to BuildContext.
/// Useful for global error or success notifications.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
