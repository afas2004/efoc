import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../models/message.dart';
import '../../../services/chat_service.dart';
import '../../../services/clip_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/caption.dart';
import '../../../widgets/clip_video.dart';
import '../../chat/widgets/clip_chat_bar.dart';

class ClipPopup extends StatefulWidget {
  final int initialMemberIdx;
  final int initialHourIdx;

  /// Called after a reply is sent from the popup, to open the chat.
  final VoidCallback? onReplied;

  const ClipPopup({
    super.key,
    required this.initialMemberIdx,
    required this.initialHourIdx,
    this.onReplied,
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

  /// The clip's chat card: its reactions and replies are the clip's.
  EfocMessage? _card;

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
      _card = null;
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
      state.markClipsViewed([clip]);
      _loadCard(clip['id'] as String);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load video: $e';
      });
    }
  }

  Future<void> _loadCard(String clipId) async {
    try {
      final card = await ChatService.instance.fetchClipCard(clipId);
      if (mounted && _clip?['id'] == clipId) setState(() => _card = card);
    } catch (e) {
      debugPrint('Clip card: $e');
    }
  }

  void _react(String emoji) {
    final card = _card;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (card == null || myId == null) return;
    setState(() => _card = card.withMyReaction(emoji, myId));
    ChatService.instance
        .react(messageId: card.id, emoji: emoji)
        .catchError((Object e) => debugPrint('React error: $e'));
  }

  Future<void> _reply(String text) async {
    final card = _card;
    if (card == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ChatService.instance.sendText(
        groupId: card.groupId,
        text: text,
        replyToId: card.id,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      return;
    }
    navigator.pop();
    widget.onReplied?.call();
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
    final overlayColor = parseCaptionColor(_clip?['text_color'] as String?);

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
              bottom: _barSpace,
              child: Center(
                child: _buildVideoArea(
                  member: member,
                  overlayText: overlayText,
                  overlayColor: overlayColor,
                  hour: state.hours[_hourIdx],
                ),
              ),
            ),

            // Reactions + reply, shared with the clip's chat card
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  MediaQuery.of(context).padding.bottom +
                  16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipChatBar(
                    key: ValueKey(_clip?['id']),
                    card: _card,
                    onReact: _react,
                    onReply: _reply,
                  ),
                ),
              ),
            ),

            // Tap zones for prev / next
            Positioned(
              left: 0,
              top: 0,
              bottom: _barSpace,
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
              bottom: _barSpace,
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

  /// Room kept under the video for the reaction / reply bar.
  double get _barSpace =>
      MediaQuery.of(context).viewInsets.bottom +
      MediaQuery.of(context).padding.bottom +
      130;

  Widget _buildVideoArea({
    required dynamic member,
    required String overlayText,
    required Color overlayColor,
    required int hour,
  }) {
    // The clip's own shape once loaded (landscape for sideways clips).
    final rotation = clipRotationOf(_clip);
    final ar = (_videoController?.value.isInitialized ?? false)
        ? uprightAspect(_videoController!, rotation)
        : 3 / 2;

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
              UprightVideoCover(
                controller: _videoController!,
                rotation: rotation,
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

            // 4. Caption, where it was placed when recorded
            if (overlayText.isNotEmpty)
              PositionedCaption(
                text: overlayText,
                fontKey: _clip?['text_font'] as String?,
                highlight: _clip?['text_bg'] as String?,
                color: overlayColor,
                alignment: captionAlignmentOf(_clip),
              ),
          ],
        ),
      ),
    );
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }
}