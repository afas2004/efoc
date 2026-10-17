import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/colors.dart';
import '../version.dart';

/// Runs the update check inside its own popup, so the result shows on top
/// of whatever sheet opened it (a snackbar would sit underneath).
Future<void> showUpdateCheckDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (_) => const _UpdateCheckDialog(),
  );
}

class _UpdateCheckDialog extends StatefulWidget {
  const _UpdateCheckDialog();

  @override
  State<_UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

class _UpdateCheckDialogState extends State<_UpdateCheckDialog> {
  UpdateResult? _result;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _result = null);
    final result = await UpdateService.instance.check();
    if (mounted) setState(() => _result = result);
  }

  Future<void> _update() async {
    setState(() => _reloading = true);
    await UpdateService.instance.reload();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    final Widget icon;
    final String title;
    final String message;
    String? primary;
    VoidCallback? onPrimary;

    if (result == null) {
      icon = SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: EfocColors.accentBright,
        ),
      );
      title = 'Checking for updates…';
      message = 'You have v$kAppVersion ($kAppBuild).';
    } else {
      switch (result.status) {
        case UpdateStatus.upToDate:
          icon = const Icon(
            Icons.check_circle_rounded,
            color: EfocColors.success,
            size: 30,
          );
          title = "You're up to date";
          message = 'v$kAppVersion ($kAppBuild) is the latest version.';
        case UpdateStatus.updateAvailable:
          icon = Icon(
            Icons.system_update_alt_rounded,
            color: EfocColors.accentBright,
            size: 30,
          );
          title = 'Version ${result.latestVersion} is available';
          message = result.releaseNotes.isEmpty
              ? 'You have v$kAppVersion. Update to get the latest changes.'
              : result.releaseNotes;
          primary = _reloading ? 'Updating…' : 'Update now';
          onPrimary = _reloading ? null : _update;
        case UpdateStatus.failed:
          icon = const Icon(
            Icons.wifi_off_rounded,
            color: EfocColors.warning,
            size: 30,
          );
          title = "Couldn't check for updates";
          message = 'Check your connection and try again.';
          primary = 'Try again';
          onPrimary = _check;
      }
    }

    return Dialog(
      backgroundColor: EfocColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 32, child: Center(child: icon)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            if (primary != null) ...[
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EfocColors.accent,
                    disabledBackgroundColor:
                        EfocColors.accent.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    primary,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed:
                    _reloading ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: EfocColors.surface2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  primary == null ? 'OK' : 'Not now',
                  style: const TextStyle(
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
