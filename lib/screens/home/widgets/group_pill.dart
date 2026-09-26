import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class GroupPill extends StatelessWidget {
  const GroupPill({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final group = state.currentGroup;

    // TODO: ring should appear when yesterday's stitched vlog is unviewed.
    // Requires a `vlog_views` table (or viewed_at column on vlogs).
    // Disabled until that data exists.
    const showRing = false;

    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(5, 0, 12, 0),
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [
          _RingAvatar(
            color: group.avatarColor,
            initial: group.name.isEmpty
                ? '?'
                : group.name[0].toUpperCase(),
            showRing: showRing,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              group.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: Colors.white54,
          ),
        ],
      ),
    );
  }
}

class _RingAvatar extends StatelessWidget {
  final Color color;
  final String initial;
  final bool showRing;

  const _RingAvatar({
    required this.color,
    required this.initial,
    required this.showRing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showRing
            ? Border.all(color: EfocColors.accent, width: 2)
            : null,
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}