import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: 'https://rctvstoosbrgmjmedjwh.supabase.co',
    publishableKey: 'sb_publishable_c2Qee8sVEyIcc3abpx-_WQ_0ssBJQ_4',
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const EfocApp(),
    ),
  );
}