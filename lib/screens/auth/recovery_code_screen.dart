import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../theme/colors.dart';

/// Shows a recovery code once. It's the only way back into a username
/// account on another device, and we can't show it again.
class RecoveryCodeScreen extends StatefulWidget {
  const RecoveryCodeScreen({
    super.key,
    required this.code,
    required this.onDone,
    this.username,
  });

  final String code;
  final String? username;

  /// Called after "I saved it". May throw; the message is shown.
  final Future<void> Function() onDone;

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends State<RecoveryCodeScreen> {
  bool _saved = false;
  bool _busy = false;

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      await widget.onDone();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: EfocColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = AuthService.formatRecoveryCode(widget.code);

    return PopScope(
      // Leaving without saving would lose the code for good.
      canPop: false,
      child: Scaffold(
        backgroundColor: EfocColors.bg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            children: [
              const SizedBox(height: 48),
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: EfocColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.key_rounded,
                  size: 40,
                  color: EfocColors.accentBright,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Save your recovery code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You stay signed in on this device. To sign in anywhere else '
                'you\'ll need your username'
                '${widget.username == null ? '' : ' (@${widget.username})'} '
                'and this code. We can\'t show it again, and there\'s no '
                'email to reset it.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: EfocColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: code));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  },
                  icon: Icon(Icons.copy_rounded,
                      size: 16, color: EfocColors.accentBright),
                  label: Text(
                    'Copy',
                    style: TextStyle(color: EfocColors.accentBright),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _saved,
                onChanged: (v) => setState(() => _saved = v ?? false),
                activeColor: EfocColors.accent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I\'ve saved it somewhere safe',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _saved && !_busy ? _done : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EfocColors.accent,
                    disabledBackgroundColor:
                        EfocColors.accent.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
