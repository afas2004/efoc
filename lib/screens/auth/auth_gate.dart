import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';
import '../../services/auth_service.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _initialized = false;
  Session? _session;

  @override
  void initState() {
    super.initState();

    _session = AuthService.instance.currentSession;
    _initialized = true;

    AuthService.instance.authStateChanges.listen((event) {
      if (!mounted) return;

      setState(() {
        _session = event.session;
      });

      // Pop any pushed routes (profile sheet, check-email screen,
      // sub-sheets, dialogs) back to the root so the correct screen
      // is visible after login or logout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        efocNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SplashScreen();
    if (_session == null) return const LoginScreen();
    return const HomeScreen();
  }
}