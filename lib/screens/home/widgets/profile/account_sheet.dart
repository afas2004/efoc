import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/profile_service.dart';
import '../../../../theme/colors.dart';

enum _SaveStatus { idle, saving, saved, error }

class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final _nameController = TextEditingController();
  final _focusNode = FocusNode();

  late final String _userId;
  String _savedName = '';
  String _username = '';
  String _email = '';
  bool _loading = true;

  Timer? _debounce;
  int _saveVersion = 0;
  _SaveStatus _status = _SaveStatus.idle;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    _email = Supabase.instance.client.auth.currentUser?.email ?? '';
    _nameController.addListener(_onNameChanged);
    _focusNode.addListener(_onFocusChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.removeListener(_onNameChanged);
    _focusNode.removeListener(_onFocusChanged);

    // Fire-and-forget final save if the last typed value differs.
    final current = _nameController.text.trim();
    if (current.isNotEmpty && current != _savedName && _userId.isNotEmpty) {
      ProfileService.instance.updateDisplayName(
        targetUserId: _userId,
        displayName: current,
      );
    }

    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await ProfileService.instance.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        if (profile != null) {
          _savedName = (profile['display_name'] as String?) ?? '';
          _username = (profile['username'] as String?) ?? '';
          _nameController.text = _savedName;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onNameChanged() {
    final trimmed = _nameController.text.trim();
    if (trimmed == _savedName) {
      // Nothing meaningful changed — reset status.
      if (_status != _SaveStatus.idle) {
        setState(() => _status = _SaveStatus.idle);
      }
      return;
    }
    if (_status != _SaveStatus.idle) {
      setState(() => _status = _SaveStatus.idle);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _save);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // User blurred the field — commit immediately.
      _debounce?.cancel();
      _save();
    }
  }

  Future<void> _save() async {
    // Auth must still match the captured id.
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != _userId) return;

    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty || trimmed == _savedName) return;

    final myVersion = ++_saveVersion;
    setState(() => _status = _SaveStatus.saving);

    try {
      final result = await ProfileService.instance.updateDisplayName(
        targetUserId: _userId,
        displayName: trimmed,
      );

      if (!mounted) return;
      // A newer save has started — ignore this result.
      if (_saveVersion != myVersion) return;

      if (result == null) {
        setState(() => _status = _SaveStatus.error);
        return;
      }

      setState(() {
        _savedName = trimmed;
        _status = _SaveStatus.saved;
      });
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted && _saveVersion == myVersion) {
          setState(() => _status = _SaveStatus.idle);
        }
      });
    } catch (_) {
      if (!mounted) return;
      if (_saveVersion != myVersion) return;
      setState(() => _status = _SaveStatus.error);
    }
  }

  Widget _statusIcon() {
    switch (_status) {
      case _SaveStatus.idle:
        return const SizedBox(width: 16, height: 16);
      case _SaveStatus.saving:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: EfocColors.textMuted,
          ),
        );
      case _SaveStatus.saved:
        return const Icon(
          Icons.check_rounded,
          size: 16,
          color: EfocColors.success,
        );
      case _SaveStatus.error:
        return const Icon(
          Icons.error_outline_rounded,
          size: 16,
          color: EfocColors.danger,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: EfocColors.sheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Account',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),

            // Display name
            const Text(
              'DISPLAY NAME',
              style: TextStyle(
                color: EfocColors.textFaint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: EfocColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      focusNode: _focusNode,
                      enabled: !_loading,
                      maxLength: 30,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Your name',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontWeight: FontWeight.w500,
                        ),
                        counterText: '',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 14),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        _debounce?.cancel();
                        _save();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  _statusIcon(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _username.isEmpty ? '' : '@$_username',
              style: const TextStyle(
                color: EfocColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),

            // Email (read-only)
            const Text(
              'EMAIL',
              style: TextStyle(
                color: EfocColors.textFaint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: EfocColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _email.isEmpty ? '—' : _email,
                style: const TextStyle(
                  color: EfocColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Signed in via one-time code. No password to change.',
              style: TextStyle(
                color: EfocColors.textFaint,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}