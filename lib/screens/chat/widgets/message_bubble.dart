import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../models/message.dart';
import '../../../services/clip_service.dart';
import '../../../theme/colors.dart';

class MessageBubble extends StatelessWidget {
  final EfocMessage message;
  final bool isGrouped;
  final VoidCallback onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isGrouped,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: isGrouped ? 1 : 6,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            SizedBox(
              width: 28,
              child: isGrouped
                  ? const SizedBox.shrink()
                  : _Avatar(message: message),
            ),
          if (!isMe) const SizedBox(width: 6),
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMe && !isGrouped)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          color: message.senderColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  _Bubble(message: message),
                  if (message.reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, left: 2, right: 2),
                      child: _ReactionRow(reactions: message.reactions),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final EfocMessage message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final maxWidth = MediaQuery.of(context).size.width * 0.72;

    // WhatsApp-ish palette: own = light purple, others = dark gray
    final bg = isMe ? const Color(0xFF7C3AED) : const Color(0xFF262629);

    final hasText = message.text != null && message.text!.isNotEmpty;
    final hasClip = message.clipStoragePath != null;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isMe ? 14 : 3),
          bottomRight: Radius.circular(isMe ? 3 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.replySenderName != null)
            _ReplyPreview(message: message),

          if (hasClip)
            _ClipPreview(storagePath: message.clipStoragePath!),

          if (hasText)
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 7, 11, 2),
              child: Text(
                message.text!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ),

          // Timestamp — right-aligned, small
          Padding(
            padding: EdgeInsets.fromLTRB(
              hasText || hasClip ? 11 : 10,
              hasText ? 0 : 6,
              11,
              hasText || hasClip ? 5 : 6,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

class _ReplyPreview extends StatelessWidget {
  final EfocMessage message;

  const _ReplyPreview({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replySenderName ?? 'User',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message.replyPreviewText != null)
            Text(
              message.replyPreviewText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _ClipPreview extends StatefulWidget {
  final String storagePath;

  const _ClipPreview({required this.storagePath});

  @override
  State<_ClipPreview> createState() => _ClipPreviewState();
}

class _ClipPreviewState extends State<_ClipPreview> {
  bool _playing = false;
  bool _loading = false;
  VideoPlayerController? _controller;

  Future<void> _toggle() async {
    if (_playing && _controller != null) {
      await _controller!.pause();
      setState(() => _playing = false);
      return;
    }
    if (_controller != null) {
      await _controller!.play();
      setState(() => _playing = true);
      return;
    }
    setState(() => _loading = true);
    try {
      final url = await ClipService.instance.getSignedUrl(widget.storagePath);
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _playing = true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl =
        ClipService.instance.publicThumbnailUrl(widget.storagePath);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: GestureDetector(
        onTap: _toggle,
        child: SizedBox(
          width: 170,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_controller != null && _controller!.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                else if (thumbUrl != null)
                  Image.network(
                    thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.black),
                  )
                else
                  Container(color: Colors.black),
                if (!_playing)
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
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

class _Avatar extends StatelessWidget {
  final EfocMessage message;

  const _Avatar({required this.message});

  @override
  Widget build(BuildContext context) {
    final initial = message.senderName.isEmpty
        ? '?'
        : message.senderName[0].toUpperCase();
    final url = message.senderAvatarUrl;
    final hasAvatar = url != null && url.isNotEmpty;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: message.senderColor,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: hasAvatar
          ? Image.network(
              url,
              fit: BoxFit.cover,
              width: 28,
              height: 28,
              errorBuilder: (_, __, ___) => _initial(initial),
            )
          : _initial(initial),
    );
  }

  Widget _initial(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  final Map<String, List<String>> reactions;

  const _ReactionRow({required this.reactions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: reactions.entries.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF262629),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.key, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 3),
              Text(
                '${e.value.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}