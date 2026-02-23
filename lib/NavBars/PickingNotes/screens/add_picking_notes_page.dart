import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_delivery_app/NavBars/PickingNotes/screens/picking_notes_page.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/motion_provider.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../constants/constants.dart';
import '../services/odoo_picking_note_service.dart';

/// Screen for adding or editing internal notes on a stock picking (transfer/receipt/delivery).
///
/// Allows the user to:
///   - Select a picking from a searchable dropdown (fetched from Odoo)
///   - View existing note (if any) and edit/add new content
///   - Save the note via Odoo RPC (`stock.picking.write`)
///   - Shows success/error feedback and refreshes picking list
///
/// Supports dark/light theme, motion reduction, form validation, and analytics tracking.
class AddPickingNotesPage extends StatefulWidget {
  const AddPickingNotesPage({super.key});

  @override
  State<AddPickingNotesPage> createState() => _AddPickingNotesPageState();
}

/// Manages state and business logic for adding/editing picking notes.
///
/// Responsibilities:
///   - Fetches available stock pickings from Odoo
///   - Loads existing note when a picking is selected
///   - Validates input and saves note to Odoo
///   - Tracks changes to enable/disable save button
///   - Handles navigation back to picking notes list with smooth transition
class _AddPickingNotesPageState extends State<AddPickingNotesPage> {
  final OdooPickingNoteService _odooService = OdooPickingNoteService();
  final TextEditingController _noteController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> pickings = [];
  int? selectedPicking;
  String? selectedPickingName;
  bool _isNoteSaved = false;
  String _originalNote = '';
  bool _shouldValidate = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    _noteController.removeListener(_onNoteChanged);
    _noteController.dispose();
    super.dispose();
  }

  /// Initializes Odoo client and fetches initial list of stock pickings.
  Future<void> _initialize() async {
    await _odooService.initializeClient();
    await _fetchStockPickings();
  }

  /// Loads paginated stock pickings from Odoo (limit 100 for now).
  ///
  /// Updates `pickings` list and triggers rebuild.
  Future<void> _fetchStockPickings() async {
    final newPickings = await _odooService.fetchStockPickings(0, 100);
    setState(() {
      pickings = newPickings;
    });
  }

  /// Listener for note text changes.
  ///
  /// Updates `_isNoteSaved` flag based on whether content differs from original.
  /// Clears validation error when user starts typing.
  void _onNoteChanged() {
    final currentText = _noteController.text.trim();
    final hasChanged = currentText != _originalNote.trim();
    if (_shouldValidate && currentText.isNotEmpty) {
      setState(() => _shouldValidate = false);
    }
    if (_isNoteSaved == hasChanged) {
      setState(() => _isNoteSaved = !hasChanged);
    }
  }

  /// Validates form and saves the note to the selected picking in Odoo.
  ///
  /// Flow:
  ///   1. Form validation (picking selected + note not empty)
  ///   2. Calls Odoo service to write note
  ///   3. On success:
  ///      - Updates original note & saved flag
  ///      - Refreshes picking list (to show updated note)
  ///      - Shows success snackbar
  ///      - Tracks analytics event
  ///   4. On failure: shows error snackbar
  Future<void> _saveNote() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _shouldValidate = true);
      return;
    }
    if (_noteController.text.trim().isEmpty) {
      setState(() => _shouldValidate = true);
      return;
    }

    final success = await _odooService.saveNote(
      selectedPicking!,
      _noteController.text.trim(),
    );
    if (success) {
      setState(() {
        _originalNote = _noteController.text.trim();
        _isNoteSaved = true;
      });
      await _fetchStockPickings();
      CustomSnackbar.showSuccess(
        context,
        'Note added successfully to $selectedPickingName',
      );
    } else {
      CustomSnackbar.showError(
        context,
        'Failed to save note. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        title: Text(
          'Log Picking Note',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
            size: 28,
          ),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const PickingNotesPage(),
                transitionDuration: motionProvider.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                reverseTransitionDuration: motionProvider.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      if (motionProvider.reduceMotion) return child;
                      return FadeTransition(opacity: animation, child: child);
                    },
              ),
            );
          },
        ),
      ),
      body: pickings.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[850] : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withOpacity(0.18)
                            : Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Picking',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownSearch<Map<String, dynamic>>(
                          popupProps: PopupProps.menu(
                            showSearchBox: true,
                            searchFieldProps: TextFieldProps(
                              decoration: InputDecoration(
                                labelText: 'Search Pickings',
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black87,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          items: pickings,
                          itemAsString: (item) => item['name'] ?? '',
                          selectedItem: selectedPicking == null
                              ? null
                              : pickings.firstWhere(
                                  (element) => element['id'] == selectedPicking,
                                  orElse: () => {},
                                ),
                          onChanged: (value) {
                            setState(() {
                              selectedPicking = value?['id'];
                              selectedPickingName = value?['name'];
                              final rawNote = value?['note'];
                              final cleanedNote = (rawNote is String)
                                  ? rawNote.replaceAll(RegExp(r'<[^>]*>'), '')
                                  : '';
                              _noteController.text = cleanedNote;
                              _originalNote = cleanedNote;
                              _isNoteSaved = true;
                              _shouldValidate = false;
                            });
                          },
                          dropdownDecoratorProps: DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              hintText: 'Select Picking',
                              hintStyle: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: isDark ? Colors.white60 : Colors.black87,
                              ),
                              prefixIcon: Icon(
                                HugeIcons.strokeRoundedPackageDelivered,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[500],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white
                                      : AppStyle.primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null ? 'Please select a picking' : null,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Add Note',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _noteController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            hintText: 'Write your note here...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : AppStyle.primaryColor.withOpacity(0.2),
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white
                                    : AppStyle.primaryColor,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              _shouldValidate &&
                                  (value == null || value.trim().isEmpty)
                              ? 'Note cannot be empty'
                              : null,
                        ),
                        if (_shouldValidate) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Note cannot be empty',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              backgroundColor: isDark
                                  ? Colors.white
                                  : AppConstants.appBarColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed:
                                (selectedPicking != null && !_isNoteSaved)
                                ? _saveNote
                                : null,
                            icon: Icon(
                              HugeIcons.strokeRoundedCollectionsBookmark,
                              color: isDark ? Colors.black : Colors.white,
                            ),
                            label: Text(
                              'Save Note',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
