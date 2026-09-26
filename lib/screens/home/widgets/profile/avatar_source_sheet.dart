import 'package:flutter/material.dart';

import '../../../../theme/colors.dart';

class AvatarSourceSheet extends StatelessWidget {
  const AvatarSourceSheet({super.key});

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
          ListTile(
            leading: const Icon(Icons.image_outlined,
                color: Colors.white),
            title: const Text(
              'Choose from library',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () => Navigator.of(context).pop('library'),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined,
                color: Colors.white),
            title: const Text(
              'Take a photo',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () => Navigator.of(context).pop('camera'),
          ),
        ],
      ),
    );
  }
}