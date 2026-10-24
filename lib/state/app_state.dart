import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../games/table_link.dart';
import '../models/log_group.dart';
import '../models/member.dart';
import '../models/vlog.dart';
import '../services/chat_service.dart';
import '../services/clip_service.dart';
import '../services/group_service.dart';
import '../services/picked_file.dart';
import '../services/reminder_service.dart';
import '../services/vlog_service.dart';

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
  ///
  /// Note: pendingInviteCode is intentionally NOT cleared here. It must
  /// survive the signedOut -> signedIn transition so the join sheet can
  /// auto-open after login when the user arrived via an invite link.
  void _reset() {
    _clipChannel?.unsubscribe();
    _clipChannel = null;
    _chatChannel?.unsubscribe();
    _chatChannel = null;
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

    _vlogs.clear();
    _viewedVlogIds.clear();

    _viewedClipIds.clear();
    _unseenCounts.clear();
    _unreadChatGroups.clear();

    ClipService.instance.clearCache();

    notifyListeners();
  }

  // ---------- pending invite ----------
  String? _pendingInviteCode;
  String? get pendingInviteCode => _pendingInviteCode;

  bool get hasPendingInvite => _pendingInviteCode != null && _pendingInviteCode!.isNotEmpty;

  void setPendingInviteCode(String code) {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return;
    _pendingInviteCode = trimmed;
    notifyListeners();
  }

  void clearPendingInviteCode() {
    if (_pendingInviteCode == null) return;
    _pendingInviteCode = null;
    notifyListeners();
  }

  // ---------- pending game table (from a link) ----------
  TableLink? _pendingTable;
  TableLink? get pendingTable => _pendingTable;

  void setPendingTable(TableLink link) {
    _pendingTable = link;
    notifyListeners();
  }

  void clearPendingTable() {
    _pendingTable = null;
  }

  // ---------- pending sticker pack (from a share link) ----------
  /// `efoc.party/?pack=<slug>`
  String? _pendingStickerPackSlug;
  String? get pendingStickerPackSlug => _pendingStickerPackSlug;

  void setPendingStickerPackSlug(String slug) {
    final trimmed = slug.trim();
    if (trimmed.isEmpty) return;
    _pendingStickerPackSlug = trimmed;
    notifyListeners();
  }

  void clearPendingStickerPackSlug() {
    _pendingStickerPackSlug = null;
  }

  // ---------- a file shared into efoc (Android share sheet) ----------
  PickedBytes? _pendingSharedFile;
  PickedBytes? get pendingSharedFile => _pendingSharedFile;

  void setPendingSharedFile(PickedBytes file) {
    _pendingSharedFile = file;
    notifyListeners();
  }

  /// Hands the file over once and forgets it, so a rebuild doesn't re-import.
  PickedBytes? takePendingSharedFile() {
    final file = _pendingSharedFile;
    _pendingSharedFile = null;
    return file;
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

  // ---------- vlogs ----------
  /// Stitched vlogs keyed by `groupId|yyyy-mm-dd`, for the last [recentDays] days.
  final Map<String, EfocVlog> _vlogs = {};
  final Set<String> _viewedVlogIds = {};

  /// Today plus the six days before it: the window for vlogs and unseen counts.
  static const int recentDays = 7;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _vlogKey(String groupId, DateTime day) =>
      '$groupId|${day.year}-${day.month}-${day.day}';

  EfocVlog? vlogFor(String groupId, DateTime day) =>
      _vlogs[_vlogKey(groupId, _dateOnly(day))];

  EfocVlog? yesterdayVlog(String groupId) => vlogFor(
        groupId,
        _dateOnly(DateTime.now()).subtract(const Duration(days: 1)),
      );

  bool isVlogViewed(EfocVlog vlog) => _viewedVlogIds.contains(vlog.id);

  /// Drives the pulsing ring on the group avatar and the dropdown "new" hint.
  bool hasUnviewedYesterday(String groupId) {
    final v = yesterdayVlog(groupId);
    return v != null && !isVlogViewed(v);
  }

  /// Marks a vlog as watched everywhere (dots, ring, dropdown). Optimistic.
  Future<void> markVlogViewed(EfocVlog vlog) async {
    if (!_viewedVlogIds.add(vlog.id)) return;
    notifyListeners();
    try {
      await VlogService.instance.markViewed(vlog.id);
    } catch (e) {
      debugPrint('Mark vlog viewed error: $e');
    }
  }

  Future<void> reloadVlogs() => _loadVlogs();

  Future<void> _loadVlogs() async {
    if (!hasGroups) return;
    try {
      final since = _dateOnly(DateTime.now())
          .subtract(const Duration(days: recentDays - 1));
      final vlogs = await VlogService.instance.fetchRecent(
        groupIds: groups.map((g) => g.id).toList(),
        since: since,
      );
      final viewed = await VlogService.instance
          .fetchViewedIds(vlogs.map((v) => v.id).toList());
      _vlogs
        ..clear()
        ..addEntries(vlogs.map((v) => MapEntry(_vlogKey(v.groupId, v.date), v)));
      _viewedVlogIds
        ..clear()
        ..addAll(viewed);
      notifyListeners();
    } catch (e) {
      debugPrint('Load vlogs error: $e');
    }
  }

  /// Today's clips in the current group, in hour order. Used to preview
  /// "today so far" before the midnight stitch exists.
  List<Map<String, dynamic>> get todaysClipsInOrder {
    final clips = _clipsByUserAndHour.values.toList()
      ..sort((a, b) {
        final byHour =
            (a['hour_of_day'] as int).compareTo(b['hour_of_day'] as int);
        if (byHour != 0) return byHour;
        return ((a['created_at'] as String?) ?? '')
            .compareTo((b['created_at'] as String?) ?? '');
      });
    return clips;
  }

  // ---------- seen clips ----------
  /// Clip ids (from the loaded day) the current user has watched.
  final Set<String> _viewedClipIds = {};

  /// Unwatched clips from other members, keyed by `groupId|yyyy-mm-dd`,
  /// for the last [recentDays] days across all groups.
  final Map<String, int> _unseenCounts = {};

  String? get _myId => _client.auth.currentUser?.id;

  /// Someone else's clip you haven't opened yet. Your own clips never are.
  bool isClipUnseen(Map<String, dynamic> clip) =>
      clip['user_id'] != _myId && !_viewedClipIds.contains(clip['id']);

  /// You already have a clip for the current hour in the group on screen.
  bool get recordedThisHour =>
      _clipsByUserAndHour.containsKey('$_myId-$currentHour');

  /// Drives the "new" hint in the dropdown.
  bool hasUnseenClips(String groupId) => _unseenCounts.entries
      .any((e) => e.value > 0 && e.key.startsWith('$groupId|'));

  /// Any group other than the current one has something new. Drives the
  /// dot on the group pill so you know to open the dropdown.
  bool get otherGroupsHaveNews => groups.any((g) =>
      g.id != currentGroup.id &&
      (hasUnseenClips(g.id) ||
          hasUnviewedYesterday(g.id) ||
          hasUnreadChat(g.id)));

  /// Someone else's clip at [hour] today, in the current group, that you
  /// haven't opened yet. Lights that hour's dot.
  bool hourHasUnseen(int hour) => _clipsByUserAndHour.values
      .any((c) => c['hour_of_day'] == hour && isClipUnseen(c));

  /// Marks clips as watched everywhere (grid, dots, dropdown). Optimistic.
  void markClipsViewed(Iterable<Map<String, dynamic>> clips) {
    final fresh = clips.where(isClipUnseen).toList();
    if (fresh.isEmpty) return;
    for (final clip in fresh) {
      _viewedClipIds.add(clip['id'] as String);
      final key = '${clip['group_id']}|${clip['recorded_on']}';
      final left = (_unseenCounts[key] ?? 0) - 1;
      if (left > 0) {
        _unseenCounts[key] = left;
      } else {
        _unseenCounts.remove(key);
      }
    }
    notifyListeners();
    for (final clip in fresh) {
      ClipService.instance.markViewed(clip['id'] as String).catchError(
            (Object e) => debugPrint('Mark clip viewed error: $e'),
          );
    }
  }

  Future<void> _loadUnseenCounts() async {
    if (!hasGroups) return;
    try {
      final since = _dateOnly(DateTime.now())
          .subtract(const Duration(days: recentDays - 1));
      final counts =
          await ClipService.instance.fetchUnseenCounts(since: since);
      _unseenCounts
        ..clear()
        ..addAll(counts);
      notifyListeners();
    } catch (e) {
      debugPrint('Load unseen counts error: $e');
    }
  }

  // ---------- chat unread ----------
  final Set<String> _unreadChatGroups = {};
  RealtimeChannel? _chatChannel;

  bool hasUnreadChat(String groupId) => _unreadChatGroups.contains(groupId);

  Future<void> markChatRead(String groupId) async {
    if (_unreadChatGroups.remove(groupId)) notifyListeners();
    try {
      await ChatService.instance.markRead(groupId);
    } catch (e) {
      debugPrint('Mark chat read error: $e');
    }
  }

  Future<void> _loadUnreadChat() async {
    if (!hasGroups) return;
    try {
      final ids = await ChatService.instance.fetchUnreadGroupIds();
      _unreadChatGroups
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (e) {
      debugPrint('Load unread chat error: $e');
    }
  }

  /// Re-checks unseen clips, unread chat and vlogs, e.g. on app resume.
  Future<void> reloadBadges() => Future.wait([
        _loadUnseenCounts(),
        _loadUnreadChat(),
        _loadVlogs(),
      ]);

  // ---------- init ----------
  Future<void> _init() async {
    await _loadGroups();

    if (hasGroups) {
      await _loadClips();
      _subscribeRealtime();
      _loadVlogs();
      _loadUnreadChat();
    }
    ReminderService.instance.syncOnLaunch();
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
      final viewed = await ClipService.instance.fetchViewedIds(
        map.values.map((c) => c['id'] as String).toList(),
      );
      _clipsByUserAndHour
        ..clear()
        ..addAll(map);
      _viewedClipIds
        ..clear()
        ..addAll(viewed);
    } catch (e) {
      debugPrint('Load clips error: $e');
    } finally {
      isLoadingClips = false;
      clipsLoadedOnce = true;
      notifyListeners();
    }
    // A new upload from someone else may have just arrived.
    _loadUnseenCounts();
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

    // Lights the chat dot live for the group on screen. Other groups are
    // re-checked on resume and when you switch to them.
    _chatChannel?.unsubscribe();
    _chatChannel = _client
        .channel('unread-${currentGroup.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: currentGroup.id,
          ),
          callback: (_) => _loadUnreadChat(),
        )
        .subscribe();
  }

  Future<void> refresh() async {
    await _loadGroups();
    if (hasGroups) {
      await Future.wait([_loadClips(), _loadVlogs(), _loadUnreadChat()]);
    }
  }

  // ---------- group mutations ----------

  Future<void> createGroupAndReload(String name) async {
    await GroupService.instance.createGroup(name);
    await _loadGroups();
    await _loadClips();
    _subscribeRealtime();
    _loadVlogs();
  }

  Future<void> joinGroupAndReload(String inviteCode) async {
    await GroupService.instance.joinGroup(inviteCode);
    await _loadGroups();
    await _loadClips();
    _subscribeRealtime();
    _loadVlogs();
  }

  Future<void> renameCurrentGroup(String newName) async {
    await GroupService.instance.renameGroup(currentGroup.id, newName);
    await _loadGroups();
    notifyListeners();
  }

  Future<void> transferCurrentGroup(String newOwnerId) async {
    await GroupService.instance.transferOwnership(currentGroup.id, newOwnerId);
    await _loadGroups();
  }

  Future<void> removeMemberFromCurrentGroup(String userId) async {
    await GroupService.instance.removeMember(currentGroup.id, userId);
    await _loadGroups();
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
    _chatChannel?.unsubscribe();
    super.dispose();
  }
}