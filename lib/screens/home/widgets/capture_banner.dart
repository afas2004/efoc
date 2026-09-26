import 'package:flutter/material.dart';

import '../../../theme/colors.dart';

class CaptureBanner extends StatelessWidget {
    final VoidCallback onTap;

  const CaptureBanner({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        14,
        18,
        26 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black,
          ],
          stops: const [0, 0.55],
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: EfocColors.accent,
            borderRadius: BorderRadius.circular(27),
            boxShadow: [
              BoxShadow(
                color: EfocColors.accent.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.circle, size: 12, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Capture your moment',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}