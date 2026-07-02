import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/navigation/data_loss_warning_dialog.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/dialogs/common_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loaders/delivery_shimmers.dart';
import '../../../shared/widgets/loading_overlay.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import '../models/pending_attachment.dart';
import '../screens/signature_screen.dart';
import '../services/odoo_attach_service.dart';
import '../utils/utils.dart';
import 'document_preview_page.dart';

/// Shows every document attached to a single picking, lets the user open one
/// in an in-app preview, and add new documents (signature / file upload).
///
/// Uploading reuses the same online/offline behaviour as the documents tab:
/// online → `ir.attachment.create`; offline → queued in Hive for later sync.
class PickingDocumentsPage extends StatefulWidget {
  final Map<String, dynamic> picking;

  const PickingDocumentsPage({super.key, required this.picking});

  @override
  State<PickingDocumentsPage> createState() => _PickingDocumentsPageState();
}

class _PickingDocumentsPageState extends State<PickingDocumentsPage> {
  final OdooAttachService _service = OdooAttachService();

  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _attachments = [];

  // Docs staged locally — not yet pushed to Odoo. Each entry:
  // { 'mimeType': String, 'base64File': String, 'fileName': String }
  final List<Map<String, dynamic>> _pendingUploads = [];

  // Lazy-loaded thumbnail bytes keyed by attachment id (saved items only).
  final Map<int, Uint8List?> _thumbnailCache = {};

  bool get _hasUnsavedChanges => _pendingUploads.isNotEmpty;

  int get _pickingId =>
      int.tryParse(widget.picking['id']?.toString() ?? '') ?? 0;

