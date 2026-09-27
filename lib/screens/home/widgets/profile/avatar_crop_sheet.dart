import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../theme/colors.dart';

class AvatarCropSheet extends StatefulWidget {
  final Uint8List imageBytes;

  const AvatarCropSheet({super.key, required this.imageBytes});

  @override
  State<AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<AvatarCropSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transform = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _crop() async {
    setState(() => _saving = true);
    // Give the frame a beat to render the "saving" state, then capture.
    await Future.delayed(const Duration(milliseconds: 16));

    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(byteData.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.of(context).size.width - 40;
    final cropSize = available < 320 ? available : 320.0;

    return Container(
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Move and zoom',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pinch or drag to adjust. The circle is what others will see.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: cropSize,
            height: cropSize,
            child: Stack(
              children: [
                // Capture region — RepaintBoundary captures ONLY this.
                RepaintBoundary(
                  key: _boundaryKey,
                  child: ClipRect(
                    child: SizedBox(
                      width: cropSize,
                      height: cropSize,
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1.0,
                        maxScale: 5.0,
                        panEnabled: true,
                        scaleEnabled: true,
                        child: Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.cover,
                          width: cropSize,
                          height: cropSize,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),

                // Mask overlay — NOT captured, sits on top.
                IgnorePointer(
                  child: CustomPaint(
                    size: Size(cropSize, cropSize),
                    painter: _CircleMaskPainter(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          GestureDetector(
            onTap: _saving ? null : _crop,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: _saving
                    ? EfocColors.accent.withValues(alpha: 0.4)
                    : EfocColors.accent,
                borderRadius: BorderRadius.circular(26),
              ),
              alignment: Alignment.center,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    final full = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final circle = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: size.width / 2,
        ),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, circle),
      paint,
    );

    // Thin white ring around the crop circle for visual reference.
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}