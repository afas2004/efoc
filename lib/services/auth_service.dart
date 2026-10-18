import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'reminder_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isLoggedIn => currentSession != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Username accounts sign in with `<username>@` this domain. It has no
  /// mail server; the address only exists so Supabase has an email to
  /// key the account on. Never show it to anyone.
  static const usernameDomain = 'users.efoc.party';

  static bool isUsernameEmail(String? email) =>
      (email ?? '').toLowerCase().endsWith('@$usernameDomain');

  /// True for accounts made with a username instead of an email.
  bool get isUsernameAccount => isUsernameEmail(currentUser?.email);

  /// The real email, or null for username accounts.
  String? get realEmail => isUsernameAccount ? null : currentUser?.email;

  static final usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Recovery codes are the password of a username account: 12 characters
  /// from the invite-code alphabet, shown as XXXX-XXXX-XXXX. Spaces, dashes
  /// and case don't matter when typing one in.
  static String normalizeRecoveryCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String formatRecoveryCode(String code) {
    final c = normalizeRecoveryCode(code);
    final parts = <String>[];
    for (var i = 0; i < c.length; i += 4) {
      parts.add(c.substring(i, i + 4 > c.length ? c.length : i + 4));
    }
    return parts.join('-');
  }

  static String newRecoveryCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> signInWithUsername({
    required String username,
    required String recoveryCode,
  }) async {
    await _client.auth.signInWithPassword(
      email: '${username.trim().toLowerCase()}@$usernameDomain',
      password: normalizeRecoveryCode(recoveryCode),
    );
  }

  /// Creates a username account (needs a Log invite code; the server adds
  /// them to that Log) and returns its recovery code. Doesn't sign in, so
  /// the code can be shown first; call [signInWithUsername] after.
  /// Throws [AuthFlowException] with a message fit to show.
  Future<String> signUpWithUsername({
    required String username,
    required String inviteCode,
    String? displayName,
  }) async {
    try {
      final res = await _client.functions.invoke('username-signup', body: {
        'username': username.trim().toLowerCase(),
        'invite_code': inviteCode.trim().toUpperCase(),
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      });
      final code = (res.data as Map?)?['recovery_code'] as String?;
      if (code == null) throw AuthFlowException("Couldn't create the account");
      return code;
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      throw AuthFlowException(msg ?? "Couldn't create the account");
    }
  }

  /// Replaces the recovery code of the signed-in username account; the old
  /// one stops working. Returns the new code to show once.
  Future<String> resetRecoveryCode() async {
    final code = newRecoveryCode();
    await _client.auth.updateUser(UserAttributes(password: code));
    return code;
  }

  /// Deletes the account and everything in it, then signs out locally.
  Future<void> deleteAccount() async {
    await ReminderService.instance.forgetThisDevice();
    try {
      await _client.functions.invoke('delete-account');
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      throw AuthFlowException(msg ?? "Couldn't delete the account");
    }
    // The server already removed the user; just drop the local session.
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  /// Sends a 6-digit OTP code to the given email.
  Future<void> sendOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: true,
    );
  }

  /// Verifies the OTP code. On success, the session is established
  /// and [authStateChanges] fires with a signedIn event.
  Future<AuthResponse> verifyOtp({
    required String email,
    required String code,
  }) async {
    return await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.email,
    );
  }

  Future<void> signOut() async {
    // While still signed in, so RLS lets us delete our own token row.
    await ReminderService.instance.forgetThisDevice();
    await _client.auth.signOut();
  }
}

class AuthFlowException implements Exception {
  AuthFlowException(this.message);
  final String message;

  @override
  String toString() => message;
}
