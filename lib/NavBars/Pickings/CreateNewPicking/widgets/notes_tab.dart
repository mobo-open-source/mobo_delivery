import 'package:flutter/material.dart';
import 'info_row.dart';

/// A simple tab content widget that displays an editable note field for a picking.
///
/// Intended to be used as one of the tabs in a `TabBarView` (e.g. in the picking creation form).
///
/// Features:
///   - Wraps a single `InfoRow` configured for note editing
///   - Uses `SingleChildScrollView` to handle keyboard overflow when typing long notes
///   - Applies consistent padding and layout
///
/// The note content is managed externally via the provided `TextEditingController`.
class NotesTab extends StatelessWidget {
  /// Controller that holds and manages the note text content.
  ///
  /// Passed from the parent widget (usually `CreatePickingPage`).
  /// Allows two-way binding between the text field and parent state.
  final TextEditingController noteController;

  const NotesTab({
    Key? key,
    required this.noteController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(
              label: "Note",
              value: null,
              isEditing: true,
              controller: noteController,
            ),
          ],
        ),
      ),
    );
  }
}