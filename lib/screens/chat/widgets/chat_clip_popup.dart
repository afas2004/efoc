import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../models/message.dart';
import '../../../services/clip_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/caption.dart';
import '../../../widgets/clip_video.dart';
import 'clip_chat_bar.dart';

/// Opens a clip card full-size (spec 6.7). Resolves to the reply text if
/// one was sent from the popup, so the chat can post it quoting the card.
Future<String?> showChatClipPopup({
  required BuildContext context,
  required EfocMessage message,
  required void Function(String? emoji) onReact,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => _ChatClipPopup(message: message, onReact: onReact),
  );
}

class _ChatClipPopup extends StatefulWidget {
  final EfocMessage message;
  final void Function(String? emoji) onReact;

  const _ChatClipPopup({required this.message, required this.onReact});

  @override
  State<_ChatClipPopup> createState() => _ChatClipPopupState();
}

class _ChatClipPopupState extends State<_ChatClipPopup> {
  late EfocMessage _card = widget.message;
  Map<String, dynamic>? _clip;
  VideoPlayerController? _video;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final clipId = widget.message.clipId;
    if (clipId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final clip = await Supabase.instance.client
          .from('clips')
          .select()
          .eq('id', clipId)
          .maybeSingle();
      final path = clip?['storage_path'] as String?;
      if (clip == null || path == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
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
        _video = controller;
        _loading = false;
      });
      context.read<AppState>().markClipsViewed([clip]);
    } catch (e) {
      debugPrint('Chat clip popup: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _react(String emoji) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    setState(() => _card = _card.withMyReaction(emoji, myId));
    widget.onReact(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width * 0.8;
    final rotation = clipRotationOf(_clip);
    final ar = (_video?.value.isInitialized ?? false)
        ? uprightAspect(_video!, rotation)
        : 9 / 15;
    final caption =
        (_clip?['text_overlay'] as String?)?.trim() ??
        widget.message.cardCaption?.trim() ??
        '';
    final hour = widget.message.cardHour;
    final thumbPath = widget.message.cardPath;
    final thumb = thumbPath == null
        ? null
        : ClipService.instance.publicThumbnailUrl(thumbPath);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  0,
                  media.padding.top + 12,
                  0,
                  media.viewInsets.bottom + media.padding.bottom + 16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: width),
                        child: AspectRatio(
                          aspectRatio: ar,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              color: Colors.black,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_video != null)
                                    UprightVideoCover(
                                      controller: _video!,
                                      rotation: rotation,
                                    )
                                  else if (thumb != null)
                                    Image.network(
                                      thumb,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox.shrink(),
                                    ),
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
                                  else if (_video == null)
                                    Center(
                                      child: Text(
                                        'Clip expired',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 14,
                                    left: 14,
                                    right: 14,
                                    child: Text(
                                      [
                                        widget.message.isMe
                                            ? 'You'
                                            : widget.message.senderName,
                                        if (hour != null) formatHour12(hour),
                                      ].join(' · '),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 6,
                                            color: Colors.black54,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (caption.isNotEmpty)
                                    PositionedCaption(
                                      text: caption,
                                      fontKey: _clip?['text_font'] as String?,
                                      highlight: _clip?['text_bg'] as String?,
                                      color: parseCaptionColor(
                                        _clip?['text_color'] as String?,
                                      ),
                                      alignment: _clip == null
                                          ? Alignment.center
                                          : captionAlignmentOf(_clip),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: width,
                      child: ClipChatBar(
                        card: _card,
                        onReact: _react,
                        onReply: (text) => Navigator.of(context).pop(text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
