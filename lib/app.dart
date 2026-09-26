import 'package:flutter/material.dart';

import 'screens/auth/auth_gate.dart';
import 'theme/colors.dart';

final GlobalKey<NavigatorState> efocNavigatorKey = GlobalKey<NavigatorState>();

class EfocApp extends StatelessWidget {
  const EfocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Efoc',
      debugShowCheckedModeBanner: false,
      navigatorKey: efocNavigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: EfocColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: EfocColors.accent,
          secondary: EfocColors.accentBright,
          surface: EfocColors.surface,
          error: EfocColors.danger,
        ),
      ),
      home: const AuthGate(),
    );
  }
}