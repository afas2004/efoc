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
    final memberCount = group.members.length;

    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(5, 0, 12, 0),
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _RingAvatar(
            color: group.avatarColor,
            initial: group.name.isEmpty
                ? '?'
                : group.name[0].toUpperCase(),
            showRing: false,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$memberCount member${memberCount == 1 ? "" : "s"} · hold to open settings',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
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
      width: 34,
      height: 34,
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
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}