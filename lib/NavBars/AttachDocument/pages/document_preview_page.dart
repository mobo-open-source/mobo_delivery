import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/loaders/loading_widget.dart';
import '../services/odoo_attach_service.dart';

/// In-app preview for a single picking attachment.
///
/// Images and PDFs render natively; any other type is written to a temp file
/// and handed to the OS via [OpenFile]. The file content is downloaded lazily
/// (base64 `datas`) so the document list stays lightweight.
class DocumentPreviewPage extends StatefulWidget {
  final int attachmentId;
  final String name;
  final String mimetype;
  final OdooAttachService service;

  const DocumentPreviewPage({
    super.key,
    required this.attachmentId,
    required this.name,
    required this.mimetype,
    required this.service,
  });

  @override
  State<DocumentPreviewPage> createState() => _DocumentPreviewPageState();
}

class _DocumentPreviewPageState extends State<DocumentPreviewPage> {
  bool _loading = true;
  String? _error;
  Uint8List? _bytes;

  bool get _isImage =>
      widget.mimetype.startsWith('image/') ||
      RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false)
          .hasMatch(widget.name);

  bool get _isPdf =>
      widget.mimetype == 'application/pdf' ||
      widget.name.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final base64 = await widget.service.downloadAttachmentBytes(
      widget.attachmentId,
    );
    if (!mounted) return;
    if (base64 == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load this document. Please check your connection.';
      });
      return;
    }
    try {
      final bytes = base64Decode(base64);
      // Native preview only for images / PDFs; hand everything else to the OS.
      if (!_isImage && !_isPdf) {
        await _openExternally(bytes);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Opening "${widget.name}" in another app…';
        });
        return;
      }
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This document could not be opened.';
      });
    }
  }

  Future<void> _openExternally(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final safeName = widget.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[100],
      appBar: AppBar(
        forceMaterialTransparency: true,
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[100],
        title: Text(
          widget.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
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
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(
        child: LoadingWidget(
          size: 40,
          variant: LoadingVariant.staggeredDots,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                HugeIcons.strokeRoundedFile01,
                size: 64,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_bytes == null) return const SizedBox.shrink();

    if (_isPdf) {
      return PdfViewer.data(
        _bytes!,
        sourceName: widget.name,
      );
    }
    // Image.
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5,
      child: Center(
        child: Image.memory(
          _bytes!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Icon(
            HugeIcons.strokeRoundedImageNotFound01,
            size: 64,
            color: AppStyle.primaryColor,
          ),
        ),
      ),
    );
  }
}
