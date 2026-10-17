import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';
import '../../vlog/vlog_viewer_screen.dart';

enum _Ring { none, unviewed, viewed }

class GroupPill extends StatelessWidget {
  const GroupPill({super.key});

  void _openYesterday(BuildContext context) {
    final state = context.read<AppState>();
    final vlog = state.yesterdayVlog(state.currentGroup.id);
    if (vlog == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No vlog from yesterday'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }
    openStitchedVlog(context, vlog, dayLabel: 'Yesterday');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final group = state.currentGroup;
    final memberCount = group.members.length;
    final yesterday = state.yesterdayVlog(group.id);
    final ring = yesterday == null
        ? _Ring.none
        : state.isVlogViewed(yesterday)
            ? _Ring.viewed
            : _Ring.unviewed;

    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(5, 0, 12, 0),
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          // Own detector so tapping the avatar opens yesterday's vlog
          // instead of the group dropdown the rest of the pill opens.
          GestureDetector(
            onTap: () => _openYesterday(context),
            child: _RingAvatar(
              color: group.avatarColor,
              initial: group.name.isEmpty
                  ? '?'
                  : group.name[0].toUpperCase(),
              ring: ring,
            ),
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
          // Something new in another group: nudge toward the dropdown.
          Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Colors.white54,
              ),
              if (state.otherGroupsHaveNews)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: EfocColors.accentBright,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: EfocColors.accent.withValues(alpha: 0.8),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingAvatar extends StatefulWidget {
  final Color color;
  final String initial;
  final _Ring ring;

  const _RingAvatar({
    required this.color,
    required this.initial,
    required this.ring,
  });

  @override
  State<_RingAvatar> createState() => _RingAvatarState();
}

class _RingAvatarState extends State<_RingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_RingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.ring == _Ring.unviewed) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: switch (widget.ring) {
              _Ring.none => null,
              _Ring.viewed => Border.all(color: Colors.white24, width: 2),
              _Ring.unviewed => Border.all(color: EfocColors.accent, width: 2),
            },
            boxShadow: widget.ring == _Ring.unviewed
                ? [
                    BoxShadow(
                      color: EfocColors.accent.withValues(alpha: 0.25 + 0.45 * t),
                      blurRadius: 4 + 8 * t,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(2),
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
        alignment: Alignment.center,
        child: Text(
          widget.initial,
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
