import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class CreateJoinSheet extends StatefulWidget {
  final String? initialCode;

  const CreateJoinSheet({super.key, this.initialCode});

  @override
  State<CreateJoinSheet> createState() => _CreateJoinSheetState();
}

class _CreateJoinSheetState extends State<CreateJoinSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  int _tab = 0; // 0 = create, 1 = join
  bool _busy = false;
  String? _error;

  // Preview state for the join tab.
  Map<String, dynamic>? _preview;
  bool _previewLoading = false;
  String? _previewError;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();

    final seed = widget.initialCode?.trim().toUpperCase();
    if (seed != null && seed.isNotEmpty) {
      _tab = 1;
      _codeController.text = seed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchPreview();
      });
    }

    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _codeController.removeListener(_onCodeChanged);
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    _previewDebounce?.cancel();
    final code = _codeController.text.trim();
    if (code.length != 6) {
      if (_preview != null || _previewError != null || _previewLoading) {
        setState(() {
          _preview = null;
          _previewError = null;
          _previewLoading = false;
        });
      }
      return;
    }
    _previewDebounce = Timer(
      const Duration(milliseconds: 350),
      _fetchPreview,
    );
  }

  Future<void> _fetchPreview() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) return;

    setState(() {
      _previewLoading = true;
      _previewError = null;
    });

    try {
      final res = await Supabase.instance.client.rpc(
        'preview_group_by_code',
        params: {'p_code': code},
      );
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _preview = null;
          _previewLoading = false;
          _previewError = 'No group found with that code';
        });
      } else {
        setState(() {
          _preview = Map<String, dynamic>.from(res as Map);
          _previewLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewLoading = false;
        _previewError = 'Could not load group';
      });
    }
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

  bool get _isAlreadyMember =>
      _preview != null && (_preview!['is_member'] as bool? ?? false);

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
                autofocus: widget.initialCode == null,
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
              if (_previewLoading) ...[
                const SizedBox(height: 12),
                const _PreviewSkeleton(),
              ] else if (_preview != null) ...[
                const SizedBox(height: 12),
                _PreviewCard(preview: _preview!),
              ] else if (_previewError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _previewError!,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
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
              onTap: _busy || _isAlreadyMember
                  ? null
                  : (_tab == 0 ? _create : _join),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: _busy || _isAlreadyMember
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
                        _isAlreadyMember
                            ? 'Already a member'
                            : (_tab == 0 ? 'Create' : 'Join'),
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

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white24,
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final Map<String, dynamic> preview;

  const _PreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final name = preview['name'] as String? ?? 'Unnamed group';
    final count = preview['member_count'] as int? ?? 0;
    final members = (preview['members'] as List?) ?? const [];
    final isMember = preview['is_member'] as bool? ?? false;

    final names = members
        .map((m) => (m as Map)['display_name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMember ? EfocColors.accent : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.people_outline,
                size: 14,
                color: Colors.white54,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (members.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _AvatarStack(members: members),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _memberSummary(names, count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (isMember) ...[
            const SizedBox(height: 10),
            Text(
              "You're already in this group",
              style: TextStyle(
                color: EfocColors.accentBright,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _memberSummary(List<String> names, int total) {
    if (names.isEmpty) return '';
    if (names.length == 1 && total <= 1) return names.first;
    final shown = names.take(3).join(', ');
    final remaining = total - names.take(3).length;
    if (remaining <= 0) return shown;
    return '$shown and $remaining ${remaining == 1 ? 'other' : 'others'}';
  }
}

class _AvatarStack extends StatelessWidget {
  final List members;

  const _AvatarStack({required this.members});

  @override
  Widget build(BuildContext context) {
    const size = 26.0;
    const overlap = 8.0;
    final shown = members.take(4).toList();
    final width = shown.isEmpty
        ? 0.0
        : size + (shown.length - 1) * (size - overlap);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: EfocColors.surface,
                    width: 2,
                  ),
                ),
                child: _Avatar(member: shown[i] as Map),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Map member;

  const _Avatar({required this.member});

  @override
  Widget build(BuildContext context) {
    final url = member['avatar_url'] as String?;
    final name = (member['display_name'] as String?) ?? '';

    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 22,
          height: 22,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initial(name),
        ),
      );
    }
    return _initial(name);
  }

  Widget _initial(String name) {
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      color: EfocColors.accent.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
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