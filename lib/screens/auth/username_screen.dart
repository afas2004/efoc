import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import 'what_we_store_screen.dart';

/// Sign in or sign up with a username and password, no email.
/// Signing up needs a Log invite code.
class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _signUp = false;
  bool _loading = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    // Arrived through an invite link: they're most likely new.
    final pending = context.read<AppState>().pendingInviteCode;
    if (pending != null && pending.isNotEmpty) {
      _code.text = pending;
      _signUp = true;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
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
        await AuthService.instance.signUpWithUsername(
          username: _username.text,
          password: _password.text,
          inviteCode: _code.text,
          displayName: _name.text,
        );
        // The server already put them in that Log.
        if (appState.pendingInviteCode?.toUpperCase() ==
            _code.text.trim().toUpperCase()) {
          appState.clearPendingInviteCode();
        }
      } else {
        await AuthService.instance.signInWithUsername(
          username: _username.text,
          password: _password.text,
        );
      }
      // AuthGate takes over from here.
    } on AuthException catch (e) {
      _fail(e.message.toLowerCase().contains('invalid login')
          ? 'Wrong username or password'
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
                _signUp ? 'Join without email' : 'Sign in with username',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _signUp
                    ? 'No email needed. You\'ll need an invite code from a friend.'
                    : 'For accounts made without an email.',
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

              TextFormField(
                controller: _password,
                style: input,
                cursorColor: EfocColors.accent,
                obscureText: !_showPassword,
                autofillHints: [
                  _signUp ? AutofillHints.newPassword : AutofillHints.password,
                ],
                decoration: _field(
                  'Password',
                  suffix: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: EfocColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) {
                  final value = v ?? '';
                  if (value.isEmpty) return 'Enter a password';
                  if (_signUp && value.length < 8) {
                    return 'At least 8 characters';
                  }
                  return null;
                },
              ),

              if (_signUp) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  style: input,
                  cursorColor: EfocColors.accent,
                  decoration: _field('Display name (optional)'),
                ),
                const SizedBox(height: 12),
                Text(
                  'There\'s no email to reset your password, so keep it '
                  'somewhere safe. If you forget it, ask whoever runs Efoc.',
                  style: TextStyle(
                    color: EfocColors.warning.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],

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
                          _signUp ? 'Create account' : 'Sign in',
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
                        ? 'Already have an account? Sign in'
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
