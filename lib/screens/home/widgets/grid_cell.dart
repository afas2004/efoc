import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/member.dart';
import '../../../services/clip_service.dart';
import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class EfocGridCell extends StatelessWidget {
  final int memberIdx;
  final int hourIdx;
  final VoidCallback onTap;

  const EfocGridCell({
    super.key,
    required this.memberIdx,
    required this.hourIdx,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final member = state.currentGroup.members[memberIdx];
    final filled = state.isCellFilled(memberIdx, hourIdx, member);
    final hour = state.hours[hourIdx];

    if (filled) {
      final clip = state.clipFor(memberIdx, hourIdx);
      return _FilledCell(
        member: member,
        memberIdx: memberIdx,
        hour: hour,
        clip: clip,
        onTap: onTap,
      );
    }

    return _EmptyCell(
      member: member,
      hour: hour,
      onTap: onTap,
    );
  }
}

class _EmptyCell extends StatelessWidget {
  final EfocMember member;
  final int hour;
  final VoidCallback onTap;

  const _EmptyCell({
    required this.member,
    required this.hour,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = member.isMe;
    final isCurrentHour = hour == DateTime.now().hour;
    final showTapHint = isMine && isCurrentHour;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: const Color(0xFF0D0D0D),
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 10,
              right: 40,
              child: _UserChip(member: member),
            ),
            Center(
              child: _BreathingZ(
                color: isMine
                    ? EfocColors.accent.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              right: 0,
              child: Align(
                alignment: const Alignment(0, 0.28),
                child: Text(
                  '$hour:00',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.18),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            if (showTapHint)
              const Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(child: _TapHint()),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilledCell extends StatelessWidget {
  final EfocMember member;
  final int memberIdx;
  final int hour;
  final Map<String, dynamic>? clip;
  final VoidCallback onTap;

  const _FilledCell({
    required this.member,
    required this.memberIdx,
    required this.hour,
    required this.clip,
    required this.onTap,
  });

  static const _gradients = [
    [Color(0xFFA855F7), Color(0xFF6D28D9)],
    [Color(0xFFC77DFF), Color(0xFF7C3AED)],
    [Color(0xFF7C3AED), Color(0xFF4C1D95)],
    [Color(0xFFEC4899), Color(0xFF9D174D)],
    [Color(0xFF8B5CF6), Color(0xFF5B21B6)],
    [Color(0xFF06B6D4), Color(0xFF0E7490)],
    [Color(0xFF10B981), Color(0xFF047857)],
    [Color(0xFFF59E0B), Color(0xFFB45309)],
    [Color(0xFFEF4444), Color(0xFF991B1B)],
    [Color(0xFF6366F1), Color(0xFF3730A3)],
  ];

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.white;
    final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
    if (cleaned.length != 6) return Colors.white;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return Colors.white;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final pair = _gradients[memberIdx % _gradients.length];
    final overlayText = (clip?['text_overlay'] as String?)?.trim() ?? '';
    final overlayColor = _parseColor(clip?['text_color'] as String?);
    final hasOverlay = overlayText.isNotEmpty;

    final storagePath = clip?['storage_path'] as String?;
    final thumbUrl = storagePath == null
        ? null
        : ClipService.instance.publicThumbnailUrl(storagePath);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: pair,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbUrl != null)
              Image.network(
                thumbUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                loadingBuilder: (_, child, progress) {
                  return progress == null ? child : const SizedBox.shrink();
                },
              ),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  stops: const [0, 0.2, 0.7, 1],
                ),
              ),
            ),

            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),

            Positioned(
              top: 10,
              left: 10,
              right: 40,
              child: _UserChip(member: member, onDark: true),
            ),

            if (hasOverlay)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      overlayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: overlayColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final EfocMember member;
  final bool onDark;

  const _UserChip({required this.member, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final initial = member.isMe ? 'Y' : member.name[0].toUpperCase();
    final label = member.isMe ? 'You' : member.name;
    final avatarUrl = member.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: onDark
                ? Colors.black.withValues(alpha: 0.3)
                : member.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: hasAvatar
              ? Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  width: 26,
                  height: 26,
                  errorBuilder: (_, __, ___) => Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: onDark ? 0.9 : 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _BreathingZ extends StatefulWidget {
  final Color color;

  const _BreathingZ({required this.color});

  @override
  State<_BreathingZ> createState() => _BreathingZState();
}

class _BreathingZState extends State<_BreathingZ>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final scale = 0.98 + (t * 0.06);
        final opacity = 0.5 + (t * 0.4);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Text(
              'z z z',
              style: TextStyle(
                color: widget.color,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TapHint extends StatefulWidget {
  const _TapHint();

  @override
  State<_TapHint> createState() => _TapHintState();
}

class _TapHintState extends State<_TapHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final scale = 1 + (_controller.value * 0.04);
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: EfocColors.accent,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: EfocColors.accent.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Text(
              'Tap to capture',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }
}