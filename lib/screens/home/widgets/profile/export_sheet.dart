import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/vlog_service.dart';
import '../../../../state/app_state.dart';
import '../../../../theme/colors.dart';
import '../../../vlog/vlog_viewer_screen.dart';

enum _SaveState { idle, saving, saved, failed }

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key});

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  _SaveState _save = _SaveState.idle;

  Future<void> _saveYesterday() async {
    final state = context.read<AppState>();
    final group = state.currentGroup;
    final vlog = state.yesterdayVlog(group.id);
    if (vlog == null || _save == _SaveState.saving) return;

    setState(() => _save = _SaveState.saving);
    state.markVlogViewed(vlog);
    try {
      // Opens the device share sheet: save to Photos/Files or send it on.
      await VlogService.instance.shareVlog(vlog, groupName: group.name);
      if (mounted) setState(() => _save = _SaveState.saved);
    } catch (e) {
      debugPrint('Export yesterday error: $e');
      if (mounted) setState(() => _save = _SaveState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final group = state.currentGroup;
    final count = state.todaysClipsInOrder.length;
    final yesterday = state.yesterdayVlog(group.id);

    final String ySubtitle;
    if (yesterday == null) {
      ySubtitle = 'Not stitched yet · ${group.name}';
    } else {
      final clips = yesterday.clipCount;
      ySubtitle = switch (_save) {
        _SaveState.saving => 'Preparing…',
        _SaveState.saved => 'Saved ✓',
        _SaveState.failed => "Couldn't download. Tap to try again.",
        _SaveState.idle =>
          '$clips clip${clips == 1 ? '' : 's'} · ${group.name}',
      };
    }

    return Container(
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Export vlogs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          _ExportRow(
            emoji: '💾',
            title: "Save yesterday's vlog",
            subtitle: ySubtitle,
            trailing: _save == _SaveState.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: EfocColors.textMuted,
                    ),
                  )
                : Icon(
                    _save == _SaveState.saved
                        ? Icons.check_rounded
                        : Icons.download_rounded,
                    color: _save == _SaveState.saved
                        ? EfocColors.success
                        : EfocColors.textFaint,
                    size: 20,
                  ),
            onTap: yesterday == null ? null : _saveYesterday,
          ),
          const SizedBox(height: 10),
          _ExportRow(
            emoji: '📼',
            title: 'Watch today so far',
            subtitle: count == 0
                ? 'No clips yet in ${group.name}'
                : '$count clip${count == 1 ? '' : 's'} · ~${count * 3}s · ${group.name}',
            trailing: const Icon(
              Icons.play_arrow_rounded,
              color: EfocColors.textFaint,
              size: 20,
            ),
            onTap: count == 0 ? null : () => openTodayPreview(context),
          ),
          const SizedBox(height: 14),
          const Text(
            "Today's clips are stitched into one video at midnight, then you "
            'can save it here. Saving opens your share sheet: pick Photos, '
            'Files, or send it on.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EfocColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _ExportRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: EfocColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
