import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'games/table_link.dart';
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
  final initialUri = await _readInitialLink();
  final initialCode = initialUri?.queryParameters['code'];
  if (initialCode != null && initialCode.isNotEmpty) {
    appState.setPendingInviteCode(initialCode);
  }
  // A card-game table link (efoc.party/join?table=...).
  final initialTable = initialUri == null ? null : TableLink.fromUri(initialUri);
  if (initialTable != null) appState.setPendingTable(initialTable);

  // Warm-start deep links (Android). Web handles this via page reload.
  _listenForIncomingInviteLinks(appState);

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const EfocApp(),
    ),
  );
}

Future<Uri?> _readInitialLink() async {
  if (kIsWeb) return Uri.base;
  try {
    return await AppLinks().getInitialLink();
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
      final table = TableLink.fromUri(uri);
      if (table != null) appState.setPendingTable(table);
    },
    onError: (_) {},
  );
}