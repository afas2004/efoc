import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/day_dot_state.dart';
import '../../../state/app_state.dart';
import '../../../theme/colors.dart';
import '../../vlog/vlog_viewer_screen.dart';

/// Today plus the previous six days. Stitched days open their vlog.
class DayDots extends StatelessWidget {
  const DayDots({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dots = state.dayDotsFor(state.currentGroup.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final dot in dots)
            GestureDetector(
              onTap: () => _onTap(context, dot),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DayDot(kind: dot.kind, hasUnseen: dot.hasUnseenClips),
                    const SizedBox(height: 4),
                    Text(
                      dot.kind == DayDotKind.today
                          ? 'Today'
                          : dot.label == 'Yesterday'
                              ? 'Yday'
                              : dot.label,
                      style: TextStyle(
                        color: dot.kind == DayDotKind.today
                            ? Colors.white70
                            : Colors.white30,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onTap(BuildContext context, DayDotData dot) {
    final vlog = dot.vlog;
    if (dot.kind == DayDotKind.today) {
      openTodayPreview(context);
    } else if (vlog != null) {
      openStitchedVlog(context, vlog, dayLabel: dot.label);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No vlog for ${dot.label}'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    }
  }
}

class _DayDot extends StatelessWidget {
  final DayDotKind kind;

  /// Unwatched clips from others that day. Stitched days already show
  /// their own watched/unwatched state, so this only recolours today and
  /// days without a vlog.
  final bool hasUnseen;

  const _DayDot({required this.kind, this.hasUnseen = false});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case DayDotKind.today:
        return Container(
          width: 20,
          height: 8,
          decoration: BoxDecoration(
            color: hasUnseen ? EfocColors.accentBright : Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: hasUnseen
                ? [
                    BoxShadow(
                      color: EfocColors.accent.withValues(alpha: 0.8),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
      case DayDotKind.stitchedUnviewed:
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: EfocColors.accentBright,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: EfocColors.accent.withValues(alpha: 0.8),
                blurRadius: 8,
              ),
            ],
          ),
        );
      case DayDotKind.stitchedViewed:
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: EfocColors.accent.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
        );
      case DayDotKind.missed:
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: hasUnseen ? EfocColors.accentBright : Colors.white24,
              width: 1.2,
            ),
          ),
        );
    }
  }
}
