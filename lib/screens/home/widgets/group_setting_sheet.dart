import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/member.dart';
import 'profile/qr_sheet.dart';
import '../../../services/group_service.dart';
import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

class GroupSettingsSheet extends StatefulWidget {
  const GroupSettingsSheet({super.key});

  @override
  State<GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

/// Turns an exception into something a person can read. The raw text
/// still goes to the debug console.
String _friendly(Object e, String fallback) {
  debugPrint('Group settings error: $e');
  final msg = '$e'.toLowerCase();
  if (msg.contains('socket') ||
      msg.contains('network') ||
      msg.contains('failed host lookup') ||
      msg.contains('clientexception')) {
    return 'No connection. Check your internet and try again.';
  }
  return fallback;
}

class _GroupSettingsSheetState extends State<GroupSettingsSheet> {
  String? _code;
  bool _loading = true;
  String? _error;
  bool _copied = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = context.read<AppState>();
      final code = await GroupService.instance.fetchInviteCode(
        state.currentGroup.id,
      );
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e, "Couldn't load the invite code.");
        _loading = false;
      });
    }
  }

  Future<void> _copy() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _code!));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _openQr() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const QrSheet(),
    );
  }

  Future<void> _rename() async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: state.currentGroup.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Rename Log',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Log name',
            hintStyle: const TextStyle(color: Colors.white38),
            counterStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: EfocColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(
              'Rename',
              style: TextStyle(color: EfocColors.accentBright),
            ),
          ),
        ],
      ),
    );

    controller.dispose();
    if (newName == null || newName.isEmpty) return;
    if (newName == state.currentGroup.name) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await state.renameCurrentGroup(newName);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e, "Couldn't rename the Log. Try again.");
      });
    }
  }

  Future<void> _leave() async {
    final confirmed = await _confirm(
      title: 'Leave Log?',
      body:
          'You will stop seeing clips from this Log. You can rejoin with the invite code.',
      action: 'Leave',
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final state = context.read<AppState>();
      await state.leaveCurrentGroup();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e, "Couldn't leave the Log. Try again.");
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      title: 'Delete Log?',
      body:
          'This permanently removes the Log, its members, and all clips. Nobody can undo this.',
      action: 'Delete',
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final state = context.read<AppState>();
      await state.deleteCurrentGroup();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e, "Couldn't delete the Log. Try again.");
      });
    }
  }

  Future<void> _memberActions(EfocMember m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: EfocColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  m.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.workspace_premium_outlined,
                  color: EfocColors.accentBright,
                ),
                title: const Text(
                  'Make owner',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  "They can rename or delete the Log. You'll be a member.",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => Navigator.of(ctx).pop('owner'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: EfocColors.danger,
                ),
                title: const Text(
                  'Remove from Log',
                  style: TextStyle(color: EfocColors.danger),
                ),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    final isTransfer = action == 'owner';
    final ok = await _confirm(
      title: isTransfer ? 'Make ${m.name} the owner?' : 'Remove ${m.name}?',
      body: isTransfer
          ? "You'll become a regular member and can then leave the Log."
          : "They'll stop seeing this Log. Their clips stay. They could "
                'rejoin with the invite code.',
      action: isTransfer ? 'Make owner' : 'Remove',
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      if (isTransfer) {
        await state.transferCurrentGroup(m.id);
      } else {
        await state.removeMemberFromCurrentGroup(m.id);
      }
    } catch (e) {
      if (mounted) {
        _error = _friendly(
          e,
          isTransfer
              ? "Couldn't hand over the Log. Try again."
              : "Couldn't remove them. Try again.",
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              action,
              style: const TextStyle(color: EfocColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final group = state.currentGroup;
    final isOwner = state.isCurrentGroupOwner;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: SingleChildScrollView(
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
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    group.name,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _busy ? null : _rename,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${group.members.length} member${group.members.length == 1 ? "" : "s"}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 24),
            const Text(
              'INVITE CODE',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white30,
                    ),
                  ),
                ),
              )
            else if (_error != null && _code == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: EfocColors.danger,
                    fontSize: 12,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: EfocColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _copied
                        ? EfocColors.success
                        : Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _code ?? '------',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 8,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _copy,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          _copied ? Icons.check : Icons.copy_rounded,
                          color: _copied ? EfocColors.success : Colors.white54,
                          size: 20,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _openQr,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.qr_code_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Share this code with friends. They enter it in "Create or join a Log".',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 24),
            const Text(
              'MEMBERS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            for (final m in group.members)
              InkWell(
                onTap: isOwner && !m.isMe && !_busy
                    ? () => _memberActions(m)
                    : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: m.color,
                          shape: BoxShape.circle,
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: (m.avatarUrl?.isNotEmpty ?? false)
                            ? Image.network(
                                m.avatarUrl!,
                                width: 30,
                                height: 30,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _MemberInitial(m),
                              )
                            : _MemberInitial(m),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          m.isMe ? 'You' : m.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (m.id == group.ownerId)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: EfocColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'OWNER',
                            style: TextStyle(
                              color: EfocColors.accentBright,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      if (isOwner && !m.isMe)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: Colors.white38,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 32),
            const Divider(color: Colors.white12),
            const SizedBox(height: 16),

            if (!isOwner)
              _DangerButton(
                label: _busy ? 'Leaving…' : 'Leave Log',
                onTap: _busy ? null : _leave,
              ),
            if (isOwner) ...[
              _DangerButton(
                label: _busy ? 'Working…' : 'Delete Log',
                onTap: _busy ? null : _delete,
              ),
              if (group.members.length > 1)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Want to leave instead? Tap a member and make them the '
                    'owner first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
            ],

            if (_error != null && _code != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: EfocColors.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberInitial extends StatelessWidget {
  final EfocMember member;

  const _MemberInitial(this.member);

  @override
  Widget build(BuildContext context) {
    final name = member.name;
    return Text(
      member.isMe ? 'Y' : (name.isEmpty ? '?' : name[0].toUpperCase()),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _DangerButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: EfocColors.danger.withValues(alpha: disabled ? 0.15 : 0.12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: EfocColors.danger.withValues(alpha: disabled ? 0.2 : 0.5),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: EfocColors.danger.withValues(alpha: disabled ? 0.5 : 1),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
