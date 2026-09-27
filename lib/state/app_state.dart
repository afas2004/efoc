import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/log_group.dart';
import '../models/member.dart';
import '../services/clip_service.dart';
import '../services/group_service.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _listenAuth();
    _init();
  }

  SupabaseClient get _client => Supabase.instance.client;

  // ---------- auth ----------
  StreamSubscription<AuthState>? _authSub;

  void _listenAuth() {
    _authSub = _client.auth.onAuthStateChange.listen((event) {
      debugPrint('AUTH EVENT: ${event.event}');
      switch (event.event) {
        case AuthChangeEvent.signedOut:
          _reset();
          break;
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
          _reset();
          _init();
          break;
        default:
          break;
      }
    });
  }

  /// Wipes all per-user state. Called on every auth transition so
  /// accounts can't inherit each other's data within a single session.
  void _reset() {
    _clipChannel?.unsubscribe();
    _clipChannel = null;
    _debounce?.cancel();
    _debounce = null;

    groups = [];
    isLoadingGroups = true;
    groupsError = null;

    _clipsByUserAndHour.clear();
    isLoadingClips = false;
    clipsLoadedOnce = false;

    _currentGroupIndex = 0;
    _currentPageIndex = 0;

    ClipService.instance.clearCache();

    notifyListeners();
  }

  // ---------- groups ----------
  List<EfocLogGroup> groups = [];
  bool isLoadingGroups = true;
  String? groupsError;

  static const _emptyGroup = EfocLogGroup(
    id: '',
    name: '',
    ownerId: '',
    avatarColor: Color(0xFFA855F7),
    members: [],
  );

  // ---------- hours ----------
  final List<int> hours = List.generate(24, (i) => i);
  int get currentHour => DateTime.now().hour;

  int _currentGroupIndex = 0;
  int _currentPageIndex = 0;

  int get currentGroupIndex => _currentGroupIndex;
  int get currentPageIndex => _currentPageIndex;

  int get currentHourIndex {
    final visible = visibleHourIndices;
    if (visible.isEmpty) return hours.first;
    final idx = _currentPageIndex.clamp(0, visible.length - 1);
    return visible[idx];
  }

  EfocLogGroup get currentGroup =>
      groups.isEmpty ? _emptyGroup : groups[_currentGroupIndex];

  bool get hasGroups => groups.isNotEmpty;

  bool get isCurrentGroupOwner {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    return currentGroup.ownerId == uid;
  }

  List<int> get visibleHourIndices {
    final nowHour = DateTime.now().hour;
    final result = <int>[];
    for (int i = 0; i < hours.length; i++) {
      final h = hours[i];
      if (h == nowHour) {
        result.add(i);
      } else if (h < nowHour) {
        if (_hasAnyClipAt(h)) result.add(i);
      }
    }
    return result;
  }

  bool _hasAnyClipAt(int hour) {
    if (!hasGroups) return false;
    for (final m in currentGroup.members) {
      if (_clipsByUserAndHour.containsKey('${m.id}-$hour')) return true;
    }
    return false;
  }

  int get defaultPageIndex {
    final visible = visibleHourIndices;
    if (visible.isEmpty) return 0;
    final nowHour = DateTime.now().hour;
    for (int p = 0; p < visible.length; p++) {
      if (hours[visible[p]] == nowHour) return p;
    }
    return visible.length - 1;
  }

  // ---------- clips ----------
  final Map<String, Map<String, dynamic>> _clipsByUserAndHour = {};
  bool isLoadingClips = false;
  bool clipsLoadedOnce = false;

  RealtimeChannel? _clipChannel;
  Timer? _debounce;

  // ---------- init ----------
  Future<void> _init() async {
    await _loadGroups();

    if (hasGroups) {
      await _loadClips();
      _subscribeRealtime();
    }
  }

  // ---------- setters ----------
  void setGroup(int i) {
    if (i < 0 || i >= groups.length) return;
    _currentGroupIndex = i;
    _currentPageIndex = 0;
    notifyListeners();
    _subscribeRealtime();
    _loadClips();
  }

  void setPage(int pageIdx) {
    final visible = visibleHourIndices;
    if (pageIdx < 0 || pageIdx >= visible.length) return;
    if (_currentPageIndex == pageIdx) return;
    _currentPageIndex = pageIdx;
    notifyListeners();
  }

  // ---------- data loading ----------
  Future<void> _loadGroups() async {
    isLoadingGroups = true;
    groupsError = null;
    notifyListeners();

    try {
      groups = await GroupService.instance.fetchMyGroups();
      if (_currentGroupIndex >= groups.length) _currentGroupIndex = 0;
    } catch (e) {
      groupsError = 'Failed to load groups: $e';
      debugPrint(groupsError);
    } finally {
      isLoadingGroups = false;
      notifyListeners();
    }
  }

  Future<void> _loadClips() async {
    if (!hasGroups) {
      _clipsByUserAndHour.clear();
      notifyListeners();
      return;
    }

    isLoadingClips = true;
    notifyListeners();

    try {
      final map = await ClipService.instance.fetchClipsForDay(
        groupId: currentGroup.id,
        date: DateTime.now(),
      );
      _clipsByUserAndHour
        ..clear()
        ..addAll(map);
    } catch (e) {
      debugPrint('Load clips error: $e');
    } finally {
      isLoadingClips = false;
      clipsLoadedOnce = true;
      notifyListeners();
    }
  }

  void _subscribeRealtime() {
    _clipChannel?.unsubscribe();
    _clipChannel = null;

    if (!hasGroups) return;

    _clipChannel = ClipService.instance.subscribeToGroupClips(
      groupId: currentGroup.id,
      onChange: () {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 200), _loadClips);
      },
    );
  }

  Future<void> refresh() async {
    await _loadGroups();
    if (hasGroups) await _loadClips();
  }

  // ---------- group mutations ----------

  Future<void> createGroupAndReload(String name) async {
    await GroupService.instance.createGroup(name);
    await _loadGroups();
    await _loadClips();
    _subscribeRealtime();
  }

  Future<void> joinGroupAndReload(String inviteCode) async {
    await GroupService.instance.joinGroup(inviteCode);
    await _loadGroups();
    await _loadClips();
    _subscribeRealtime();
  }

  Future<void> renameCurrentGroup(String newName) async {
    await GroupService.instance.renameGroup(currentGroup.id, newName);
    await _loadGroups();
    notifyListeners();
  }

  Future<void> leaveCurrentGroup() async {
    await GroupService.instance.leaveGroup(currentGroup.id);
    _currentGroupIndex = 0;
    _currentPageIndex = 0;
    await _loadGroups();
    await _loadClips();
    _subscribeRealtime();
  }

  Future<void> deleteCurrentGroup() async {
    await GroupService.instance.deleteGroup(currentGroup.id);
    _currentGroupIndex = 0;
    _currentPageIndex = 0;
    await _loadGroups();
    await _loadClips();
    _subscribeRealtime();
  }

  // ---------- cell queries ----------
  bool isCellFilled(int memberIdx, int hourIdx, EfocMember m) {
    final hour = hours[hourIdx];
    return _clipsByUserAndHour.containsKey('${m.id}-$hour');
  }

  Map<String, dynamic>? clipFor(int memberIdx, int hourIdx) {
    if (!hasGroups) return null;
    final member = currentGroup.members[memberIdx];
    final hour = hours[hourIdx];
    return _clipsByUserAndHour['${member.id}-$hour'];
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _debounce?.cancel();
    _clipChannel?.unsubscribe();
    super.dispose();
  }
}