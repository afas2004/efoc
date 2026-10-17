import 'package:flutter/material.dart';

/// One accent colour family, picked in Profile → Theme.
class EfocAccent {
  final String name;
  final Color accent;
  final Color bright;
  final Color dark;

  const EfocAccent(this.name, this.accent, this.bright, this.dark);
}

class EfocColors {
  EfocColors._();

  static const List<EfocAccent> accents = [
    EfocAccent('Purple', Color(0xFFA855F7), Color(0xFFC77DFF), Color(0xFF6D28D9)),
    EfocAccent('Blue', Color(0xFF3B82F6), Color(0xFF60A5FA), Color(0xFF1D4ED8)),
    EfocAccent('Pink', Color(0xFFEC4899), Color(0xFFF472B6), Color(0xFFBE185D)),
    EfocAccent('Green', Color(0xFF10B981), Color(0xFF34D399), Color(0xFF047857)),
    EfocAccent('Orange', Color(0xFFF97316), Color(0xFFFB923C), Color(0xFFC2410C)),
  ];

  static EfocAccent _current = accents.first;
  static EfocAccent get current => _current;

  /// Only ThemeController calls this; it also repaints the app.
  static void use(EfocAccent a) => _current = a;

  // Brand (switchable, so not const)
  static Color get accent => _current.accent;
  static Color get accentBright => _current.bright;
  static Color get accentDark => _current.dark;

  // Backgrounds
  static const Color bg           = Color(0xFF0A0A0A);
  static const Color surface      = Color(0xFF1C1C1E);
  static const Color surface2     = Color(0xFF2A2A2C);
  static const Color sheetBg      = Color(0xFF141414);

  // Text
  static const Color textPrimary  = Color(0xFFFFFFFF);
  static const Color textMuted    = Color(0xFF888888);
  static const Color textFaint    = Color(0xFF555555);

  // Status
  static const Color success      = Color(0xFF34D399);
  static const Color warning      = Color(0xFFFFA94D);
  static const Color danger       = Color(0xFFFF5555);
}
