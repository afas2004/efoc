import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import 'recovery_code_screen.dart';
import 'what_we_store_screen.dart';

/// Sign up with just a username (needs a Log invite code), or sign in on
/// another device with username + recovery code. No email either way.
class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key, this.signUp = true});

  /// Open on "join" (true) or "sign in with recovery code" (false).
  final bool signUp;

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _recovery = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _signUp = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _signUp = widget.signUp;
    // Arrived through an invite link: fill the code in for them.
    final pending = context.read<AppState>().pendingInviteCode;
    if (pending != null && pending.isNotEmpty) _code.text = pending;
  }

  @override
  void dispose() {
    _username.dispose();
    _recovery.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final appState = context.read<AppState>();
    try {
      if (_signUp) {
        final username = _username.text.trim().toLowerCase();
        final code = await AuthService.instance.signUpWithUsername(
          username: username,
          inviteCode: _code.text,
          displayName: _name.text,
        );
        // The server already put them in that Log.
        if (appState.pendingInviteCode?.toUpperCase() ==
            _code.text.trim().toUpperCase()) {
          appState.clearPendingInviteCode();
        }
        if (!mounted) return;
        // Show the code before signing in: signing in swaps to home.
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecoveryCodeScreen(
              code: code,
              username: username,
              onDone: () => AuthService.instance.signInWithUsername(
                username: username,
                recoveryCode: code,
              ),
            ),
          ),
        );
      } else {
        await AuthService.instance.signInWithUsername(
          username: _username.text,
          recoveryCode: _recovery.text,
        );
      }
      // AuthGate takes over from here.
    } on AuthException catch (e) {
      _fail(e.message.toLowerCase().contains('invalid login')
          ? 'Wrong username or recovery code'
          : e.message);
    } catch (e) {
      _fail('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: EfocColors.danger),
    );
  }

  InputDecoration _field(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: EfocColors.textFaint, fontSize: 15),
        filled: true,
        fillColor: EfocColors.surface,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: EfocColors.accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      );

  @override
  Widget build(BuildContext context) {
    const input = TextStyle(color: Colors.white, fontSize: 15);

    return Scaffold(
      backgroundColor: EfocColors.bg,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            children: [
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: EfocColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _signUp ? 'Join with a username' : 'Sign in on a new device',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _signUp
                    ? 'Just pick a username. You\'ll need an invite code from a friend.'
                    : 'Use the recovery code you saved when you joined.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),

              if (_signUp) ...[
                TextFormField(
                  controller: _code,
                  style: input,
                  cursorColor: EfocColors.accent,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _field('Invite code'),
                  validator: (v) => (v ?? '').trim().length == 6
                      ? null
                      : 'Invite codes are 6 characters',
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _username,
                style: input,
                cursorColor: EfocColors.accent,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: _field('Username'),
                validator: (v) {
                  final value = (v ?? '').trim().toLowerCase();
                  if (value.isEmpty) return 'Enter a username';
                  if (!AuthService.usernamePattern.hasMatch(value)) {
                    return '3–20 letters, numbers or _';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              if (!_signUp)
                TextFormField(
                  controller: _recovery,
                  style: input,
                  cursorColor: EfocColors.accent,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  autofillHints: const [AutofillHints.password],
                  decoration: _field('Recovery code (XXXX-XXXX-XXXX)'),
                  validator: (v) =>
                      AuthService.normalizeRecoveryCode(v ?? '').length == 12
                          ? null
                          : 'Recovery codes are 12 letters and numbers',
                ),

              if (_signUp)
                TextFormField(
                  controller: _name,
                  style: input,
                  cursorColor: EfocColors.accent,
                  decoration: _field('Display name (optional)'),
                ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EfocColors.accent,
                    disabledBackgroundColor:
                        EfocColors.accent.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _signUp ? 'Join' : 'Sign in',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() => _signUp = !_signUp),
                  child: Text(
                    _signUp
                        ? 'New phone? Sign in with your recovery code'
                        : 'New here? Join with an invite code',
                    style: TextStyle(color: EfocColors.accentBright),
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const WhatWeStoreScreen()),
                  ),
                  child: const Text(
                    'What we store',
                    style: TextStyle(color: EfocColors.textMuted),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
