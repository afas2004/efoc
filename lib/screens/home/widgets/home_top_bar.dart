import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';
import 'group_pill.dart';

class HomeTopBar extends StatelessWidget {
  final LayerLink groupLink;
  final LayerLink downloadLink;
  final VoidCallback onToggleGroup;
  final VoidCallback onOpenGroupSettings;
  final VoidCallback onToggleDownload;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenChat;

  const HomeTopBar({
    super.key,
    required this.groupLink,
    required this.downloadLink,
    required this.onToggleGroup,
    required this.onOpenGroupSettings,
    required this.onToggleDownload,
    required this.onOpenProfile,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onOpenProfile,
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [EfocColors.accent, EfocColors.accentDark],
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                'A',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: CompositedTransformTarget(
              link: groupLink,
              child: GestureDetector(
                onTap: onToggleGroup,
                onLongPress: state.currentGroup.isPersonal
                    ? null
                    : onOpenGroupSettings,
                child: const GroupPill(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          CompositedTransformTarget(
            link: downloadLink,
            child: _IconBtn(
              icon: Icons.download_rounded,
              onTap: onToggleDownload,
            ),
          ),
          const SizedBox(width: 8),

          _IconBtn(
            icon: Icons.chat_bubble_outline_rounded,
            onTap: onOpenChat,
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: EfocColors.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}