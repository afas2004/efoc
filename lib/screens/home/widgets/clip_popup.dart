import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../services/clip_service.dart';
import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class ClipPopup extends StatefulWidget {
  final int initialMemberIdx;
  final int initialHourIdx;

  const ClipPopup({
    super.key,
    required this.initialMemberIdx,
    required this.initialHourIdx,
  });

  @override
  State<ClipPopup> createState() => _ClipPopupState();
}

class _ClipPopupState extends State<ClipPopup> {
  late int _memberIdx;
  late int _hourIdx;

  VideoPlayerController? _videoController;
  Map<String, dynamic>? _clip;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _memberIdx = widget.initialMemberIdx;
    _hourIdx = widget.initialHourIdx;
    _loadClip();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadClip() async {
    await _videoController?.dispose();
    _videoController = null;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final state = context.read<AppState>();
    final clip = state.clipFor(_memberIdx, _hourIdx);

    if (clip == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No clip found';
      });
      return;
    }

    final path = clip['storage_path'] as String?;
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Clip has no storage path';
      });
      return;
    }

    try {
      final url = await ClipService.instance.getSignedUrl(path);
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _clip = clip;
        _videoController = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load video: $e';
      });
    }
  }

  void _navigate(int dir) {
    final state = context.read<AppState>();
    final members = state.currentGroup.members;
    if (members.length < 2) return;

    for (int i = 1; i <= members.length; i++) {
      final cand =
          (_memberIdx + dir * i + members.length * 10) % members.length;
      if (state.isCellFilled(cand, _hourIdx, members[cand])) {
        setState(() => _memberIdx = cand);
        _loadClip();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final member = state.currentGroup.members[_memberIdx];
    final overlayText = (_clip?['text_overlay'] as String?)?.trim() ?? '';
    final overlayColor = _parseColor(_clip?['text_color'] as String?);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Solid dark backdrop
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.85)),
            ),

            // Video layer — sized to its own aspect ratio
            Positioned.fill(
              child: Center(
                child: _buildVideoArea(
                  member: member,
                  overlayText: overlayText,
                  overlayColor: overlayColor,
                  hour: state.hours[_hourIdx],
                ),
              ),
            ),

            // Tap zones for prev / next
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 80,
              child: GestureDetector(
                onTap: () => _navigate(-1),
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 80,
              child: GestureDetector(
                onTap: () => _navigate(1),
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),

            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea({
    required dynamic member,
    required String overlayText,
    required Color overlayColor,
    required int hour,
  }) {
    // Determine aspect ratio: use video's own if ready, else fall back to 9:16
    final ar = (_videoController?.value.isInitialized ?? false)
        ? _videoController!.value.aspectRatio
        : 9 / 16;

    return AspectRatio(
      aspectRatio: ar,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Video (or loading/error)
            if (_loading)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            else if (_videoController != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),

            // 2. Author chip (top-left)
            Positioned(
              top: 14,
              left: 14,
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      member.isMe ? 'Y' : member.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    member.isMe ? 'You' : member.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 3. Hour label (top-right)
            Positioned(
              top: 18,
              right: 14,
              child: Text(
                _formatHour(hour),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: const [
                    Shadow(blurRadius: 6, color: Colors.black54),
                  ],
                ),
              ),
            ),

            // 4. Text overlay (centered)
            if (overlayText.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    overlayText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: overlayColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.white;
    final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
    if (cleaned.length != 6) return Colors.white;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return Colors.white;
    return Color(0xFF000000 | value);
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }
}