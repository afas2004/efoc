import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../services/group_service.dart';
import '../../../../state/app_state.dart';
import '../../../../theme/colors.dart';

class QrSheet extends StatefulWidget {
  const QrSheet({super.key});

  @override
  State<QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<QrSheet> {
  String? _code;
  String _groupName = '';
  bool _loading = true;
  String? _error;
  bool _copied = false;

  String get _inviteUrl => 'https://efoc.party/join?code=${_code ?? ''}';

  String get _shareMessage =>
      'Join me on Efoc — hourly 2-second vlogs, stitched daily.\n\n$_inviteUrl';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final state = context.read<AppState>();
      final group = state.currentGroup;
      final code = await GroupService.instance.fetchInviteCode(group.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _groupName = group.name;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _copyLink() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _inviteUrl));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _share() async {
    if (_code == null) return;

    if (kIsWeb) {
      // On web, just copy. The Web Share API only exists on mobile
      // browsers and behaves inconsistently elsewhere.
      await Clipboard.setData(ClipboardData(text: _shareMessage));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite copied — paste it anywhere'),
          duration: Duration(milliseconds: 1600),
        ),
      );
      return;
    }

    // Native (Android). Share.share opens the system share sheet.
    await Share.share(_shareMessage, subject: 'Join my Efoc Log');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isPersonal = state.currentGroup.isPersonal;

    return Container(
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          if (isPersonal)
            const _PersonalNotice()
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white30,
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: EfocColors.danger,
                  fontSize: 12,
                ),
              ),
            )
          else
            _InviteContent(
              groupName: _groupName,
              code: _code!,
              inviteUrl: _inviteUrl,
              copied: _copied,
              onCopy: _copyLink,
              onShare: _share,
            ),
        ],
      ),
    );
  }
}

class _PersonalNotice extends StatelessWidget {
  const _PersonalNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: EfocColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 24,
              color: EfocColors.accentBright,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Personal Log',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Only you can post here. Create a shared Log to invite friends.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteContent extends StatelessWidget {
  final String groupName;
  final String code;
  final String inviteUrl;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _InviteContent({
    required this.groupName,
    required this.code,
    required this.inviteUrl,
    required this.copied,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Invite to $groupName',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),

        // QR code
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: QrImageView(
            data: inviteUrl,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Code display
        Text(
          code,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'or scan the QR',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 24),

        // Copy + Share row
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onCopy,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: EfocColors.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: copied
                          ? EfocColors.success
                          : Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        copied ? Icons.check : Icons.link_rounded,
                        size: 16,
                        color: copied
                            ? EfocColors.success
                            : Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        copied ? 'Copied' : 'Copy link',
                        style: TextStyle(
                          color: copied
                              ? EfocColors.success
                              : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: onShare,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: EfocColors.accent,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.ios_share_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Share',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}