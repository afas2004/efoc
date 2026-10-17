import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'state/app_state.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: 'https://rctvstoosbrgmjmedjwh.supabase.co',
    publishableKey: 'sb_publishable_c2Qee8sVEyIcc3abpx-_WQ_0ssBJQ_4',
  );

  // Saved accent colour, before the first frame.
  await ThemeController.instance.load();

  final appState = AppState();

  // Initial launch: pull invite code from URL (web) or initial deep link (Android).
  final initialCode = await _readInitialInviteCode();
  if (initialCode != null && initialCode.isNotEmpty) {
    appState.setPendingInviteCode(initialCode);
  }

  // Warm-start deep links (Android). Web handles this via page reload.
  _listenForIncomingInviteLinks(appState);

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const EfocApp(),
    ),
  );
}

Future<String?> _readInitialInviteCode() async {
  if (kIsWeb) {
    return Uri.base.queryParameters['code'];
  }
  try {
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    return initialUri?.queryParameters['code'];
  } catch (_) {
    return null;
  }
}

void _listenForIncomingInviteLinks(AppState appState) {
  if (kIsWeb) return;
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen(
    (uri) {
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        appState.setPendingInviteCode(code);
      }
    },
    onError: (_) {},
  );
}