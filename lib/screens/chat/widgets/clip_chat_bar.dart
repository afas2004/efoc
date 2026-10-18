import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/colors.dart';

/// Reactions and a reply box under a clip in a popup (spec 6.7). Both act
/// on the clip's chat card, so the grid popup and the chat share them.
class ClipChatBar extends StatefulWidget {
  /// The clip's chat card, or null while loading / if it has none.
  final EfocMessage? card;
  final void Function(String emoji) onReact;
  final void Function(String text) onReply;

  const ClipChatBar({
    super.key,
    required this.card,
    required this.onReact,
    required this.onReply,
  });

  static const emojis = ['❤️', '😂', '😮', '👏'];

  @override
  State<ClipChatBar> createState() => _ClipChatBarState();
}

class _ClipChatBarState extends State<ClipChatBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.card == null) return;
    widget.onReply(text);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final enabled = card != null;
    final mine = card?.myReaction;

    // Swallow taps so they don't reach the popup's close-on-tap backdrop.
    return GestureDetector(
      onTap: () {},
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final e in ClipChatBar.emojis)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _EmojiButton(
                      emoji: e,
                      count:
                          card?.reactions.where((r) => r.emoji == e).length ??
                          0,
                      selected: mine == e,
                      onTap: enabled ? () => widget.onReact(e) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: enabled,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Reply…',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: enabled ? _send : null,
                    icon: Icon(
                      Icons.send_rounded,
                      color: EfocColors.accentBright,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  const _EmojiButton({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? EfocColors.accent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? EfocColors.accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
