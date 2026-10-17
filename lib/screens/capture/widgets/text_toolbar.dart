import 'package:flutter/material.dart';

import '../../../theme/colors.dart';

class TextToolbar extends StatefulWidget {
  final String text;
  final String fontKey;
  final Color color;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<Color> onColorChanged;

  const TextToolbar({
    super.key,
    required this.text,
    required this.fontKey,
    required this.color,
    required this.onTextChanged,
    required this.onFontChanged,
    required this.onColorChanged,
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

  static const _fonts = [
    ('classic', 'Classic'),
    ('bold', 'Bold'),
    ('elegant', 'Elegant'),
    ('mono', 'Mono'),
  ];

  static const _colors = [
    Colors.white,
    Colors.black,
    Color(0xFFA855F7),
    Color(0xFFC77DFF),
    Color(0xFFFFD93D),
    Color(0xFF4ECDC4),
  ];

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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
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

        // fonts
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _fonts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (key, label) = _fonts[i];
              final isActive = key == widget.fontKey;
              return GestureDetector(
                onTap: () => widget.onFontChanged(key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? EfocColors.accent.withValues(alpha: 0.12)
                        : EfocColors.surface,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: isActive
                          ? EfocColors.accent
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isActive
                          ? EfocColors.accentBright
                          : Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // colors
        SizedBox(
          height: 28,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _colors.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _colors[i];
              final isActive = c.toARGB32() == widget.color.toARGB32();
              return GestureDetector(
                onTap: () => widget.onColorChanged(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isActive ? 28 : 24,
                  height: isActive ? 28 : 24,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    // Black needs a rim or it vanishes on the black screen.
                    border: Border.all(
                      color: isActive
                          ? Colors.white
                          : c.computeLuminance() < 0.1
                              ? Colors.white38
                              : Colors.transparent,
                      width: isActive ? 2 : 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}