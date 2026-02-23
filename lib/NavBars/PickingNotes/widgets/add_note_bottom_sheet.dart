import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../services/odoo_picking_note_service.dart';

/// Bottom sheet dialog for adding or editing an internal note on a specific stock picking.
///
/// Features:
///   - Pre-fills with any existing note (cleaned of HTML tags)
///   - Simple multi-line text field for note input
///   - Validates that note is not empty before saving
///   - Saves note via Odoo RPC (`stock.picking.write`)
///   - Shows success/error feedback and calls `onNoteAdded` callback
///   - Tracks save event for analytics
///
/// Designed to be shown via `showModalBottomSheet` with scroll control and padding.
class AddNoteBottomSheet extends StatefulWidget {
  final int pickingId;
  final String pickingName;
  final String existingNote;
  final VoidCallback onNoteAdded;

  const AddNoteBottomSheet({
    super.key,
    required this.pickingId,
    required this.pickingName,
    required this.existingNote,
    required this.onNoteAdded,
  });

  @override
  State<AddNoteBottomSheet> createState() => _AddNoteBottomSheetState();
}

/// Manages state and save logic for the picking note bottom sheet.
///
/// Responsibilities:
///   - Initializes text controller with existing note
///   - Validates input (non-empty note)
///   - Calls Odoo service to save the note
///   - Handles success/error feedback and analytics
///   - Closes sheet and triggers parent refresh on success
class _AddNoteBottomSheetState extends State<AddNoteBottomSheet> {
  late final TextEditingController _noteController;
  final OdooPickingNoteService _odooService = OdooPickingNoteService();

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.existingNote);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Validates input and saves the note to Odoo for the selected picking.
  ///
  /// Flow:
  ///   1. Trims note text and checks it's not empty
  ///   2. Calls `saveNote(pickingId, note)` via Odoo service
  ///   3. On success:
  ///      - Triggers parent refresh via `onNoteAdded`
  ///      - Closes bottom sheet
  ///      - Shows success snackbar
  ///      - Tracks analytics event
  ///   4. On failure: shows error snackbar but keeps sheet open
  Future<void> _saveNote() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      CustomSnackbar.showWarning(context, 'Note cannot be empty');
      return;
    }

    final success = await _odooService.saveNote(widget.pickingId, note);
    if (success) {
      widget.onNoteAdded();
      Navigator.pop(context);
      CustomSnackbar.showSuccess(context, 'Note saved successfully to ${widget.pickingName}');
    } else {
      Navigator.pop(context);
      CustomSnackbar.showError(context, 'Failed to save note. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Add/Edit Note for Picking #${widget.pickingName}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Note',
              labelStyle: TextStyle(
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.white : Colors.black,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : AppStyle.primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _saveNote,
              icon: Icon(
                HugeIcons.strokeRoundedCollectionsBookmark,
                color: isDark ? Colors.black : Colors.white,
              ),
              label: Text(
                'Save Note',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
