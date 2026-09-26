import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class GroupChips extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const GroupChips({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<AppState>().groups;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final g = groups[i];
          final isOn = selected.contains(g.id);

          return GestureDetector(
            onTap: () => onToggle(g.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: isOn
                    ? EfocColors.accent.withValues(alpha: 0.15)
                    : EfocColors.surface,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color:
                      isOn ? EfocColors.accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOn ? EfocColors.accent : Colors.transparent,
                      border: Border.all(
                        color: isOn
                            ? EfocColors.accent
                            : Colors.white38,
                        width: 1.5,
                      ),
                    ),
                    child: isOn
                        ? const Icon(
                            Icons.check,
                            size: 9,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    g.name,
                    style: TextStyle(
                      color: isOn
                          ? EfocColors.accentBright
                          : Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}