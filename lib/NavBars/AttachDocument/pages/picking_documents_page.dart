import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/utils/globals.dart';
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

  // ── Upload (online → Odoo, offline → Hive queue) ──────────────────────────
  Future<void> _upload(
    String mimeType,
    String base64File,
    String fileName,
  ) async {
    setState(() => _busy = true);
    try {
      final online = await _service.checkNetworkConnectivity();
      if (!online) {
        await HiveService().savePendingAttachment(
          PendingAttachment(
            pickingId: _pickingId,
            mimeType: mimeType,
            base64File: base64File,
            fileName: fileName,
          ),
        );
        if (!mounted) return;
        CustomSnackbar.showWarning(
          context,
          'Saved offline — will upload when back online.',
        );
      } else {
        final ok = await _service.uploadFileToChatter(
          mimeType,
          base64File,
          _pickingId,
          fileName,
        );
        if (!mounted) return;
        if (ok) {
          CustomSnackbar.showSuccess(context, 'Document added.');
          await _loadAttachments();
        } else {
          CustomSnackbar.showError(context, 'Failed to add document.');
        }
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
        await _upload(
          Utils.getMimeType(fileName),
          base64Encode(fileBytes),
          fileName,
        );
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
      await _upload(result['mimeType'], result['base64'], result['fileName']);
    }
  }

  void _showAddOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        Widget tile(IconData icon, String label, VoidCallback onTap) =>
            ListTile(
              leading: Icon(
                icon,
                color: isDark ? Colors.white : Colors.black87,
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
          child: Wrap(
            children: [
              tile(
                HugeIcons.strokeRoundedSignature,
                'Signature',
                _addSignature,
              ),
              tile(
                HugeIcons.strokeRoundedUploadSquare02,
                'Upload Image or PDF',
                () => _pickFile(['jpg', 'jpeg', 'png', 'pdf']),
              ),
              tile(
                HugeIcons.strokeRoundedLink01,
                'Attach Document',
                () => _pickFile(['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt']),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
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
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [_buildBody(isDark), if (_busy) const LoadingOverlay()],
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
              'Documents (${_attachments.length})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (_attachments.isEmpty)
            _noDocsCard(isDark)
          else ...[
            for (final a in _attachments) ...[
              _attachmentCard(a, isDark),
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
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
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
        return ('Done', const Color(0xFF2E7D32));
      case 'cancel':
        return ('Cancelled', const Color(0xFFC62828));
      case 'assigned':
        return ('Ready', const Color(0xFF1565C0));
      case 'confirmed':
      case 'waiting':
        return ('Waiting', const Color(0xFFE08600));
      case 'draft':
        return ('Draft', Colors.grey);
      default:
        return (state, Colors.grey);
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
                color: AppStyle.primaryColor.withValues(alpha: 0.5),
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppStyle.primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconFor(mimetype, name),
                  color: AppStyle.primaryColor,
                  size: 22,
                ),
              ),
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
              Icon(
                HugeIcons.strokeRoundedArrowRight01,
                color: isDark ? Colors.grey[500] : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
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
