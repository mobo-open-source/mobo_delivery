import 'package:flutter/material.dart';
import 'package:odoo_delivery_app/Rating/review_service.dart';

/// A customizable rating dialog that allows users to rate the app
/// and optionally provide feedback.
///
/// If the user gives a rating of 4 stars or higher, the [onGoodReview]
/// callback is triggered. Typically, this is used to request an
/// in-app store review.
///
/// If the user gives a rating lower than 4 stars, the [onBadReview]
/// callback is triggered. This is generally used to collect feedback
/// via email and postpone future review prompts.
///
/// The dialog includes:
/// - A star rating bar (1–5 stars)
/// - An optional comment field (visible for ratings below 4)
/// - Continue button with rating display
/// - "Never Ask Again" and "Ask Me Later" actions
///
/// Use [CustomRatingDialog.show] to display the dialog.
class CustomRatingDialog extends StatefulWidget {
  final Function(double, String) onGoodReview;
  final Function(double, String) onBadReview;

  const CustomRatingDialog({
    Key? key,
    required this.onGoodReview,
    required this.onBadReview,
  }) : super(key: key);

  @override
  _CustomRatingDialogState createState() => _CustomRatingDialogState();

  /// Displays the [CustomRatingDialog].
  ///
  /// This method handles default behavior for good and bad reviews:
  ///
  /// - Good reviews (≥ 4 stars):
  ///   - Stops future prompts
  ///   - Triggers the in-app review request
  ///
  /// - Bad reviews (< 4 stars):
  ///   - Postpones the review prompt for 6 months
  ///   - Sends feedback via email
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => CustomRatingDialog(
        onGoodReview: (rating, comment) async {
          Navigator.pop(context);
          await ReviewService().neverAskAgain();
          await ReviewService().forceRequestReview();
        },
        onBadReview: (rating, comment) async {
          Navigator.pop(context);
          await ReviewService().postponeReview(const Duration(days: 180));
          await ReviewService().sendEmailFeedback(rating, comment);
        },
      ),
    );
  }
}

/// State class for [CustomRatingDialog].
///
/// Manages:
/// - The selected star rating value.
/// - The optional user feedback comment.
/// - Dynamic UI updates based on the selected rating.
///
/// Behavior:
/// - Displays a 5-star rating bar with a default rating of 5.
/// - Shows a comment input field only when the rating is less than 4 stars.
/// - Triggers:
///     • [widget.onGoodReview] when rating ≥ 4
///     • [widget.onBadReview] when rating < 4
/// - Provides footer actions:
///     • "Never Ask Again" to permanently disable future prompts.
///     • "Ask Me Later" to postpone the review request.
///
/// Properly disposes the [_commentController] to prevent memory leaks.
class _CustomRatingDialogState extends State<CustomRatingDialog> {
  static const Color _starColor = Color(0xFFF5B82E);

  int _rating = 3;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF8A8A8A);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'How’s your experience ?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 26,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your feedback helps us improve\nand serve you better.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: 17,
                height: 1.4,
                color: subtitleColor,
              ),
            ),
            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final filled = index < _rating;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _rating = index + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: _starColor,
                      size: 44,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  final rating = _rating.toDouble();
                  if (rating >= 4) {
                    widget.onGoodReview(rating, '');
                  } else {
                    widget.onBadReview(rating, '');
                  }
                },
                child: const Text(
                  'Submit',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextButton(
              onPressed: () async {
                await ReviewService().postponeReview(const Duration(days: 30));
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(
                'Skip for Now',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  color: titleColor.withOpacity(0.5),
                  decoration: TextDecoration.underline,
                  decorationColor: titleColor.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}