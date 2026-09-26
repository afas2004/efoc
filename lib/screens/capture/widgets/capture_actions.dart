import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../capture_phase.dart';

class CaptureActions extends StatelessWidget {
  final CapturePhase phase;
  final int selectedCount;
  final VoidCallback onFlip;
  final VoidCallback onStart;
  final VoidCallback onSend;

  const CaptureActions({
    super.key,
    required this.phase,
    required this.selectedCount,
    required this.onFlip,
    required this.onStart,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final isSetup = phase == CapturePhase.setup;
    final isCompose = phase == CapturePhase.compose;
    final isLocked =
        phase == CapturePhase.counting || phase == CapturePhase.recording;

    return Row(
      children: [
        // Flip (setup only)
        if (isSetup)
          _SquareBtn(
            onTap: onFlip,
            child: const Icon(
              Icons.flip_camera_android_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),

        if (isSetup) const SizedBox(width: 10),

        // Primary (Start / Recording / Send)
        Expanded(
          child: _PrimaryButton(
            isSetup: isSetup,
            isCompose: isCompose,
            isLocked: isLocked,
            phase: phase,
            selectedCount: selectedCount,
            onStart: onStart,
            onSend: onSend,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final bool isSetup;
  final bool isCompose;
  final bool isLocked;
  final CapturePhase phase;
  final int selectedCount;
  final VoidCallback onStart;
  final VoidCallback onSend;

  const _PrimaryButton({
    required this.isSetup,
    required this.isCompose,
    required this.isLocked,
    required this.phase,
    required this.selectedCount,
    required this.onStart,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    VoidCallback? onTap;
    Color bg = EfocColors.accent;

    if (isSetup) {
      label = 'Start';
      onTap = onStart;
    } else if (isCompose) {
      label =
          'Send to $selectedCount Log${selectedCount != 1 ? "s" : ""}';
      onTap = selectedCount > 0 ? onSend : null;
    } else if (phase == CapturePhase.counting) {
      label = 'Get ready…';
      onTap = null;
    } else {
      label = 'Recording…';
      onTap = null;
      bg = const Color(0xFFFF3B3B);
    }

    return Opacity(
      opacity: isLocked ? 0.9 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: onTap == null ? bg.withValues(alpha: 0.4) : bg,
            borderRadius: BorderRadius.circular(26),
            boxShadow: onTap == null
                ? null
                : [
                    BoxShadow(
                      color: bg.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SquareBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _SquareBtn({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: EfocColors.surface,
          borderRadius: BorderRadius.circular(26),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}