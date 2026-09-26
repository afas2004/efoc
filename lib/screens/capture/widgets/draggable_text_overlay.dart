import 'package:flutter/material.dart';

class DraggableTextOverlay extends StatefulWidget {
  final String text;
  final String fontKey;
  final Color color;
  final Offset alignment; // -1..1 on each axis
  final ValueChanged<Offset> onAlignmentChanged;

  const DraggableTextOverlay({
    super.key,
    required this.text,
    required this.fontKey,
    required this.color,
    required this.alignment,
    required this.onAlignmentChanged,
  });

  @override
  State<DraggableTextOverlay> createState() => _DraggableTextOverlayState();
}

class _DraggableTextOverlayState extends State<DraggableTextOverlay> {
  late Offset _local;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _local = widget.alignment;
  }

  @override
  void didUpdateWidget(DraggableTextOverlay old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.alignment != widget.alignment) {
      _local = widget.alignment;
    }
  }

  TextStyle get _style {
    switch (widget.fontKey) {
      case 'bold':
        return TextStyle(
          fontFamily: 'Impact',
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: widget.color,
          height: 1.1,
        );
      case 'elegant':
        return TextStyle(
          fontFamily: 'serif',
          fontSize: 20,
          fontStyle: FontStyle.italic,
          color: widget.color,
          height: 1.2,
        );
      case 'mono':
        return TextStyle(
          fontFamily: 'monospace',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: widget.color,
          height: 1.2,
        );
      case 'classic':
      default:
        return TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: widget.color,
          height: 1.2,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (_) => setState(() => _dragging = true),
          onPanUpdate: (details) {
            final dx = details.delta.dx / (constraints.maxWidth / 2);
            final dy = details.delta.dy / (constraints.maxHeight / 2);
            setState(() {
              _local = Offset(
                (_local.dx + dx).clamp(-1.0, 1.0),
                (_local.dy + dy).clamp(-1.0, 1.0),
              );
            });
            widget.onAlignmentChanged(_local);
          },
          onPanEnd: (_) => setState(() => _dragging = false),
          child: Align(
            alignment: Alignment(_local.dx, _local.dy),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.text.isEmpty ? ' ' : widget.text,
                textAlign: TextAlign.center,
                style: _style,
              ),
            ),
          ),
        );
      },
    );
  }
}