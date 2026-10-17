import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../widgets/caption.dart';

class TextToolbar extends StatefulWidget {
  final String text;
  final String fontKey;
  final Color color;
  final String highlight;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<String> onHighlightChanged;

  const TextToolbar({
    super.key,
    required this.text,
    required this.fontKey,
    required this.color,
    required this.highlight,
    required this.onTextChanged,
    required this.onFontChanged,
    required this.onColorChanged,
    required this.onHighlightChanged,
  });

  @override
  State<TextToolbar> createState() => _TextToolbarState();
}

class _TextToolbarState extends State<TextToolbar> {
  // Kept across rebuilds: a new controller per build reset the cursor to
  // the end on every keystroke.
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _chip({
    required bool active,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? EfocColors.accent.withValues(alpha: 0.12)
              : EfocColors.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: active ? EfocColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _row({required double height, required List<Widget> children}) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // text input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: EfocColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: TextField(
              controller: _controller,
              onChanged: widget.onTextChanged,
              maxLength: 40,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: EfocColors.accent,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                counterText: '',
                hintText: 'Add text…',
                hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // fonts: each label in its own font
        _row(height: 36, children: [
          for (final (key, label) in captionFonts)
            _chip(
              active: key == widget.fontKey,
              onTap: () => widget.onFontChanged(key),
              child: Text(
                label,
                style: captionStyle(
                  key,
                  key == widget.fontKey
                      ? EfocColors.accentBright
                      : Colors.white70,
                  size: 13,
                  highlight: 'dark',
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),

        // highlight: a tiny preview of each style
        _row(height: 36, children: [
          for (final (key, label) in captionHighlights)
            _chip(
              active: key == widget.highlight,
              onTap: () => widget.onHighlightChanged(key),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CaptionBubble(
                    text: 'Aa',
                    fontKey: widget.fontKey,
                    color: widget.color,
                    highlight: key,
                    size: 10,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: key == widget.highlight
                          ? EfocColors.accentBright
                          : Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 8),

        // colours
        _row(height: 30, children: [
          for (final c in captionColors)
            GestureDetector(
              onTap: () => widget.onColorChanged(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: c.toARGB32() == widget.color.toARGB32() ? 28 : 24,
                height: c.toARGB32() == widget.color.toARGB32() ? 28 : 24,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  // Dark swatches need a rim or they vanish on black.
                  border: Border.all(
                    color: c.toARGB32() == widget.color.toARGB32()
                        ? Colors.white
                        : c.computeLuminance() < 0.1
                            ? Colors.white38
                            : Colors.transparent,
                    width: c.toARGB32() == widget.color.toARGB32() ? 2 : 1.5,
                  ),
                ),
              ),
            ),
        ]),
      ],
    );
  }
}
