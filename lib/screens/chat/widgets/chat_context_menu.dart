import 'package:flutter/material.dart';

import '../../../models/message.dart';

/// Shows a floating context menu anchored to a long-pressed message.
/// Positions above the tap point if there's room, otherwise below.
void showChatContextMenu({
  required BuildContext context,
  required EfocMessage message,
  required Offset tapPosition,
  required VoidCallback onReply,
  required void Function(String emoji) onReact,
  required VoidCallback onMoreEmojis,
  required VoidCallback? onCopy,
  required VoidCallback? onDelete,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  void dismiss() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => _ContextMenuLayer(
      message: message,
      tapPosition: tapPosition,
      onDismiss: dismiss,
      onReply: () {
        dismiss();
        onReply();
      },
      onReact: (emoji) {
        dismiss();
        onReact(emoji);
      },
      onMoreEmojis: () {
        dismiss();
        onMoreEmojis();
      },
      onCopy: onCopy == null
          ? null
          : () {
              dismiss();
              onCopy();
            },
      onDelete: onDelete == null
          ? null
          : () {
              dismiss();
              onDelete();
            },
    ),
  );

  overlay.insert(entry);
}

class _ContextMenuLayer extends StatelessWidget {
  final EfocMessage message;
  final Offset tapPosition;
  final VoidCallback onDismiss;
  final VoidCallback onReply;
  final void Function(String emoji) onReact;
  final VoidCallback onMoreEmojis;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  const _ContextMenuLayer({
    required this.message,
    required this.tapPosition,
    required this.onDismiss,
    required this.onReply,
    required this.onReact,
    required this.onMoreEmojis,
    required this.onCopy,
    required this.onDelete,
  });

  /// WhatsApp's default quick reactions, in its order.
  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  static const _menuWidth = 290.0;

  /// Rough max height — used only to decide whether "above" has room.
  /// Actual rendering uses bottom-anchoring so this doesn't need to be exact.
  static const _estimatedMenuHeight = 200.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    const gap = 10.0;

    // Horizontal: center on the tap, clamped to screen edges.
    double left = tapPosition.dx - _menuWidth / 2;
    if (left < 8) left = 8;
    if (left + _menuWidth > screen.width - 8) {
      left = screen.width - _menuWidth - 8;
    }

    // Vertical: prefer above. Anchor by BOTTOM edge so the menu sits
    // snug against the tap regardless of its actual height.
    final spaceAbove = tapPosition.dy - safeTop;
    final spaceBelow = screen.height - safeBottom - tapPosition.dy;

    final placeAbove = spaceAbove >= _estimatedMenuHeight + gap;
    final placeBelow =
        !placeAbove && spaceBelow >= _estimatedMenuHeight + gap;

    Widget menu = Material(
      color: Colors.transparent,
      child: _MenuCard(
        emojis: _emojis,
        current: message.myReaction,
        onReact: onReact,
        onMoreEmojis: onMoreEmojis,
        onReply: onReply,
        onCopy: onCopy,
        onDelete: onDelete,
      ),
    );

    // If neither side has enough space, fall back to whichever side is
    // larger and let it clamp.
    final actuallyAbove = placeAbove || (!placeBelow && spaceAbove > spaceBelow);

    Positioned positioned;
    if (actuallyAbove) {
      positioned = Positioned(
        left: left,
        bottom: screen.height - tapPosition.dy + gap,
        child: menu,
      );
    } else {
      positioned = Positioned(
        left: left,
        top: tapPosition.dy + gap,
        child: menu,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        positioned,
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<String> emojis;
  final String? current;
  final void Function(String emoji) onReact;
  final VoidCallback onMoreEmojis;
  final VoidCallback onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  const _MenuCard({
    required this.emojis,
    required this.current,
    required this.onReact,
    required this.onMoreEmojis,
    required this.onReply,
    required this.onCopy,
    required this.onDelete,
  });

  List<String> _quickRow() {
    final c = current;
    if (c == null || emojis.contains(c)) return emojis;
    return [...emojis.take(emojis.length - 1), c];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _ContextMenuLayer._menuWidth,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Your current reaction sits on a grey disc; tapping it
                // again removes it. A reaction picked from the full
                // picker takes the place of the last quick emoji.
                for (final e in _quickRow())
                  GestureDetector(
                    onTap: () => onReact(e),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: e == current
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        e,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: onMoreEmojis,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),

          _MenuItem(
            icon: Icons.reply_rounded,
            label: 'Reply',
            onTap: onReply,
          ),

          if (onCopy != null) ...[
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            _MenuItem(
              icon: Icons.copy_rounded,
              label: 'Copy',
              onTap: onCopy!,
            ),
          ],

          if (onDelete != null) ...[
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            _MenuItem(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: const Color(0xFFFF5555),
              onTap: onDelete!,
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}