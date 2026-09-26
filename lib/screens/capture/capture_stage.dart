import 'package:flutter/material.dart';

class CaptureStage extends StatelessWidget {
  final String ratio; // '9x16' | '1x1' | '16x9'
  final Widget? preview;
  final List<Widget> children;

  const CaptureStage({
    super.key,
    required this.ratio,
    this.preview,
    required this.children,
  });

  double get _aspect {
    switch (ratio) {
      case '1x1':
        return 1.0;
      case '16x9':
        return 16 / 9;
      case '9x16':
      default:
        return 9 / 16;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final aspect = _aspect;

        double w, h;
        if (aspect <= 1) {
          h = maxH;
          w = h * aspect;
          if (w > maxW) {
            w = maxW;
            h = w / aspect;
          }
        } else {
          w = maxW;
          h = w / aspect;
          if (h > maxH) {
            h = maxH;
            w = h * aspect;
          }
        }

        return Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: preview == null
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1A1A2E),
                        Color(0xFF16213E),
                        Color(0xFF0F3460),
                      ],
                    )
                  : null,
              color: preview != null ? Colors.black : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Live camera or placeholder label
                  if (preview != null)
                    preview!
                  else
                    const Center(
                      child: Text(
                        'LIVE CAMERA',
                        style: TextStyle(
                          color: Color(0x22FFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
                    ),

                  // Overlay children (countdown, REC pip, text)
                  ...children,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}