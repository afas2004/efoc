import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class CreateJoinSheet extends StatefulWidget {
  const CreateJoinSheet({super.key});

  @override
  State<CreateJoinSheet> createState() => _CreateJoinSheetState();
}

class _CreateJoinSheetState extends State<CreateJoinSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  int _tab = 0; // 0 = create, 1 = join
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final state = context.read<AppState>();
    await _run(() => state.createGroupAndReload(name));
  }

  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character code');
      return;
    }
    final state = context.read<AppState>();
    await _run(() => state.joinGroupAndReload(code));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Tabs
            Row(
              children: [
                _Tab(
                  label: 'Create',
                  active: _tab == 0,
                  onTap: () => setState(() {
                    _tab = 0;
                    _error = null;
                  }),
                ),
                const SizedBox(width: 8),
                _Tab(
                  label: 'Join',
                  active: _tab == 1,
                  onTap: () => setState(() {
                    _tab = 1;
                    _error = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (_tab == 0) ...[
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 30,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  hint: 'Log name',
                  counter: true,
                ),
                onSubmitted: (_) => _busy ? null : _create(),
              ),
            ] else ...[
              TextField(
                controller: _codeController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[A-Za-z0-9]'),
                  ),
                  UpperCaseTextFormatter(),
                ],
                style: const TextStyle(
                  color: Colors.white,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _inputDecoration(
                  hint: 'ABC123',
                  counter: true,
                ),
                onSubmitted: (_) => _busy ? null : _join(),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: EfocColors.danger,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),

            GestureDetector(
              onTap: _busy ? null : (_tab == 0 ? _create : _join),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: _busy
                      ? EfocColors.accent.withValues(alpha: 0.4)
                      : EfocColors.accent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _tab == 0 ? 'Create' : 'Join',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    bool counter = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      counterStyle: counter
          ? const TextStyle(color: Colors.white24)
          : null,
      filled: true,
      fillColor: EfocColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? EfocColors.accent.withValues(alpha: 0.15)
              : EfocColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? EfocColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? EfocColors.accentBright : Colors.white54,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}