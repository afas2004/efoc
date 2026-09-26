import 'package:flutter/material.dart';

import '../../../theme/colors.dart';

class DownloadPopover extends StatelessWidget {
  final LayerLink link;
  final VoidCallback onDismiss;

  const DownloadPopover({
    super.key,
    required this.link,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
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
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 230,
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
                children: const [
                  _DlRow(
                    title: '📼 Today · up to now',
                    subtitle: 'Stitch clips so far',
                  ),
                  _DlRow(
                    title: '🎬 Yesterday · full',
                    subtitle: 'Stitched at midnight',
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

class _DlRow extends StatelessWidget {
  final String title;
  final String subtitle;

  const _DlRow({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title — coming soon'),
            duration: const Duration(milliseconds: 1200),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}