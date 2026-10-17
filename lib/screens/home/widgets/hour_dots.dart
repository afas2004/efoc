import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';
import '../../vlog/vlog_viewer_screen.dart';

/// One dot per visible hour, plus a bigger dot in front for yesterday's
/// stitched vlog when there is one.
class HourDots extends StatelessWidget {
  final PageController controller;

  const HourDots({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visible = state.visibleHourIndices;
    final stitched = state.yesterdayVlog(state.currentGroup.id);
    final showHours = visible.length > 1;
    if (!showHours && stitched == null) return const SizedBox(height: 18);

    final active = state.currentPageIndex;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (stitched != null) ...[
            GestureDetector(
              onTap: () =>
                  openStitchedVlog(context, stitched, dayLabel: 'Yesterday'),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.5),
                child: _StitchDot(viewed: state.isVlogViewed(stitched)),
              ),
            ),
            if (showHours) const SizedBox(width: 8),
          ],
          if (showHours)
            for (int p = 0; p < visible.length; p++)
              GestureDetector(
                onTap: () {
                  if (!controller.hasClients) return;
                  controller.animateToPage(
                    p,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.5),
                  child: _Dot(
                    isActive: p == active,
                    hasUnseen:
                        state.hourHasUnseen(state.hours[visible[p]]),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool isActive;

  /// Someone else's clip in this hour you haven't opened yet.
  final bool hasUnseen;

  const _Dot({required this.isActive, required this.hasUnseen});

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (hasUnseen) {
      color = EfocColors.accentBright;
    } else if (isActive) {
      color = Colors.white;
    } else {
      color = Colors.white.withValues(alpha: 0.22);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: isActive ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
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
  }
}

/// Yesterday's stitched vlog: glowing until watched, faded after.
class _StitchDot extends StatelessWidget {
  final bool viewed;

  const _StitchDot({required this.viewed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: viewed
            ? EfocColors.accent.withValues(alpha: 0.4)
            : EfocColors.accentBright,
        boxShadow: viewed
            ? null
            : [
                BoxShadow(
                  color: EfocColors.accent.withValues(alpha: 0.8),
                  blurRadius: 10,
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.play_arrow_rounded,
        size: 10,
        color: viewed ? Colors.white54 : Colors.white,
      ),
    );
  }
}
