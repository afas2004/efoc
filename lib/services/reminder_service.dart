import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/push_config.dart';

enum ReminderResult {
  enabled,

  /// The user (or browser) said no to notifications.
  denied,

  /// No push support here, e.g. iPhone Safari outside a Home Screen app.
  unsupported,

  /// The web push key hasn't been filled in (see push_config.dart).
  notConfigured,

  failed,
}

/// Whether hourly reminders can actually reach this device right now.
enum DeviceReach {
  /// Reminders are off for this account.
  off,

  /// On, permitted, and this device is registered.
  ok,

  /// On, but notifications are blocked here (revoked, or never allowed in
  /// this browser or home-screen app).
  blocked,

  /// On and permitted, but registering this device failed.
  notRegistered,

  /// No push support here.
  unsupported,
}

/// Hourly reminder opt-in. The reminders themselves are sent by
/// worker/remind.py; this registers the device and stores the preference.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  SupabaseClient get _client => Supabase.instance.client;
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  StreamSubscription<String>? _refreshSub;

  /// The token registered from this device, so sign-out can remove it.
  String? _currentToken;

  /// What went wrong in the last [enable] that returned
  /// [ReminderResult.failed], for the error popup.
  String? lastError;

  Future<bool> fetchEnabled() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from('profiles')
        .select('reminders_enabled')
        .eq('id', userId)
        .maybeSingle();
    return (row?['reminders_enabled'] as bool?) ?? false;
  }

  /// Asks for notification permission, registers this device and turns
  /// reminders on. Call from a tap: browsers only show the permission
  /// prompt in response to a user gesture.
  Future<ReminderResult> enable() async {
    lastError = null;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      lastError = 'Not signed in';
      return ReminderResult.failed;
    }
    if (kIsWeb && kWebPushVapidKey.isEmpty) return ReminderResult.notConfigured;

    try {
      if (!await _messaging.isSupported()) return ReminderResult.unsupported;

      final settings = await _messaging.requestPermission();
      final status = settings.authorizationStatus;
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        return ReminderResult.denied;
      }

      final String? token;
      try {
        token = await _getTokenWithRetry();
      } catch (e) {
        lastError = 'Push registration: $e';
        rethrow;
      }
      if (token == null) {
        lastError = 'Push registration returned no token';
        return ReminderResult.failed;
      }
      try {
        await _saveToken(userId, token);
      } catch (e) {
        lastError = 'Saving device: $e';
        rethrow;
      }

      await _client
          .from('profiles')
          .update({'reminders_enabled': true}).eq('id', userId);
      _listenForRefresh(userId);
      return ReminderResult.enabled;
    } catch (e) {
      debugPrint('Enable reminders error: $e');
      lastError ??= '$e';
      return ReminderResult.failed;
    }
  }

  /// The push worker can still be starting up on the first try ("no active
  /// Service Worker"), so give it a couple more chances.
  Future<String?> _getTokenWithRetry() async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _getToken();
      } catch (e) {
        if (attempt >= 3) rethrow;
        debugPrint('getToken attempt $attempt failed: $e');
        await Future.delayed(Duration(milliseconds: 1500 * attempt));
      }
    }
  }

  /// Reminders that arrive while efoc is open (the system notification is
  /// only shown in the background). Null where push isn't supported.
  Future<Stream<RemoteMessage>?> foregroundMessages() async {
    if (kIsWeb && kWebPushVapidKey.isEmpty) return null;
    try {
      if (!await _messaging.isSupported()) return null;
      return FirebaseMessaging.onMessage;
    } catch (e) {
      debugPrint('Foreground messages unavailable: $e');
      return null;
    }
  }

  Future<void> disable() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('profiles')
        .update({'reminders_enabled': false}).eq('id', userId);
  }

  /// On app start: tokens rotate, so re-register quietly if reminders are
  /// on and permission is still granted. Never prompts.
  Future<void> syncOnLaunch() async {
    await checkThisDevice();
  }

  /// Works out whether reminders reach this device, and re-registers it
  /// when they're on and permitted, which repairs a lost registration.
  /// Never prompts for permission.
  Future<DeviceReach> checkThisDevice() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return DeviceReach.off;
    try {
      if (!await fetchEnabled()) return DeviceReach.off;
      if (kIsWeb && kWebPushVapidKey.isEmpty) return DeviceReach.unsupported;
      if (!await _messaging.isSupported()) return DeviceReach.unsupported;
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return DeviceReach.blocked;
      }
      // Same retries as enable(): the push worker may still be starting.
      final token = await _getTokenWithRetry();
      if (token == null) return DeviceReach.notRegistered;
      await _saveToken(userId, token);
      _listenForRefresh(userId);
      return DeviceReach.ok;
    } catch (e) {
      debugPrint('Reminder device check error: $e');
      return DeviceReach.notRegistered;
    }
  }

  /// Before sign-out: stop sending this account's reminders to this device.
  Future<void> forgetThisDevice() async {
    _refreshSub?.cancel();
    _refreshSub = null;
    final token = _currentToken;
    _currentToken = null;
    if (token == null) return;
    try {
      await _client.from('push_tokens').delete().eq('token', token);
    } catch (e) {
      debugPrint('Forget push token error: $e');
    }
  }

  Future<String?> _getToken() =>
      _messaging.getToken(vapidKey: kIsWeb ? kWebPushVapidKey : null);

  Future<void> _saveToken(String userId, String token) async {
    _currentToken = token;
    await _client.from('push_tokens').upsert({
      'token': token,
      'user_id': userId,
      'platform': kIsWeb ? 'web' : 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  void _listenForRefresh(String userId) {
    _refreshSub ??= _messaging.onTokenRefresh.listen((token) {
      _saveToken(userId, token).catchError(
        (Object e) => debugPrint('Save refreshed token error: $e'),
      );
    });
  }
}
