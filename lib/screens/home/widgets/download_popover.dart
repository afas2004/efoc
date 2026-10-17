import 'package:flutter/material.dart';

import '../../../services/export_service.dart';
import '../../../theme/colors.dart';

class DownloadPopover extends StatelessWidget {
  final LayerLink link;
  final VoidCallback onDismiss;
  final VoidCallback onToday;
  final VoidCallback onYesterday;
  final VoidCallback onMake;

  /// A "Make a vlog" result that finished while the sheet was closed.
  final Future<EfocExport?> ready;
  final ValueChanged<EfocExport> onSaveReady;

  const DownloadPopover({
    super.key,
    required this.link,
    required this.onDismiss,
    required this.onToday,
    required this.onYesterday,
    required this.onMake,
    required this.ready,
    required this.onSaveReady,
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
                children: [
                  FutureBuilder<EfocExport?>(
                    future: ready,
                    builder: (context, snap) {
                      final e = snap.data;
                      if (e == null) return const SizedBox.shrink();
                      return _DlRow(
                        title: '✅ Ready to save',
                        subtitle: '${e.clipCount ?? 0} clips · from Make a vlog',
                        onTap: () {
                          onDismiss();
                          onSaveReady(e);
                        },
                      );
                    },
                  ),
                  _DlRow(
                    title: '✂️ Make a vlog…',
                    subtitle: 'Pick Logs and hours',
                    onTap: () {
                      onDismiss();
                      onMake();
                    },
                  ),
                  _DlRow(
                    title: '📼 Today · up to now',
                    subtitle: 'Watch clips so far',
                    onTap: () {
                      onDismiss();
                      onToday();
                    },
                  ),
                  _DlRow(
                    title: '🎬 Yesterday · full',
                    subtitle: 'Stitched at midnight',
                    onTap: () {
                      onDismiss();
                      onYesterday();
                    },
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
  final VoidCallback onTap;

  const _DlRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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