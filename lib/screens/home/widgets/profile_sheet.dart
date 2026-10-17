import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../state/app_state.dart';
import '../../../services/auth_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/reminder_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/theme_controller.dart';
import '../../../version.dart';
import '../../../widgets/update_check_dialog.dart';
import 'profile/account_sheet.dart';
import 'profile/avatar_crop_sheet.dart';
import 'profile/avatar_source_sheet.dart';
import 'profile/export_sheet.dart';
import 'profile/qr_sheet.dart';
import 'profile/theme_sheet.dart';

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  // ---------- preferences ----------
  bool _reminders = false;
  bool _remindersBusy = false;

  String _theme = ThemeController.instance.name;
  bool _autoStitch = true;

  String _displayName = 'You';
  String _handle = '';
  String? _avatarUrl;

  bool _loadingProfile = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    try {
      final on = await ReminderService.instance.fetchEnabled();
      if (mounted) setState(() => _reminders = on);
    } catch (_) {
      // Leave it off; flipping it will retry.
    }
  }

  Future<void> _toggleReminders(bool on) async {
    if (_remindersBusy) return;
    setState(() {
      _remindersBusy = true;
      _reminders = on; // optimistic
    });

    if (!on) {
      try {
        await ReminderService.instance.disable();
      } catch (_) {
        if (mounted) {
          setState(() => _reminders = true);
          _showNotice("Couldn't turn reminders off", 'Please try again.');
        }
      }
      if (mounted) setState(() => _remindersBusy = false);
      return;
    }

    final result = await ReminderService.instance.enable();
    if (!mounted) return;
    setState(() {
      _remindersBusy = false;
      _reminders = result == ReminderResult.enabled;
    });

    switch (result) {
      case ReminderResult.enabled:
        break;
      case ReminderResult.denied:
        _showNotice(
          'Notifications are blocked',
          'Allow notifications for efoc.party in your browser settings, '
              'then turn this on again.',
        );
      case ReminderResult.unsupported:
        _showNotice(
          "Reminders don't work here",
          'On iPhone, add efoc to your Home Screen (Share → Add to Home '
              'Screen) and open it from there. On other devices, try Chrome.',
        );
      case ReminderResult.notConfigured:
        _showNotice(
          'Reminders aren\'t set up yet',
          'The web push key is missing from this build.',
        );
      case ReminderResult.failed:
        final detail = ReminderService.instance.lastError;
        _showNotice(
          "Couldn't turn reminders on",
          'Please try again.'
              '${detail == null ? '' : '\n\nDetails: $detail'}',
        );
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.instance.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        if (profile != null) {
          _displayName =
              (profile['display_name'] as String?) ??
                  (profile['username'] as String?) ??
                  'You';
          _handle = '@${profile['username'] ?? _displayName.toLowerCase()}';
          _avatarUrl = profile['avatar_url'] as String?;
        }
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  // ---------- actions ----------

  Future<void> _openThemePicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ThemeSheet(current: _theme),
    );
    if (result != null && mounted) {
      await ThemeController.instance.set(result);
      if (mounted) setState(() => _theme = result);
    }
  }

  Future<void> _openExportSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ExportSheet(),
    );
  }

  Future<void> _openAccountSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const AccountSheet(),
    );
    if (!mounted) return;

    // Sheet no longer returns values — it saves directly.
    // Reload the identity row and refresh group members so the grid
    // picks up the new display name.
    await _loadProfile();
    if (!mounted) return;
    context.read<AppState>().refresh();
  }

  Future<void> _openAvatarPicker() async {
    // 1. Pick a source and let image_picker return an XFile.
    final XFile? file = await showModalBottomSheet<XFile>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const AvatarSourceSheet(),
    );
    if (file == null || !mounted) return;

    // 2. Load the bytes.
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      _showNotice('Could not read that image', 'Try a different photo.');
      return;
    }
    if (!mounted) return;

    // 3. Crop.
    final Uint8List? cropped = await showModalBottomSheet<Uint8List>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AvatarCropSheet(imageBytes: bytes),
    );
    if (cropped == null || !mounted) return;

    // 4. Upload + update profile.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final url = await ProfileService.instance.uploadAvatar(
        targetUserId: userId,
        bytes: cropped,
      );
      if (!mounted) return;
      if (url == null) {
        _showNotice('Could not save your photo', 'Please try again.');
        return;
      }
      setState(() => _avatarUrl = url);
      context.read<AppState>().refresh();
    } catch (e) {
      debugPrint('Avatar upload error: $e');
      if (!mounted) return;
      _showNotice(
        'Upload failed',
        'Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// A popup, not a snackbar: snackbars render underneath this sheet.
  void _showNotice(String title, String message) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => AlertDialog(
        backgroundColor: EfocColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'OK',
              style: TextStyle(color: EfocColors.accentBright),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQrSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const QrSheet(),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => const _LogoutConfirmDialog(),
    );

    if (confirmed == true) {
      await AuthService.instance.signOut();
      // AuthGate will rebuild and switch to LoginScreen.
      // This sheet is popped by the rebuild.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
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

              // ---------- Zone 1 — Identity ----------
              _IdentityRow(
                loading: _loadingProfile,
                displayName: _displayName,
                handle: _handle,
                avatarUrl: _avatarUrl,
                uploading: _uploadingAvatar,
                onAvatarTap: _uploadingAvatar ? null : _openAvatarPicker,
                onQrTap: _openQrSheet,
              ),
              const SizedBox(height: 26),

              // ---------- Zone 2 — Preferences ----------
              const _SectionLabel('Preferences'),
              const SizedBox(height: 10),
              _SettingsCard(
                children: [
                  _SettingRow(
                    icon: Icons.notifications_outlined,
                    label: 'Hourly reminders',
                    trailing: _remindersBusy
                        ? const SizedBox(
                            width: 44,
                            height: 26,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: EfocColors.textMuted,
                                ),
                              ),
                            ),
                          )
                        : _EfocToggle(
                            value: _reminders,
                            onChanged: _toggleReminders,
                          ),
                  ),
                  _SettingRow(
                    icon: Icons.palette_outlined,
                    label: 'Theme',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _theme,
                          style: const TextStyle(
                            color: EfocColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          color: EfocColors.textFaint,
                          size: 18,
                        ),
                      ],
                    ),
                    onTap: _openThemePicker,
                  ),
                  _SettingRow(
                    icon: Icons.movie_filter_outlined,
                    label: 'Auto-stitch at midnight',
                    trailing: _EfocToggle(
                      value: _autoStitch,
                      onChanged: (v) => setState(() => _autoStitch = v),
                    ),
                    isLast: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---------- Zone 3 — Content ----------
              const _SectionLabel('Content'),
              const SizedBox(height: 10),
              _SettingsCard(
                children: [
                  _SettingRow(
                    icon: Icons.download_outlined,
                    label: 'Export vlogs',
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: EfocColors.textFaint,
                      size: 18,
                    ),
                    onTap: _openExportSheet,
                  ),
                  _SettingRow(
                    icon: Icons.settings_outlined,
                    label: 'Account',
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: EfocColors.textFaint,
                      size: 18,
                    ),
                    onTap: _openAccountSheet,
                  ),
                  _SettingRow(
                    icon: Icons.system_update_alt_rounded,
                    label: 'Check for updates',
                    trailing: Text(
                      'v$kAppVersion ($kAppBuild)',
                      style: const TextStyle(
                        color: EfocColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    onTap: kIsWeb
                        ? () => showUpdateCheckDialog(context)
                        : null,
                    isLast: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---------- Zone 4 — Danger ----------
              _SettingsCard(
                children: [
                  _SettingRow(
                    icon: Icons.logout_rounded,
                    label: 'Log out',
                    color: EfocColors.danger,
                    trailing: const SizedBox.shrink(),
                    onTap: _confirmLogout,
                    isLast: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Sub-widgets
// ============================================================

class _IdentityRow extends StatelessWidget {
  final bool loading;
  final String displayName;
  final String handle;
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback? onAvatarTap;
  final VoidCallback onQrTap;

  const _IdentityRow({
    required this.loading,
    required this.displayName,
    required this.handle,
    required this.avatarUrl,
    required this.uploading,
    required this.onAvatarTap,
    required this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        displayName.isEmpty ? '?' : displayName[0].toUpperCase();
    final state = context.watch<AppState>();
    final me = state.hasGroups
        ? state.currentGroup.members.where((m) => m.isMe).firstOrNull
        : null;
    final myColor = me?.color ?? EfocColors.accent;

    return Row(
      children: [
        // Avatar
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            // The edit badge sits slightly outside the circle.
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: myColor,
                  image: avatarUrl != null
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: avatarUrl == null
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              if (uploading)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: EfocColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: EfocColors.sheetBg,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.edit,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),

        // Name + handle
        Expanded(
          child: loading
              ? SizedBox(
                  height: 40,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EfocColors.accent,
                      ),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (handle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        handle,
                      style: const TextStyle(
                        color: EfocColors.textMuted,
                        fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
        ),

        // QR button
        GestureDetector(
          onTap: onQrTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: EfocColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: EfocColors.accent.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.qr_code_rounded,
              size: 20,
              color: EfocColors.accentBright,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: EfocColors.textFaint,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;
  final Color? color;
  final bool isLast;

  const _SettingRow({
    required this.icon,
    required this.label,
    required this.trailing,
    this.onTap,
    this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isLast ? Radius.zero : const Radius.circular(16),
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04),
                    width: 1,
                  ),
                ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: color != null
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _EfocToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _EfocToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          color: value ? EfocColors.accent : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(13),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment:
              value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Logout confirmation dialog
// ============================================================

class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: EfocColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Log out?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ll need to sign in again to access your vlogs.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EfocColors.danger,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Log out',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  backgroundColor: EfocColors.surface2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancel',
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
      ),
    );
  }
}