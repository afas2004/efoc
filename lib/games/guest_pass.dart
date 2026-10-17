import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-time guest passes for a table: efoc.party/play?pass=CODE lets one
/// person in with just a name, to that table only, for two hours. They get
/// a Firebase token from the `guest-token` Edge Function and never a
/// Supabase account. See supabase/migrations/20261018_game_guest_passes.sql.
class GuestPass {
  GuestPass._();

  static const _chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _deviceKeyPref = 'games.guestDeviceKey';
  static const _namePref = 'games.guestName';

  static SupabaseClient get _client => Supabase.instance.client;

  static String _random(int n) {
    final rand = Random.secure();
    return List.generate(n, (_) => _chars[rand.nextInt(_chars.length)]).join();
  }

  static Uri linkFor(String code) =>
      Uri.https('efoc.party', '/play', {'pass': code});

  /// The pass code in a /play link, if there is one.
  static String? codeIn(Uri uri) {
    if (uri.path != '/play') return null;
    final code = (uri.queryParameters['pass'] ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return code.length == 12 ? code : null;
  }

  /// Makes a pass for this table (the caller must be in [groupId]).
  static Future<Uri> create({
    required String roomId,
    required String groupId,
    required String gameId,
  }) async {
    final code = _random(12);
    await _client.from('game_guest_passes').insert({
      'code': code,
      'room_id': roomId,
      'group_id': groupId,
      'game_id': gameId,
    });
    return linkFor(code);
  }

  /// Redeems [code] as [name] from this browser. The same browser can
  /// redeem again (after a reload) until it expires.
  static Future<GuestTicket> redeem(String code, String name) async {
    final prefs = await SharedPreferences.getInstance();
    var deviceKey = prefs.getString(_deviceKeyPref);
    if (deviceKey == null) {
      deviceKey = _random(32);
      await prefs.setString(_deviceKeyPref, deviceKey);
    }

    final Object? data;
    try {
      data = (await _client.functions.invoke('guest-token', body: {
        'pass': code,
        'name': name,
        'device_key': deviceKey,
      }))
          .data;
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      throw GuestPassError(msg ?? "Couldn't open the table");
    }
    if (data is! Map || data['token'] is! String) {
      throw GuestPassError("Couldn't open the table");
    }
    await prefs.setString(_namePref, data['name'] as String? ?? name);
    return GuestTicket(
      token: data['token'] as String,
      uid: data['uid'] as String,
      name: data['name'] as String? ?? name,
      roomId: data['room_id'] as String,
      groupId: data['group_id'] as String,
      gameId: data['game_id'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  /// The name this browser used last time, to fill in after a reload.
  static Future<String?> lastName() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_namePref);
    } catch (_) {
      return null;
    }
  }
}

class GuestTicket {
  final String token;
  final String uid;
  final String name;
  final String roomId;
  final String groupId;
  final String gameId;
  final DateTime expiresAt;

  const GuestTicket({
    required this.token,
    required this.uid,
    required this.name,
    required this.roomId,
    required this.groupId,
    required this.gameId,
    required this.expiresAt,
  });
}

class GuestPassError implements Exception {
  final String message;
  GuestPassError(this.message);

  @override
  String toString() => message;
}
