import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Color _base(bool isDark) =>
    isDark ? const Color(0xFF2A2A2A) : Colors.grey[300]!;
Color _highlight(bool isDark) =>
    isDark ? const Color(0xFF3A3A3A) : Colors.grey[100]!;
Color _cardBg(bool isDark) =>
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

Widget _box({
  required bool isDark,
  required double height,
  double? width,
  double radius = 6,
}) =>
    Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: _base(isDark),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

// ---------------------------------------------------------------------------
// Picking List Shimmer  (mirrors _buildPickingCard)
// ---------------------------------------------------------------------------

class PickingCardShimmer extends StatelessWidget {
  const PickingCardShimmer({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _base(isDark),
      highlightColor: _highlight(isDark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // reference + status badge
              Row(
                children: [
                  Expanded(child: _box(isDark: isDark, height: 14, width: 160)),
                  const SizedBox(width: 12),
                  _box(isDark: isDark, height: 24, width: 72, radius: 12),
                ],
              ),
              const SizedBox(height: 10),
              // Origin row
              Row(children: [
                _box(isDark: isDark, height: 12, width: 52),
                const SizedBox(width: 12),
                Expanded(child: _box(isDark: isDark, height: 12, width: 180)),
              ]),
              const SizedBox(height: 6),
              // Partner row
              Row(children: [
                _box(isDark: isDark, height: 12, width: 52),
                const SizedBox(width: 12),
                Expanded(child: _box(isDark: isDark, height: 12, width: 140)),
              ]),
              const SizedBox(height: 6),
              // Scheduled date row (icon + text)
              Row(children: [
                _box(isDark: isDark, height: 14, width: 14, radius: 3),
                const SizedBox(width: 6),
                Expanded(child: _box(isDark: isDark, height: 12, width: 120)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class PickingListShimmer extends StatelessWidget {
  const PickingListShimmer({super.key, this.itemCount = 6});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: itemCount,
      itemBuilder: (_, __) => PickingCardShimmer(isDark: isDark),
    );
  }
}

// ---------------------------------------------------------------------------
// Pagination Bar Shimmer  (mirrors the range-pill + chevron row above lists)
// ---------------------------------------------------------------------------

class PaginationBarShimmer extends StatelessWidget {
  const PaginationBarShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: _base(isDark),
      highlightColor: _highlight(isDark),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // filter chip placeholder
            _box(isDark: isDark, height: 28, width: 80, radius: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // range pill placeholder
                _box(isDark: isDark, height: 28, width: 80, radius: 20),
                const SizedBox(width: 4),
                // prev / next icon placeholders
                _box(isDark: isDark, height: 24, width: 24, radius: 12),
                const SizedBox(width: 4),
                _box(isDark: isDark, height: 24, width: 24, radius: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Return Management Shimmer  (mirrors _buildReturnTile)
// ---------------------------------------------------------------------------

class ReturnCardShimmer extends StatelessWidget {
  const ReturnCardShimmer({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _base(isDark),
      highlightColor: _highlight(isDark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // reference + optional "Return" badge + status badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(children: [
                      _box(isDark: isDark, height: 14, width: 140),
                      const SizedBox(width: 8),
                      _box(isDark: isDark, height: 20, width: 52, radius: 4),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  _box(isDark: isDark, height: 24, width: 72, radius: 12),
                ],
              ),
              const SizedBox(height: 10),
              // Return of
              Row(children: [
                _box(isDark: isDark, height: 12, width: 66),
                const SizedBox(width: 12),
                Expanded(child: _box(isDark: isDark, height: 12, width: 160)),
              ]),
              const SizedBox(height: 6),
              // Scheduled
              Row(children: [
                _box(isDark: isDark, height: 12, width: 66),
                const SizedBox(width: 12),
                Expanded(child: _box(isDark: isDark, height: 12, width: 110)),
              ]),
              const SizedBox(height: 6),
              // Partner
              Row(children: [
                _box(isDark: isDark, height: 12, width: 66),
                const SizedBox(width: 12),
                Expanded(child: _box(isDark: isDark, height: 12, width: 140)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class ReturnListShimmer extends StatelessWidget {
  const ReturnListShimmer({super.key, this.itemCount = 6});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: itemCount,
      itemBuilder: (_, __) => ReturnCardShimmer(isDark: isDark),
    );
  }
}

// ---------------------------------------------------------------------------
// Attach Documents List Shimmer  (mirrors _buildAttachmentTile — ListTile)
// ---------------------------------------------------------------------------

class AttachmentPickingCardShimmer extends StatelessWidget {
  const AttachmentPickingCardShimmer({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _base(isDark),
      highlightColor: _highlight(isDark),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(isDark: isDark, height: 14, width: 160),
                    const SizedBox(height: 8),
                    _box(isDark: isDark, height: 12, width: 120),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _box(isDark: isDark, height: 24, width: 72, radius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class AttachmentPickingListShimmer extends StatelessWidget {
  const AttachmentPickingListShimmer({super.key, this.itemCount = 8});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (_, __) => AttachmentPickingCardShimmer(isDark: isDark),
    );
  }
}

// ---------------------------------------------------------------------------
// Picking Documents Page Shimmer
// (mirrors summary card + _attachmentCard items)
// ---------------------------------------------------------------------------

class PickingDocumentPageShimmer extends StatelessWidget {
  const PickingDocumentPageShimmer({super.key, required this.isDark});
  final bool isDark;

  Widget _summaryCardShimmer() {
    return Shimmer.fromColors(
      baseColor: _base(isDark),
      highlightColor: _highlight(isDark),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: _box(isDark: isDark, height: 16, width: 180)),
              const SizedBox(width: 12),
              _box(isDark: isDark, height: 24, width: 72, radius: 12),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _box(isDark: isDark, height: 14, width: 14, radius: 3),
              const SizedBox(width: 8),
              Expanded(child: _box(isDark: isDark, height: 12, width: 120)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _box(isDark: isDark, height: 14, width: 14, radius: 3),
              const SizedBox(width: 8),
              Expanded(child: _box(isDark: isDark, height: 12, width: 100)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _documentItemShimmer() {
    return Shimmer.fromColors(
      baseColor: _base(isDark),
      highlightColor: _highlight(isDark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // file type icon placeholder
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _base(isDark),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(isDark: isDark, height: 14),
                    const SizedBox(height: 6),
                    _box(isDark: isDark, height: 11, width: 100),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _box(isDark: isDark, height: 16, width: 16, radius: 3),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _summaryCardShimmer(),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: _box(isDark: isDark, height: 14, width: 110),
        ),
        _documentItemShimmer(),
        _documentItemShimmer(),
        _documentItemShimmer(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Picking Detail Page Shimmer  (mirrors header card + delivery details + tabs + product rows)
// ---------------------------------------------------------------------------

class PickingDetailShimmer extends StatelessWidget {
  const PickingDetailShimmer({super.key, required this.isDark});
  final bool isDark;

  Widget _card({required List<Widget> children}) {
    return Shimmer.fromColors(
      baseColor: _base(isDark),
      highlightColor: _highlight(isDark),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  // Mirrors InfoRow view mode: Padding(vertical:8) > Row(label | Spacer | value)
  Widget _infoRow(double labelWidth, double valueWidth) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _box(isDark: isDark, height: 13, width: labelWidth),
          const Spacer(),
          _box(isDark: isDark, height: 13, width: valueWidth),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header card: reference (20sp bold) + status badge, partner, address, date row
          _card(children: [
            Row(children: [
              Expanded(child: _box(isDark: isDark, height: 20, width: 180)),
              const SizedBox(width: 12),
              _box(isDark: isDark, height: 26, width: 72, radius: 13),
            ]),
            const SizedBox(height: 10),
            _box(isDark: isDark, height: 14, width: 200), // partner name 15sp
            const SizedBox(height: 4),
            _box(isDark: isDark, height: 12, width: 160), // address 13sp
            const SizedBox(height: 10),
            Row(children: [
              _box(isDark: isDark, height: 13, width: 13, radius: 3), // calendar icon
              const SizedBox(width: 6),
              _box(isDark: isDark, height: 12, width: 110), // scheduled date 13sp
            ]),
          ]),
          const SizedBox(height: 16),
          // Delivery Details card: title + InfoRow-style text rows (no grey containers)
          _card(children: [
            _box(isDark: isDark, height: 18, width: 140), // "Delivery Details" 18sp
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _infoRow(110, 140), // Delivery Address
                  _infoRow(100, 100), // Operation Type
                  _infoRow(100, 110), // Scheduled Date
                  _infoRow(110, 120), // Source Document
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          // Tab pills row (height:40, 3 pills: Operations / Additional Info / Note)
          Shimmer.fromColors(
            baseColor: _base(isDark),
            highlightColor: _highlight(isDark),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  _box(isDark: isDark, height: 36, width: 96, radius: 18),
                  const SizedBox(width: 8),
                  _box(isDark: isDark, height: 36, width: 116, radius: 18),
                  const SizedBox(width: 8),
                  _box(isDark: isDark, height: 36, width: 52, radius: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Tab content container (radius:16, minHeight:240) — 3 product rows
          _card(children: [
            for (int i = 0; i < 3; i++) ...[
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _base(isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _box(isDark: isDark, height: 14)),
                const SizedBox(width: 12),
                _box(isDark: isDark, height: 14, width: 48),
              ]),
              if (i < 2) const SizedBox(height: 12),
            ],
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard Shimmer (mirrors the app scaffold: AppBar + content + BottomNav)
// ---------------------------------------------------------------------------

class DashboardShimmer extends StatelessWidget {
  const DashboardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // AppBar placeholder
            Shimmer.fromColors(
              baseColor: _base(isDark),
              highlightColor: _highlight(isDark),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  _box(isDark: isDark, height: 22, width: 160),
                  const Spacer(),
                  _box(isDark: isDark, height: 32, width: 32, radius: 8),
                  const SizedBox(width: 10),
                  _box(isDark: isDark, height: 32, width: 32, radius: 8),
                ]),
              ),
            ),
            // Search / filter bar placeholder
            Shimmer.fromColors(
              baseColor: _base(isDark),
              highlightColor: _highlight(isDark),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _box(isDark: isDark, height: 44, radius: 12),
              ),
            ),
            // List of card placeholders
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 6,
                  itemBuilder: (_, __) => PickingCardShimmer(isDark: isDark),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Shimmer.fromColors(
        baseColor: _base(isDark),
        highlightColor: _highlight(isDark),
        child: Container(
          height: 64,
          color: _cardBg(isDark),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              5,
              (_) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _box(isDark: isDark, height: 24, width: 24, radius: 6),
                  const SizedBox(height: 4),
                  _box(isDark: isDark, height: 10, width: 40, radius: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
