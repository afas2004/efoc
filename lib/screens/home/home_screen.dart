import 'package:efoc/screens/capture/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_screen.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  final LayerLink _groupLink = LayerLink();
  final LayerLink _dlLink = LayerLink();
  final PageController _hourController = PageController();

  OverlayEntry? _groupOverlay;
  OverlayEntry? _dlOverlay;

  void _closeAllOverlays() {
    _groupOverlay?.remove();
    _groupOverlay = null;
    _dlOverlay?.remove();
    _dlOverlay = null;
  }

    void _openChat() {
    final state = context.read<AppState>();
    if (!state.hasGroups) return;
    final group = state.currentGroup;

    Navigator.of(context).push(
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
      ),
    );
    Overlay.of(context).insert(_dlOverlay!);
  }

  void _openProfile() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ProfileSheet(),
    );
  }

  void _openCreateJoin() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const CreateJoinSheet(),
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
    _closeAllOverlays();
    _hourController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final needsInitialLoad = state.isLoadingGroups ||
        (state.hasGroups && !state.clipsLoadedOnce);

    if (needsInitialLoad) {
      return const Scaffold(
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
      );
    }

    if (state.groupsError != null) {
      return Scaffold(
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
      );
    }

    if (!state.hasGroups) {
      return Scaffold(
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
                    child: const Icon(
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
      );
    }

    return GestureDetector(
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
    );
  }
}