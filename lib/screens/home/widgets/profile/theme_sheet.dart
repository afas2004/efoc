import 'package:flutter/material.dart';

import '../../../../theme/colors.dart';

/// Accent colour picker. Pops with the chosen accent's name.
class ThemeSheet extends StatelessWidget {
  final String current;
  const ThemeSheet({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
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
            'Theme',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Accent colour for buttons, dots and highlights. Saved on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: EfocColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: [
              for (final a in EfocColors.accents)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(a.name),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [a.bright, a.dark],
                          ),
                          border: Border.all(
                            color: a.name == current
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: a.name == current
                              ? [
                                  BoxShadow(
                                    color: a.accent.withValues(alpha: 0.6),
                                    blurRadius: 14,
                                  ),
                                ]
                              : null,
                        ),
                        child: a.name == current
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 22)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a.name,
                        style: TextStyle(
                          color: a.name == current
                              ? Colors.white
                              : EfocColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
