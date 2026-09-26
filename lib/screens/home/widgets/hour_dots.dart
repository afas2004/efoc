import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';

class HourDots extends StatelessWidget {
  final PageController controller;

  const HourDots({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visible = state.visibleHourIndices;
    if (visible.length <= 1) return const SizedBox(height: 18);

    final active = state.currentPageIndex;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int p = 0; p < visible.length; p++)
            GestureDetector(
              onTap: () {
                if (!controller.hasClients) return;
                controller.animateToPage(
                  p,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.5),
                child: _Dot(isActive: p == active),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool isActive;

  const _Dot({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: isActive ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}