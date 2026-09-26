import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class GroupDropdown extends StatelessWidget {
  final LayerLink link;
  final VoidCallback onDismiss;
  final VoidCallback onCreateJoin;
  final VoidCallback onOpenSettings;

  const GroupDropdown({
    super.key,
    required this.link,
    required this.onDismiss,
    required this.onCreateJoin,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final width = MediaQuery.of(context).size.width - 28;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: EfocColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 40,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < state.groups.length; i++)
                    _GroupRow(
                      groupIdx: i,
                      isActive: i == state.currentGroupIndex,
                      onTap: () {
                        state.setGroup(i);
                        onDismiss();
                      },
                    ),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                                    InkWell(
                    onTap: () {
                      onDismiss();
                      onCreateJoin();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: EfocColors.accent
                                  .withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 16,
                              color: EfocColors.accentBright,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Create or join a Log',
                            style: TextStyle(
                              color: EfocColors.accentBright,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  final int groupIdx;
  final bool isActive;
  final VoidCallback onTap;

  const _GroupRow({
    required this.groupIdx,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final group = state.groups[groupIdx];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: group.avatarColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                group.name.isEmpty
                    ? '?'
                    : group.name[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: TextStyle(
                      color: isActive
                          ? EfocColors.accentBright
                          : Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${group.members.length} member${group.members.length != 1 ? "s" : ""}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: EfocColors.accentBright,
              ),
          ],
        ),
      ),
    );
  }
}