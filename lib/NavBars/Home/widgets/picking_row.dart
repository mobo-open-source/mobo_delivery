import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/theme/mobo_home_theme.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/loaders/shimmer_skeleton.dart';
import '../models/home_attention_row.dart';
import 'status_chip.dart';

/// One row of the "Needs attention" list.
///
/// Uses the same visual language as the Pickings / Return / Documents list
/// tiles across the app: white surface, no hairline border, soft drop shadow,
/// 12px radius, `EdgeInsets.all(18)` padding, `Colors.grey[850]` in dark mode.
/// Reference (maroon, 15/w600) on the left with the [StatusChip] on the
/// right; partner and scheduled line underneath. No trailing chevron — the
/// InkWell ripple already communicates tappability, and the Pickings tiles
/// don't ship one either.
class PickingRow extends StatelessWidget {
  final HomeAttentionRow row;
  final VoidCallback onTap;

  const PickingRow({super.key, required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(12);

    return _TileShell(
      radius: radius,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  row.reference,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: AppStyle.accentOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                kind: row.isLate
                    ? StatusChipKind.late_
                    : row.state == 'assigned'
                    ? StatusChipKind.ready
                    : StatusChipKind.waiting,
                label: row.statusLabel,
              ),
            ],
          ),
          if (row.partner.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailRow(label: 'Partner:', value: row.partner),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedCalendar03,
                size: 14,
                color: isDark ? Colors.grey[100] : const Color(0xffC5C5C5),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildWhenText(
                  row,
                  baseStyle: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The due/scheduled line as either a plain `Text` (non-late) or a
  /// `Text.rich` where only the "Nd/Nh/Nm overdue" span is weight-emphasized
  /// (Late). Same muted grey color throughout — the operator can rank late
  /// rows by weight without color escalating over the Late status chip.
  Widget _buildWhenText(HomeAttentionRow r, {required TextStyle baseStyle}) {
    final due = r.dueAt;
    if (due == null) return Text('Scheduled: —', style: baseStyle);
    final local = due.toLocal();
    final now = DateTime.now();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (r.isLate) {
      final diff = now.difference(local);
      final overdue = diff.inDays > 0
          ? '${diff.inDays}d overdue'
          : diff.inHours > 0
          ? '${diff.inHours}h overdue'
          : '${diff.inMinutes.clamp(1, 59)}m overdue';
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: 'Due $time · '),
            TextSpan(
              text: overdue,
              style: baseStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(local.year, local.month, local.day);
    final delta = dueDay.difference(today).inDays;
    final label = delta == 0
        ? 'Today · $time'
        : delta == 1
        ? 'Tomorrow · $time'
        : 'Scheduled: '
              '${local.year}-${local.month.toString().padLeft(2, '0')}-'
              '${local.day.toString().padLeft(2, '0')} $time';
    return Text(label, style: baseStyle);
  }
}

/// Skeleton placeholder for a picking row — shares the [_TileShell] with
/// [PickingRow], so the loading state matches the loaded state's padding,
/// radius, shadow and inter-row gap exactly.
class PickingRowSkeleton extends StatelessWidget {
  const PickingRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      radius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SkeletonLine(width: 160, height: 15),
              SkeletonBox(
                width: 52,
                height: 22,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SkeletonLine(width: 200, height: 12),
          const SizedBox(height: 8),
          const SkeletonLine(width: 140, height: 12),
        ],
      ),
    );
  }
}

/// Shared shell for both [PickingRow] and [PickingRowSkeleton] — the exact
/// styling used by Pickings / Return / Documents list tiles so all four
/// screens read as one visual family. If the app-wide tile look ever changes,
/// this is the single spot to update.
class _TileShell extends StatelessWidget {
  final BorderRadius radius;
  final Widget child;
  final VoidCallback? onTap;

  const _TileShell({required this.radius, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: radius,
        boxShadow: home.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: const EdgeInsets.all(18), child: child),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 65,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
