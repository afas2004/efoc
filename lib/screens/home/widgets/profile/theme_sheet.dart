import 'package:flutter/material.dart';

import '../../../../theme/colors.dart';

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
          const SizedBox(height: 20),
          for (final theme in ['Purple', 'Dark', 'Auto'])
            ListTile(
              title: Text(
                theme,
                style: const TextStyle(color: Colors.white),
              ),
              trailing: theme == current
                  ? const Icon(Icons.check, color: EfocColors.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(theme),
            ),
        ],
      ),
    );
  }
}