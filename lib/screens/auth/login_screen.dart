import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import 'check_email_screen.dart';
import 'username_screen.dart';
import 'what_we_store_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await AuthService.instance.sendOtp(_emailController.text.trim());
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CheckEmailScreen(email: _emailController.text.trim()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send code: $e'),
          backgroundColor: EfocColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openUsername(bool signUp) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UsernameScreen(signUp: signUp)));
  }

  /// Shown when the app was opened from an invite link
  /// (efoc.party/join?code=...): the code is already remembered, so the
  /// quickest way in is a username account with it filled in.
  Widget _inviteCard(String code) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    decoration: BoxDecoration(
      color: EfocColors.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: EfocColors.accent.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'You’re invited to a Log',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Invite code $code. Join with just a username, no email '
          'needed. Already have an account? Sign in below and you’ll '
          'be asked to join.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: _loading ? null : () => _openUsername(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: EfocColors.accent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(23),
              ),
            ),
            child: const Text(
              'Join with just a username',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final invite = context.watch<AppState>().pendingInviteCode;
    final invited = invite != null && invite.isNotEmpty;

    return Scaffold(
      backgroundColor: EfocColors.bg,
      body: SafeArea(
        // Scrolls on short screens (the invite card makes it taller); the
        // Spacers still spread things out when there's room.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(flex: 2),

                        // Logo + name
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 64,
                                color: EfocColors.accent,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Efoc',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Private vlogs for you and your friends',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        const Spacer(flex: 2),

                        if (invited) ...[
                          _inviteCard(invite),
                          const SizedBox(height: 24),
                        ],

                        // Email label
                        const Text(
                          'Continue with email',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Email input
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          cursorColor: EfocColors.accent,
                          decoration: InputDecoration(
                            hintText: 'you@example.com',
                            hintStyle: const TextStyle(
                              color: EfocColors.textFaint,
                              fontSize: 15,
                            ),
                            filled: true,
                            fillColor: EfocColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: EfocColors.accent,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 18,
                            ),
                          ),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Enter your email';
                            final ok = RegExp(
                              r'^[\w\.\-\+]+@[\w\-]+\.[\w\-\.]+$',
                            ).hasMatch(value);
                            if (!ok) return 'Enter a valid email';
                            if (AuthService.isUsernameEmail(value)) {
                              return 'Use "No email?" below';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Send button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _sendOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: EfocColors.accent,
                              disabledBackgroundColor: EfocColors.accent
                                  .withValues(alpha: 0.4),
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
                                : const Text(
                                    'Send code',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        Center(
                          child: Text(
                            'We\'ll email you a 6-digit code to sign in. No password needed.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 11,
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // The invite card already offers this.
                        if (!invited)
                          Center(
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => _openUsername(true),
                              child: Text(
                                'No email? Join with just a username',
                                style: TextStyle(
                                  color: EfocColors.accentBright,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        Center(
                          child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => _openUsername(false),
                            child: Text(
                              'Have a recovery code? Sign in',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const WhatWeStoreScreen(),
                              ),
                            ),
                            child: const Text(
                              'What we store',
                              style: TextStyle(
                                color: EfocColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),

                        const Spacer(flex: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
