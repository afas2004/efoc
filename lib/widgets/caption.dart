import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Where a caption sits when the clip predates saved positions: a bit
/// above the middle, same as the capture screen's starting spot.
const Alignment kDefaultCaptionAlignment = Alignment(0, -0.3);

/// Caption fonts: (key stored in clips.text_font, label). The stitcher
/// (worker/stitch.py) uses the same Google Fonts files.
const captionFonts = [
  ('classic', 'Classic'), // Poppins Bold
  ('bold', 'Bold'), // Anton
  ('elegant', 'Elegant'), // Playfair Display Italic
  ('mono', 'Mono'), // JetBrains Mono
  ('hand', 'Hand'), // Caveat
  ('script', 'Script'), // Pacifico
];

/// Caption backgrounds: (key stored in clips.text_bg, label).
const captionHighlights = [
  ('dark', 'Dark'),
  ('light', 'Light'),
  ('color', 'Colour'),
  ('none', 'None'),
];
const kDefaultHighlight = 'dark';

const captionColors = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFA855F7),
  Color(0xFFC77DFF),
  Color(0xFFEC4899),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFFFD93D),
  Color(0xFFA3E635),
  Color(0xFF22C55E),
  Color(0xFF4ECDC4),
  Color(0xFF38BDF8),
  Color(0xFF3B82F6),
  Color(0xFF8B5A2B),
];

/// Readable text on top of [bg].
Color _contrastOn(Color bg) =>
    bg.computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// The caption look picked on the capture screen. [size] is the Classic
/// font size; the others are tuned to look about as big.
TextStyle captionStyle(
  String? fontKey,
  Color color, {
  double size = 20,
  String? highlight,
}) {
  // A "Colour" highlight paints the box in the chosen colour, so the text
  // switches to black or white on top of it.
  final textColor = highlight == 'color' ? _contrastOn(color) : color;
  final outline = highlight == 'none'
      ? [
          Shadow(
            color: _contrastOn(color).withValues(alpha: 0.85),
            blurRadius: size * 0.25,
          ),
          Shadow(
            color: _contrastOn(color).withValues(alpha: 0.85),
            offset: Offset(0, size * 0.05),
          ),
        ]
      : null;
  final base = TextStyle(color: textColor, height: 1.15, shadows: outline);

  switch (fontKey) {
    case 'bold':
      return GoogleFonts.anton(textStyle: base, fontSize: size * 1.1);
    case 'elegant':
      return GoogleFonts.playfairDisplay(
        textStyle: base,
        fontSize: size * 1.05,
        fontStyle: FontStyle.italic,
      );
    case 'mono':
      return GoogleFonts.jetBrainsMono(
        textStyle: base,
        fontSize: size * 0.9,
        fontWeight: FontWeight.w500,
      );
    case 'hand':
      return GoogleFonts.caveat(
        textStyle: base,
        fontSize: size * 1.35,
        fontWeight: FontWeight.w700,
      );
    case 'script':
      return GoogleFonts.pacifico(textStyle: base, fontSize: size);
    case 'classic':
    default:
      return GoogleFonts.poppins(
        textStyle: base,
        fontSize: size,
        fontWeight: FontWeight.w700,
      );
  }
}

/// The box behind the caption, or null for "None".
BoxDecoration? captionBox(String? highlight, Color color, double size) {
  final radius = BorderRadius.circular(size * 0.6);
  switch (highlight) {
    case 'none':
      return null;
    case 'light':
      return BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: radius,
      );
    case 'color':
      return BoxDecoration(color: color, borderRadius: radius);
    case 'dark':
    default:
      return BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: radius,
      );
  }
}

Color parseCaptionColor(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.white;
  final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
  if (cleaned.length != 6) return Colors.white;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return Colors.white;
  return Color(0xFF000000 | value);
}

/// Saved caption position for a clip row, or the default for old clips.
Alignment captionAlignmentOf(Map<String, dynamic>? clip) {
  final x = (clip?['text_x'] as num?)?.toDouble();
  final y = (clip?['text_y'] as num?)?.toDouble();
  if (x == null || y == null) return kDefaultCaptionAlignment;
  return Alignment(x.clamp(-1.0, 1.0), y.clamp(-1.0, 1.0));
}

/// The caption bubble itself (text in its font, on its highlight).
class CaptionBubble extends StatelessWidget {
  final String text;
  final String? fontKey;
  final Color color;
  final String? highlight;
  final double size;
  final int? maxLines;

  const CaptionBubble({
    super.key,
    required this.text,
    required this.fontKey,
    required this.color,
    required this.highlight,
    this.size = 20,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final pad = size * 0.6;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad * 0.35),
      decoration: captionBox(highlight, color, size),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: captionStyle(fontKey, color, size: size, highlight: highlight),
      ),
    );
  }
}

/// A caption positioned like it was on the capture screen. Put it in a
/// Stack that covers the clip.
class PositionedCaption extends StatelessWidget {
  final String text;
  final String? fontKey;
  final Color color;
  final String? highlight;
  final Alignment alignment;
  final double size;
  final int maxLines;

  const PositionedCaption({
    super.key,
    required this.text,
    required this.fontKey,
    required this.color,
    required this.alignment,
    this.highlight,
    this.size = 20,
    this.maxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final pad = size * 0.6;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad * 0.75),
        child: CaptionBubble(
          text: text,
          fontKey: fontKey,
          color: color,
          highlight: highlight ?? kDefaultHighlight,
          size: size,
          maxLines: maxLines,
        ),
      ),
    );
  }
}
