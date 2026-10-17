import 'dart:async';

import 'package:efoc/screens/capture/capture_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/reminder_service.dart';
import '../../services/update_service.dart';
import '../../services/vlog_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import '../../widgets/reminder_banner.dart';
import '../../widgets/update_banner.dart';
import '../chat/chat_screen.dart';
import '../vlog/vlog_viewer_screen.dart';
import 'widgets/clip_popup.dart';
import 'widgets/create_join_sheet.dart';
import 'widgets/download_popover.dart';
import 'widgets/group_dropdown.dart';
import 'widgets/group_setting_sheet.dart';
import 'widgets/home_top_bar.dart';
import 'widgets/hour_dots.dart';
import 'widgets/hour_pager.dart';
import 'widgets/profile_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final LayerLink _groupLink = LayerLink();
  final LayerLink _dlLink = LayerLink();
  final PageController _hourController = PageController();

  OverlayEntry? _groupOverlay;
  OverlayEntry? _dlOverlay;

  /// Guards the invite-link handling so it only fires once per HomeScreen.
  bool _pendingInviteHandled = false;

  // ---------- update check state ----------

  /// Result of the most recent auto-check, non-null means the banner is up.
  UpdateResult? _bannerResult;

  /// Set when the user dismisses the banner. Prevents re-showing it this
  /// session. Reset on page reload, which is fine.
  bool _updateDismissed = false;

  /// Guards against overlapping checks when the app resumes rapidly.
  bool _updateCheckInFlight = false;

  // ---------- in-app reminder ----------
  StreamSubscription<RemoteMessage>? _reminderSub;
  RemoteNotification? _reminder;
  Timer? _reminderTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeHandlePendingInvite();
      _runAutoUpdateCheck();
    });
    _listenForReminders();
  }

  // ---------- in-app reminder ----------

  Future<void> _listenForReminders() async {
    final stream = await ReminderService.instance.foregroundMessages();
    if (stream == null || !mounted) return;
    _reminderSub = stream.listen((message) {
      final n = message.notification;
      if (n == null || !mounted) return;
      _reminderTimer?.cancel();
      setState(() => _reminder = n);
      // Like a heads-up notification: goes away on its own.
      _reminderTimer = Timer(const Duration(seconds: 10), _dismissReminder);
    });
  }

  void _dismissReminder() {
    _reminderTimer?.cancel();
    if (mounted && _reminder != null) setState(() => _reminder = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runAutoUpdateCheck();
      // New clips, messages or a fresh stitch may have landed while away.
      context.read<AppState>().reloadBadges();
    }
  }

  void _closeAllOverlays() {
    _groupOverlay?.remove();
    _groupOverlay = null;
    _dlOverlay?.remove();
    _dlOverlay = null;
  }

  // ---------- update check ----------

  Future<void> _runAutoUpdateCheck() async {
    // Web-only: native builds update via the store, not a page reload.
    if (!kIsWeb) return;
    if (_updateCheckInFlight) return;
    if (_updateDismissed) return;
    _updateCheckInFlight = true;

    final result = await UpdateService.instance.check();
    _updateCheckInFlight = false;

    if (!mounted) return;

    // Silent on up-to-date and on failure for auto checks. Only the manual
    // button surfaces those outcomes.
    if (result.status == UpdateStatus.updateAvailable) {
      setState(() => _bannerResult = result);
    }
  }

  void _dismissUpdateBanner() {
    setState(() {
      _updateDismissed = true;
      _bannerResult = null;
    });
  }

  void _applyUpdate() {
    UpdateService.instance.reload();
  }

  /// Wraps any screen state with the floating update banner, or the
  /// reminder banner when a reminder just arrived (it wins: it's timely).
  Widget _withUpdateBanner(Widget child) {
    final reminder = _reminder;
    if (reminder != null) {
      final state = context.read<AppState>();
      final canRecord = state.hasGroups && !state.recordedThisHour;
      return Stack(
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ReminderBanner(
              title: reminder.title ?? 'Time to record',
              body: reminder.body ?? 'Record your 3 seconds for this hour.',
              onRecord: canRecord
                  ? () {
                      _dismissReminder();
                      _openCapture(state.currentHour);
                    }
                  : null,
              onDismiss: _dismissReminder,
            ),
          ),
        ],
      );
    }

    final result = _bannerResult;
    if (result == null) return child;

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: UpdateBanner(
            latestVersion: result.latestVersion,
            releaseNotes: result.releaseNotes,
            onUpdate: _applyUpdate,
            onDismiss: _dismissUpdateBanner,
          ),
        ),
      ],
    );
  }

  // ---------- pending invite ----------

  void _maybeHandlePendingInvite() {
    if (_pendingInviteHandled) return;
    if (!mounted) return;

    final state = context.read<AppState>();
    final code = state.pendingInviteCode;
    if (code == null || code.isEmpty) return;

    _pendingInviteHandled = true;
    state.clearPendingInviteCode();
    _stripInviteParamFromUrl();
    _openCreateJoin(initialCode: code);
  }

  /// Removes ?code=... from the browser URL so a refresh doesn't re-trigger
  /// the join sheet. No-op on non-web.
  void _stripInviteParamFromUrl() {
    if (!kIsWeb) return;
    try {
      final cleaned = Uri.base.replace(path: '/', query: '', fragment: '');
      SystemNavigator.routeInformationUpdated(uri: cleaned, replace: true);
    } catch (_) {
      // Non-fatal — worst case a refresh re-opens the sheet.
    }
  }

  // ---------- navigation ----------

  void _openChat() async {
    final state = context.read<AppState>();
    if (!state.hasGroups) return;
    final group = state.currentGroup;

    state.markChatRead(group.id);

    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ChatScreen(
          groupId: group.id,
          groupName: group.name,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
      ),
    );

    // Messages that arrived while the chat was open were seen there.
    state.markChatRead(group.id);
  }

  void _toggleGroupMenu() {
    if (_groupOverlay != null) {
      _closeAllOverlays();
      return;
    }
    _dlOverlay?.remove();
    _dlOverlay = null;

    _groupOverlay = OverlayEntry(
      builder: (_) => GroupDropdown(
        link: _groupLink,
        onDismiss: _closeAllOverlays,
        onCreateJoin: _openCreateJoin,
        onOpenSettings: _openGroupSettings,
      ),
    );
    Overlay.of(context).insert(_groupOverlay!);
  }

  void _toggleDownloadMenu() {
    if (_dlOverlay != null) {
      _closeAllOverlays();
      return;
    }
    _groupOverlay?.remove();
    _groupOverlay = null;

    _dlOverlay = OverlayEntry(
      builder: (_) => DownloadPopover(
        link: _dlLink,
        onDismiss: _closeAllOverlays,
        onToday: () => openTodayPreview(context),
        onYesterday: _downloadYesterday,
      ),
    );
    Overlay.of(context).insert(_dlOverlay!);
  }

  Future<void> _downloadYesterday() async {
    final state = context.read<AppState>();
    final group = state.currentGroup;
    final vlog = state.yesterdayVlog(group.id);
    final messenger = ScaffoldMessenger.of(context);
    if (vlog == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No yesterday vlog')),
      );
      return;
    }
    state.markVlogViewed(vlog);
    messenger.showSnackBar(const SnackBar(content: Text('Downloading…')));
    try {
      await VlogService.instance.shareVlog(vlog, groupName: group.name);
      messenger.showSnackBar(const SnackBar(content: Text('Saved ✓')));
    } catch (e) {
      debugPrint('Download yesterday error: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Download failed. Try again.')),
      );
    }
  }

  void _openProfile() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ProfileSheet(),
    );
  }

  void _openCreateJoin({String? initialCode}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CreateJoinSheet(initialCode: initialCode),
    );
  }

  void _openGroupSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const GroupSettingsSheet(),
    );
  }

  void _openClipPopup(BuildContext ctx, int memberIdx, int hourIdx) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => ClipPopup(
        initialMemberIdx: memberIdx,
        initialHourIdx: hourIdx,
      ),
    );
  }

  void _openCapture(int hour) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CaptureScreen(hour: hour),
      ),
    );
  }

  void _handleCellTap(int mIdx, int hIdx) {
    final state = context.read<AppState>();
    if (!state.hasGroups) return;
    final group = state.currentGroup;
    if (mIdx < 0 || mIdx >= group.members.length) return;

    final member = group.members[mIdx];
    final filled = state.isCellFilled(mIdx, hIdx, member);

    if (filled) {
      _openClipPopup(context, mIdx, hIdx);
    } else if (member.isMe) {
      _openCapture(state.hours[hIdx]);
    }
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    _reminderTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _closeAllOverlays();
    _hourController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Handles the case where a deep link arrives while Home is already
    // mounted (warm start on Android). Cold start is handled in initState.
    if (state.hasPendingInvite && !_pendingInviteHandled) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeHandlePendingInvite());
    }

    final needsInitialLoad = state.isLoadingGroups ||
        (state.hasGroups && !state.clipsLoadedOnce);

    if (needsInitialLoad) {
      return _withUpdateBanner(
        Scaffold(
          backgroundColor: EfocColors.bg,
          body: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: EfocColors.accent,
              ),
            ),
          ),
        ),
      );
    }

    if (state.groupsError != null) {
      return _withUpdateBanner(
        Scaffold(
          backgroundColor: EfocColors.bg,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                state.groupsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ),
        ),
      );
    }

    if (!state.hasGroups) {
      return _withUpdateBanner(
        Scaffold(
          backgroundColor: EfocColors.bg,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: EfocColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.group_add_outlined,
                        color: EfocColors.accentBright,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'No Logs yet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Create a Log or join one with an invite code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: EfocColors.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      onPressed: _openCreateJoin,
                      child: const Text(
                        'Create or join a Log',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final currentGroupHasUnread = state.hasUnreadChat(state.currentGroup.id);

    return _withUpdateBanner(
      GestureDetector(
        onTap: _closeAllOverlays,
        child: Scaffold(
          backgroundColor: EfocColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                HomeTopBar(
                  groupLink: _groupLink,
                  downloadLink: _dlLink,
                  onToggleGroup: _toggleGroupMenu,
                  onOpenGroupSettings: _openGroupSettings,
                  onToggleDownload: _toggleDownloadMenu,
                  onOpenProfile: _openProfile,
                  onOpenChat: _openChat,
                  chatHasUnread: currentGroupHasUnread,
                ),
                HourDots(controller: _hourController),
                Expanded(
                  child: HourPager(
                    controller: _hourController,
                    onCellTap: _handleCellTap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}