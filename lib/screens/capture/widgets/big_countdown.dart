import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/colors.dart';

/// "Ready?" inside a ring that runs out as [progress] goes 0 → 1.
class BigCountdown extends StatelessWidget {
  final Animation<double> progress;

  const BigCountdown({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, child) => CustomPaint(
            painter: _RingPainter(progress: progress.value),
            child: child,
          ),
          child: const Center(
            child: Text(
              'Ready?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
                shadows: [
                  Shadow(
                    color: Color(0x80000000),
                    offset: Offset(0, 4),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 3;

    // track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.white.withValues(alpha: 0.12);

    canvas.drawCircle(center, radius, trackPaint);

    // what's left of the second
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = EfocColors.accent;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * (1 - progress),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
