import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isLoggedIn => currentSession != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

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
    await _client.auth.signOut();
  }

  // Kept for compatibility — no longer used but might be referenced elsewhere.
  // Can delete once you've confirmed nothing else calls it.
  String _redirectUrl() {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return origin.isEmpty ? 'http://localhost:3000' : origin;
    }
    return 'io.supabase.efoc://login-callback';
  }
}