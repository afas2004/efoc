import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../games/open_table_link.dart';
import '../../../games/table_link.dart';
import '../../../models/message.dart';
import '../../../services/clip_service.dart';
import '../../../theme/colors.dart';
import 'clip_card.dart';

class MessageBubble extends StatelessWidget {
  final EfocMessage message;
  final bool isGrouped;
  final void Function(Offset globalTap) onLongPress;
  final VoidCallback onReactionsTap;

  /// Tapping a clip or vlog card.
  final VoidCallback onCardTap;

  /// Tapping the reply quote: jump to the quoted message.
  final VoidCallback onQuoteTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isGrouped,
    required this.onLongPress,
    required this.onReactionsTap,
    required this.onCardTap,
    required this.onQuoteTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    // The day's vlog belongs to the whole Log: centred, no sender.
    if (message.kind == MessageKind.vlog) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Center(
          child: GestureDetector(
            onLongPressStart: (d) => onLongPress(d.globalPosition),
            onSecondaryTapDown: (d) => onLongPress(d.globalPosition),
            child: _WithReactions(
              message: message,
              onReactionsTap: onReactionsTap,
              child: VlogCard(message: message, onTap: onCardTap),
            ),
          ),
        ),
      );
    }

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
              onLongPressStart: (details) =>
                  onLongPress(details.globalPosition),
              onSecondaryTapDown: (details) =>
                  onLongPress(details.globalPosition),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
                  _WithReactions(
                    message: message,
                    onReactionsTap: onReactionsTap,
                    child: switch (message.kind) {
                      MessageKind.clip =>
                        ClipCard(message: message, onTap: onCardTap),
                      MessageKind.sticker => _StickerMessage(
                        message: message,
                        onQuoteTap: onQuoteTap,
                      ),
                      _ => _Bubble(message: message, onQuoteTap: onQuoteTap),
                    },
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

/// Like WhatsApp, the reaction pill hangs off the bottom edge of the
/// bubble (or card) on the sender's side.
class _WithReactions extends StatelessWidget {
  final EfocMessage message;
  final VoidCallback onReactionsTap;
  final Widget child;

  const _WithReactions({
    required this.message,
    required this.onReactionsTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(
            bottom: message.reactions.isEmpty ? 0 : 18,
          ),
          child: child,
        ),
        if (message.reactions.isNotEmpty)
          Positioned(
            bottom: 0,
            left: isMe ? null : 8,
            right: isMe ? 8 : null,
            child: _ReactionPill(
              message: message,
              onTap: onReactionsTap,
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final EfocMessage message;
  final VoidCallback onQuoteTap;

  const _Bubble({required this.message, required this.onQuoteTap});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final maxWidth = MediaQuery.of(context).size.width * 0.72;
    final bg = isMe ? const Color(0xFF7C3AED) : const Color(0xFF262629);

    final hasText = message.text != null && message.text!.isNotEmpty;
    final table = hasText ? TableLink.inText(message.text!) : null;
    final hasClip = message.clipStoragePath != null;
    final hasReply = message.replySenderName != null;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasReply)
              GestureDetector(
                onTap: onQuoteTap,
                child: _ReplyPreview(message: message),
              ),

            if (hasClip)
              Align(
                alignment: isMe
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: _ClipPreview(storagePath: message.clipStoragePath!),
              ),

            if (table != null)
              _TableCard(
                text: TableLink.withoutLink(message.text!),
                link: table,
              )
            else if (hasText)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 11, 3),
                child: Text(
                  message.text!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 6),
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
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Colors.white70, width: 3),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _replyAuthor(message),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message.replyStickerUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _QuotedSticker(url: message.replyStickerUrl!, size: 38),
            )
          else if (message.replyPreviewText != null)
            Text(
              message.replyPreviewText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

/// `▶ Ali · 3 PM` for a clip, `Ali` for text (spec 5.3).
String _replyAuthor(EfocMessage message) {
  final name = message.replySenderName ?? 'User';
  return switch (message.replyKind) {
      MessageKind.clip => [
          '▶ $name',
          if (message.replyHour != null) formatHour12(message.replyHour!),
        ].join(' · '),
      MessageKind.vlog => '▶ Daily vlog',
      _ => name,
    };
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
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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

/// The sticker a message is quoting, drawn small inside the quote instead of
/// the word "Sticker".
class _QuotedSticker extends StatelessWidget {
  final String url;
  final double size;

  const _QuotedSticker({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
}

/// A sticker draws as the image alone — no bubble behind it — the way it does
/// in WhatsApp. The URL is the copy stored on the message, so it keeps working
/// if the pack is deleted.
///
/// What the bubble used to give it (who sent it, when, and what it's replying
/// to) is laid out around the image instead, so a sticker is never anonymous.
class _StickerMessage extends StatelessWidget {
  static const double _size = 132;

  final EfocMessage message;
  final VoidCallback onQuoteTap;

  const _StickerMessage({required this.message, required this.onQuoteTap});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final url = message.stickerUrl;

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.replySenderName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _StickerQuote(message: message, onTap: onQuoteTap),
          ),
        _image(url),
        const SizedBox(height: 2),
        Text(
          _clock(message.createdAt),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _image(String? url) {
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Image.network(
      url,
      width: _size,
      height: _size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(
        width: _size,
        height: _size,
        child: const Icon(
          Icons.broken_image_outlined,
          color: Colors.white24,
          size: 28,
        ),
      ),
    );
  }
}

/// The quoted message above a sticker. Same information as the bubble's quote,
/// standing on the page instead of inside a bubble.
class _StickerQuote extends StatelessWidget {
  final EfocMessage message;
  final VoidCallback onTap;

  const _StickerQuote({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 190),
        decoration: BoxDecoration(
          color: const Color(0xFF262629),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: EfocColors.accent.withValues(alpha: 0.8),
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _replyAuthor(message),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (message.replyStickerUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _QuotedSticker(url: message.replyStickerUrl!, size: 32),
              )
            else if (message.replyPreviewText != null)
              Text(
                message.replyPreviewText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

/// `3:04 PM`, matching the timestamp inside a text bubble.
String _clock(DateTime d) {
  final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $ap';
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

class _ReactionPill extends StatelessWidget {
  final EfocMessage message;
  final VoidCallback onTap;

  const _ReactionPill({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Up to three distinct emojis, then the total once more than one
    // person has reacted.
    final emojis = message.topEmojis.take(3).join();
    final total = message.reactions.length;

    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('$emojis$total'),
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF262629),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EfocColors.bg, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emojis, style: const TextStyle(fontSize: 14)),
              if (total > 1) ...[
                const SizedBox(width: 3),
                Text(
                  '$total',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A game table someone opened: their line plus a big Join button.
class _TableCard extends StatelessWidget {
  final String text;
  final TableLink link;

  const _TableCard({required this.text, required this.link});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text.isEmpty ? '🃏 ${link.gameName()} table' : text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF6D28D9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () => openTableLink(context, link),
            icon: const Icon(Icons.style_rounded, size: 18),
            label: Text(
              'Join ${link.gameName()}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
