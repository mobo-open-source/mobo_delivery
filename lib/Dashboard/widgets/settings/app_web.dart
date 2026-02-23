import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/widgets/snackbar.dart';

/// A full-screen in-app web browser page using `webview_flutter`.
///
/// Displays any web URL inside the app with:
/// • A modern AppBar with back button and customizable title
/// • Loading indicator while page is loading
/// • Error handling via snackbar when page fails to load
/// • Dark/light theme support
/// • JavaScript enabled by default
///
/// This widget is typically used to open external links, help pages,
/// terms & conditions, privacy policy, or any web content without leaving the app.
///
/// Example usage:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (context) => InAppWebPage(
///       url: Uri.parse('https://example.com/privacy'),
///       title: 'Privacy Policy',
///     ),
///   ),
/// );
/// ```
class InAppWebPage extends StatefulWidget {
  final Uri url;
  final String? title;

  const InAppWebPage({super.key, required this.url, this.title});

  @override
  State<InAppWebPage> createState() => _InAppWebPageState();
}

class _InAppWebPageState extends State<InAppWebPage> {
  bool isLoading = true;

  /// Controller for managing the WebView (navigation, JS, etc.)
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // Enable JavaScript (most modern websites require it)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Start loading the requested URL
      ..loadRequest(widget.url)
      // Handle navigation events
      ..setNavigationDelegate(
        NavigationDelegate(
          // Hide loading indicator when page has finished rendering
          onPageFinished: (_) {
            if (mounted) setState(() => isLoading = false);
          },
          // Show error snackbar if loading fails (no internet, invalid URL, etc.)
          onWebResourceError: (error) {
            if (mounted) {
              CustomSnackbar.showError(
                context,
                'Failed to load page: ${error.description}',
              );
            }
          },
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      /// AppBar with back button (no automatic leading arrow)
      appBar: AppBar(
        title: Text(
          widget.title ?? 'Web Page',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
            size: 28,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
      ),

      /// Main body: WebView + centered loading overlay
      body: Stack(
        children: [
          /// The actual web content viewer
          WebViewWidget(controller: _controller),

          /// The actual web content viewer
          if (isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
