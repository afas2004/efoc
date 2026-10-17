import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'games_config.dart';

/// The Realtime Database connection for card games.
///
/// Spark allows 100 connections at once, so the app is online only while a
/// game screen is open: each screen calls [acquire] in initState and
/// [release] in dispose, and the last release goes offline (which also runs
/// every onDisconnect write, so seats show as away).
class GamesDatabase {
  GamesDatabase._();
  static final GamesDatabase instance = GamesDatabase._();

  int _users = 0;

  FirebaseDatabase get db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: kGamesDatabaseUrl,
      );

  Future<void> acquire() async {
    _users++;
    await signIn();
    if (_users > 0) await db.goOnline();
  }

  Future<void> release() async {
    if (_users == 0) return;
    _users--;
    if (_users == 0) await db.goOffline();
  }

  /// Signs in to Firebase as the current Supabase user. The Edge Function
  /// `firebase-token` checks the Supabase session and mints a custom token
  /// whose uid is the Supabase user id, so the database rules
  /// (`allowed/{uid}`, `hands/{uid}`, ...) see the same id as the groups.
  Future<String> signIn() async {
    final supabaseUid = Supabase.instance.client.auth.currentUser?.id;
    if (supabaseUid == null) throw StateError('Not signed in');
    final auth = FirebaseAuth.instance;
    if (auth.currentUser?.uid == supabaseUid) return supabaseUid;

    final res =
        await Supabase.instance.client.functions.invoke('firebase-token');
    final data = res.data;
    final token = data is Map ? data['token'] : null;
    if (token is! String || token.isEmpty) {
      throw StateError('No game token');
    }
    final cred = await auth.signInWithCustomToken(token);
    final uid = cred.user?.uid;
    if (uid != supabaseUid) {
      await auth.signOut();
      throw StateError('Game sign-in mismatch');
    }
    return uid!;
  }
}
