import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:odoo_delivery_app/Rating/review_service.dart';

import '../shared/utils/globals.dart';
import '../shared/widgets/buttons/mobo_button.dart';

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
  double _rating = 5.0;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppStyle.primaryColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.stars_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                children: [
                  Text(
                    'Rate Us',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tell others what you think about this app',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: primaryColor.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        RatingBar.builder(
                          initialRating: 5,
                          minRating: 1,
                          direction: Axis.horizontal,
                          allowHalfRating: false,
                          itemCount: 5,
                          itemPadding: const EdgeInsets.symmetric(horizontal: 2.0),
                          unratedColor: Colors.grey[300],
                          itemSize: 34,
                          itemBuilder: (context, _) => const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                          ),
                          onRatingUpdate: (rating) {
                            setState(() {
                              _rating = rating;
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        MoboButton.primary(
                          label: '${_rating.toInt()}/5  CONTINUE',
                          height: 55,
                          borderRadius: 4,
                          onPressed: () {
                            if (_rating >= 4) {
                              widget.onGoodReview(_rating, _commentController.text);
                            } else {
                              widget.onBadReview(_rating, _commentController.text);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Visibility(
                    visible: _rating < 4,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: _commentController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Any comments or feedback? (Optional)',
                          hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: primaryColor),
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.black12 : Colors.grey[50],
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () async {
                      await ReviewService().neverAskAgain();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'NEVER ASK AGAIN',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: primaryColor.withOpacity(0.6),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ReviewService().postponeReview(const Duration(days: 30));
                      Navigator.pop(context);
                    },
                    child: Text(
                      'ASK ME LATER',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: primaryColor.withOpacity(0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}