  String get _pickingName =>
      (widget.picking['name'] ?? widget.picking['item'] ?? 'Picking')
          .toString();

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    setState(() => _loading = true);
    final list = await _service.fetchPickingAttachments(_pickingId);
    if (!mounted) return;
    setState(() {
      _attachments = list;
      _loading = false;
    });
  }

  // ── Stage locally (shown in UI, not yet sent to Odoo) ─────────────────────
  void _stageDocument(String mimeType, String base64File, String fileName) {
    setState(() {
      _pendingUploads.add({
        'mimeType': mimeType,
        'base64File': base64File,
        'fileName': fileName,
      });
    });
  }

  // ── Save: push all pending docs to Odoo (or Hive if offline) ──────────────
  Future<void> _saveAll() async {
    if (_pendingUploads.isEmpty) return;
    setState(() => _busy = true);
    try {
      final online = await _service.checkNetworkConnectivity();
      final toUpload = List<Map<String, dynamic>>.from(_pendingUploads);
      bool anyFailed = false;

      for (final p in toUpload) {
        if (!online) {
          await HiveService().savePendingAttachment(
            PendingAttachment(
              pickingId: _pickingId,
              mimeType: p['mimeType'],
              base64File: p['base64File'],
              fileName: p['fileName'],
            ),
          );
        } else {
          final ok = await _service.uploadFileToChatter(
            p['mimeType'],
            p['base64File'],
            _pickingId,
            p['fileName'],
          );
          if (!ok) anyFailed = true;
        }
      }

      if (!mounted) return;
      setState(() => _pendingUploads.clear());

      if (!online) {
        CustomSnackbar.showWarning(
          context,
          'Saved offline — will upload when back online.',
        );
      } else if (anyFailed) {
        CustomSnackbar.showError(context, 'Some documents failed to upload.');
        await _loadAttachments();
      } else {
        CustomSnackbar.showSuccess(context, 'Documents saved.');
        await _loadAttachments();
      }
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile(List<String> allowedExtensions) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final fileName = result.files.single.name;
        _stageDocument(Utils.getMimeType(fileName), base64Encode(fileBytes), fileName);
      }
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Something went wrong. Try again.');
      }
    }
  }

  Future<void> _addSignature() async {
    final result = await SignatureDialog.show(context);
    if (result != null) {
      _stageDocument(result['mimeType'], result['base64'], result['fileName']);
    }
  }

  // ── Back guard: warn if there are staged (unsaved) docs ───────────────────
  Future<void> _handleBackPress() async {
    if (!_hasUnsavedChanges) {
      Navigator.pop(context);
      return;
    }
    final shouldLeave = await DataLossWarningDialog.show(
      context: context,
      title: 'Discard Documents?',
      message: 'You have unsaved documents that haven\'t been uploaded yet. They will be lost if you leave.',
      confirmText: 'Discard',
      cancelText: 'Keep Editing',
    );
    if (shouldLeave == true && mounted) {
      Navigator.pop(context);
    }
  }

  void _showAddOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        Widget tile(IconData icon, String label, VoidCallback onTap) =>
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(
                icon,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
                size: 22,
              ),
              title: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                onTap();
              },
            );
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                tile(HugeIcons.strokeRoundedSignature, 'Signature', _addSignature),
                tile(HugeIcons.strokeRoundedUploadSquare02, 'Upload Image or PDF',
                    () => _pickFile(['jpg', 'jpeg', 'png', 'pdf'])),
                tile(HugeIcons.strokeRoundedLink01, 'Attach Document',
                    () => _pickFile(['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'])),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteAttachment(Map<String, dynamic> attachment) async {
    final id = int.tryParse(attachment['id']?.toString() ?? '');
    final name = (attachment['name'] ?? 'this document').toString();
    if (id == null) return;

    final confirmed = await CommonDialog.confirm(
      context,
      title: 'Delete Document?',
      message:
          'Are you sure you want to delete "$name"? This action cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await _service.deleteAttachment(id);
    if (!mounted) return;
    if (ok) {
      _thumbnailCache.remove(id);
      CustomSnackbar.showSuccess(context, 'Document deleted.');
      await _loadAttachments();
    } else {
      CustomSnackbar.showError(context, 'Failed to delete document.');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _showPendingOptions({
    required Map<String, dynamic> p,
    required String fileName,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : Colors.grey[500],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() => _pendingUploads.remove(p));
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          forceMaterialTransparency: true,
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          title: Text(
            _pickingName,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22,
            ),
          ),
          leading: IconButton(
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
              size: 28,
            ),
            onPressed: _handleBackPress,
          ),
          actions: [
            if (_hasUnsavedChanges)
              TextButton(
                onPressed: _busy ? null : _saveAll,
                child: Text(
                  'Save',
                  style: TextStyle(
                    color: AppStyle.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: Stack(
          children: [_buildBody(isDark), if (_busy) const LoadingOverlay()],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return PickingDocumentPageShimmer(isDark: isDark);
    }
    return RefreshIndicator(
      onRefresh: _loadAttachments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _summaryCard(isDark),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Documents (${_attachments.length + _pendingUploads.length})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (_attachments.isEmpty && _pendingUploads.isEmpty)
            _noDocsCard(isDark)
          else ...[
            for (final a in _attachments) ...[
              _attachmentCard(a, isDark),
              const SizedBox(height: 16),
            ],
            for (final p in _pendingUploads) ...[
              _pendingCard(p, isDark),
              const SizedBox(height: 16),
            ],
            _addDocumentCard(),
          ],
        ],
      ),
    );
  }

  /// Top summary card — gives the page context (status, schedule, source) so it
  /// doesn't look empty when a picking has only a document or two.
  Widget _summaryCard(bool isDark) {
    final state = (widget.picking['state'] ?? '').toString();
    final (statusLabel, statusColor) = _statusInfo(state);
    final scheduled = _formatDate(widget.picking['scheduled_date']);
    final origin = widget.picking['origin'];
    final hasOrigin = origin != null &&
        origin != false &&
        origin.toString().isNotEmpty &&
        origin.toString() != 'false';

    Widget infoRow(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _pickingName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              if (statusLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: isDark
                        ? Border.all(color: statusColor.withValues(alpha: 0.35), width: 0.8)
                        : null,
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? statusColor.withValues(alpha: 0.95) : statusColor,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
            ],
          ),
          if (scheduled != null)
            infoRow(HugeIcons.strokeRoundedCalendar03, 'Scheduled: $scheduled'),
          if (hasOrigin)
            infoRow(HugeIcons.strokeRoundedFile02, 'Source: $origin'),
        ],
      ),
    );
  }

  (String, Color) _statusInfo(String state) {
    switch (state) {
      case 'done':
        return ('Done', const Color(0xFF00A63E));
      case 'cancel':
        return ('Cancelled', const Color(0xFFEF4444));
      case 'assigned':
        return ('Ready', const Color(0xFF3B82F6));
      case 'confirmed':
      case 'waiting':
        return ('Waiting', const Color(0xFFF97316));
      case 'draft':
        return ('Draft', const Color(0xFF6B7280));
      default:
        return (state, const Color(0xFF6B7280));
    }
  }

  Widget _noDocsCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            HugeIcons.strokeRoundedFile01,
            size: 40,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            'No documents yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Attach a signature, image, or PDF to this picking.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _showAddOptions,
            icon: Icon(
              HugeIcons.strokeRoundedAdd01,
              size: 16,
              color: AppStyle.primaryColor,
            ),
            label: Text(
              'Add Document',
              style: TextStyle(
                color: AppStyle.primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppStyle.primaryColor,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// Inline filled "Add Document" CTA at the end of the list — primary color
  /// to match the app's in-app actions (black is reserved for the login flow).
  Widget _addDocumentCard() {
    return Material(
      color: AppStyle.primaryColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : _showAddOptions,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(HugeIcons.strokeRoundedAdd01, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Add Document',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> p, bool isDark) {
    final fileName = p['fileName'] as String;
    final mimeType = p['mimeType'] as String;
    final isImg = _isImage(mimeType, fileName);

    Widget thumbnail;
    if (isImg) {
      try {
        final raw = p['base64File'] as String;
        final clean = raw.contains(',') ? raw.split(',')[1] : raw;
        final bytes = base64Decode(clean);
        thumbnail = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover),
        );
      } catch (_) {
        thumbnail = _iconBox(mimeType, fileName, isDark);
      }
    } else {
      thumbnail = _iconBox(mimeType, fileName, isDark);
    }

    return GestureDetector(
      onLongPress: () => _showPendingOptions(p: p, fileName: fileName, isDark: isDark),
      child: Material(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              thumbnail,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showPendingOptions(p: p, fileName: fileName, isDark: isDark),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentCard(Map<String, dynamic> a, bool isDark) {
    final name = (a['name'] ?? 'Document').toString();
    final mimetype = (a['mimetype'] ?? '').toString();
    final size = _formatSize(a['file_size']);
    final date = _formatDate(a['create_date']);

    return Material(
      color: isDark ? Colors.grey[850] : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final id = int.tryParse(a['id']?.toString() ?? '');
          if (id == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DocumentPreviewPage(
                attachmentId: id,
                name: name,
                mimetype: mimetype,
                service: _service,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _savedThumbnail(a, mimetype, name, isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (size != null) size,
                        if (date != null) date,
                      ].join('  •  '),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _confirmDeleteAttachment(a),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                splashRadius: 20,
                icon: Icon(
                  HugeIcons.strokeRoundedDelete02,
                  size: 20,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
                tooltip: 'Delete document',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBox(String mimetype, String name, bool isDark) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_iconFor(mimetype, name), color: AppStyle.primaryColor, size: 22),
    );
  }

  Widget _savedThumbnail(
    Map<String, dynamic> a,
    String mimetype,
    String name,
    bool isDark,
  ) {
    final id = int.tryParse(a['id']?.toString() ?? '');
    if (id == null || !_isImage(mimetype, name)) {
      return _iconBox(mimetype, name, isDark);
    }
    // Already cached
    if (_thumbnailCache.containsKey(id)) {
      final bytes = _thumbnailCache[id];
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover),
        );
      }
      return _iconBox(mimetype, name, isDark);
    }
    // Trigger load (setState inside _loadThumbnail triggers rebuild with cached value)
    _loadThumbnail(id);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
    );
  }

  bool _isImage(String mimetype, String name) {
    return mimetype.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|gif|webp|bmp)$').hasMatch(name.toLowerCase());
  }

  Future<Uint8List?> _loadThumbnail(int id) async {
    if (_thumbnailCache.containsKey(id)) return _thumbnailCache[id];
    final b64 = await _service.downloadAttachmentBytes(id);
    Uint8List? bytes;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final clean = b64.contains(',') ? b64.split(',')[1] : b64;
        bytes = base64Decode(clean);
      } catch (_) {}
    }
    if (mounted) setState(() => _thumbnailCache[id] = bytes);
    return bytes;
  }

  IconData _iconFor(String mimetype, String name) {
    final lower = name.toLowerCase();
    if (mimetype.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|gif|webp|bmp)$').hasMatch(lower)) {
      return HugeIcons.strokeRoundedImage01;
    }
    if (mimetype == 'application/pdf' || lower.endsWith('.pdf')) {
      return HugeIcons.strokeRoundedPdf01;
    }
    return HugeIcons.strokeRoundedFile01;
  }

  String? _formatSize(dynamic raw) {
    final bytes = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '');
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String? _formatDate(dynamic raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty || s == 'false') return null;
    // Odoo datetime "2026-05-27 11:40:47" → show the date part.
    return s.split(' ').first;
  }
}
