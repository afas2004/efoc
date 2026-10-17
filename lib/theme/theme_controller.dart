import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'colors.dart';

/// The accent colour choice. Saved on this device.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'efoc.accent';

  String get name => EfocColors.current.name;

  /// Call before runApp so the first frame already has the right colour.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      EfocColors.use(
        EfocColors.accents.firstWhere(
          (a) => a.name == saved,
          orElse: () => EfocColors.accents.first,
        ),
      );
    } catch (_) {
      // Storage blocked (private mode etc.): keep the default.
    }
  }

  Future<void> set(String name) async {
    final accent = EfocColors.accents.firstWhere(
      (a) => a.name == name,
      orElse: () => EfocColors.accents.first,
    );
    if (accent.name == EfocColors.current.name) return;
    EfocColors.use(accent);
    _repaintEverything();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, accent.name);
    } catch (_) {}
  }

  /// Colours are read during build, so every widget has to build again.
  /// Rebuilding in place (not swapping a key) keeps open screens and sheets.
  void _repaintEverything() {
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) rebuild(root);
  }
}
