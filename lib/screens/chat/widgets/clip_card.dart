import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../services/clip_service.dart';
import '../../../services/vlog_service.dart';
import '../../../theme/colors.dart';

/// A clip someone posted to the grid, shown in chat (spec 5.2): 200px wide,
/// 9:13, hour badge, play icon, one-line caption. Once the stitcher has
/// deleted the raw clip it keeps its spot, drawn from the thumbnail if
/// that's still there or a placeholder if not.
class ClipCard extends StatelessWidget {
  final EfocMessage message;
  final VoidCallback onTap;

  const ClipCard({super.key, required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final path = message.cardPath ?? message.clipStoragePath;
    final thumb = path == null
        ? null
        : ClipService.instance.publicThumbnailUrl(path);
    final hour = message.cardHour;
    final caption = message.cardCaption?.trim() ?? '';
    final expired = message.clipId == null;

    return _CardFrame(
      isMe: message.isMe,
      onTap: onTap,
      background: thumb == null
          ? _Placeholder(expired: expired)
          : Image.network(
              thumb,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Placeholder(expired: expired),
            ),
      badge: hour == null
          ? null
          : _Badge(
              label: formatHour12(hour),
              pulse: _isToday(message.cardDate),
            ),
      caption: caption.isEmpty ? null : caption,
      showPlay: !expired,
    );
  }
}

/// The day's stitched vlog, posted by the stitcher after midnight.
class VlogCard extends StatefulWidget {
  final EfocMessage message;
  final VoidCallback onTap;

  const VlogCard({super.key, required this.message, required this.onTap});

  @override
  State<VlogCard> createState() => _VlogCardState();
}

class _VlogCardState extends State<VlogCard> {
  // The vlogs bucket is private, so its thumbnails need signed URLs.
  static final Map<String, Future<String>> _thumbUrls = {};

  Future<String>? _thumb;

  @override
  void initState() {
    super.initState();
    final path = widget.message.cardPath;
    if (path != null) {
      _thumb = _thumbUrls.putIfAbsent(
        path,
        () => VlogService.instance.signedUrl(path),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = widget.message.vlogId == null;
    final date = widget.message.cardDate;

    return _CardFrame(
      isMe: false,
      onTap: widget.onTap,
      background: _thumb == null
          ? _Placeholder(expired: expired)
          : FutureBuilder<String>(
              future: _thumb,
              builder: (_, snap) => snap.hasData
                  ? Image.network(
                      snap.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _Placeholder(expired: expired),
                    )
                  : _Placeholder(expired: expired && snap.hasError),
            ),
      badge: _Badge(
        label: date == null ? 'Daily vlog' : 'Vlog · ${vlogDayLabel(date)}',
        pulse: false,
      ),
      caption: null,
      showPlay: !expired,
    );
  }
}

/// "Yesterday", or "Oct 16" for older days.
String vlogDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  if (today.difference(d).inDays == 1) return 'Yesterday';
  if (d == today) return 'Today';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

bool _isToday(DateTime? d) {
  if (d == null) return false;
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

class _CardFrame extends StatelessWidget {
  final bool isMe;
  final VoidCallback onTap;
  final Widget background;
  final Widget? badge;
  final String? caption;
  final bool showPlay;

  const _CardFrame({
    required this.isMe,
    required this.onTap,
    required this.background,
    required this.badge,
    required this.caption,
    required this.showPlay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isMe
                ? EfocColors.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: AspectRatio(
            aspectRatio: 9 / 13,
            child: Stack(
              fit: StackFit.expand,
              children: [
                background,
                if (badge != null) Positioned(top: 8, left: 8, child: badge!),
                if (showPlay)
                  Center(
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          width: 44,
                          height: 44,
                          color: Colors.black.withValues(alpha: 0.3),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (caption != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                      child: Text(
                        caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final bool expired;

  const _Placeholder({required this.expired});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1A47), Color(0xFF12121A)],
        ),
      ),
      alignment: Alignment.center,
      child: expired
          ? Text(
              'Clip expired',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

/// Translucent pill with a dot, pulsing for today's clips.
class _Badge extends StatefulWidget {
  final String label;
  final bool pulse;

  const _Badge({required this.label, required this.pulse});

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: EfocColors.accentBright,
        shape: BoxShape.circle,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pulse != null)
            FadeTransition(
              opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse!),
              child: dot,
            )
          else
            dot,
          const SizedBox(width: 5),
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
