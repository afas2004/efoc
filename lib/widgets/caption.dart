import 'package:flutter/material.dart';

/// Where a caption sits when the clip predates saved positions: a bit
/// above the middle, same as the capture screen's starting spot.
const Alignment kDefaultCaptionAlignment = Alignment(0, -0.3);

/// The caption look picked on the capture screen. [size] is the classic
/// font size; the others scale from it.
TextStyle captionStyle(String? fontKey, Color color, {double size = 20}) {
  switch (fontKey) {
    case 'bold':
      return TextStyle(
        fontFamily: 'Impact',
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: color,
        height: 1.1,
      );
    case 'elegant':
      return TextStyle(
        fontFamily: 'serif',
        fontSize: size,
        fontStyle: FontStyle.italic,
        color: color,
        height: 1.2,
      );
    case 'mono':
      return TextStyle(
        fontFamily: 'monospace',
        fontSize: size * 0.9,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.2,
      );
    case 'classic':
    default:
      return TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1.2,
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

/// A caption bubble positioned like it was on the capture screen. Put it
/// in a Stack that covers the clip.
class PositionedCaption extends StatelessWidget {
  final String text;
  final String? fontKey;
  final Color color;
  final Alignment alignment;
  final double size;
  final int maxLines;

  const PositionedCaption({
    super.key,
    required this.text,
    required this.fontKey,
    required this.color,
    required this.alignment,
    this.size = 20,
    this.maxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final pad = size * 0.6;
    return Align(
      alignment: alignment,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: pad, vertical: pad * 0.75),
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad * 0.4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(size * 0.7),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: captionStyle(fontKey, color, size: size),
        ),
      ),
    );
  }
}
