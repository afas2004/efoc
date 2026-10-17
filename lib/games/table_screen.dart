import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/chat_service.dart';
import '../theme/colors.dart';
import 'game_session.dart';
import 'games_config.dart';
import 'games_database.dart';
import 'open_tables.dart';
import 'table_link.dart';
import 'table_view.dart';

/// One live table: the game page plus the [GameSession] that runs its
/// database calls. On the web build the page is an iframe, on Android a
/// WebView. The Realtime Database is online only while this screen is open.
/// With no [roomId] it is Practice vs bots: the page plays alone, offline.
class TableScreen extends StatefulWidget {
  final String gameId;
  final String? roomId;
  final String groupId;
  final String myUid;
  final String myName;

  /// The group's member uids when this phone opens the table (it becomes
  /// the host and copies them into rooms/{id}/allowed). Null to join.
  final List<String>? createWithMembers;

  const TableScreen({
    super.key,
    required this.gameId,
    this.roomId,
    required this.groupId,
    required this.myUid,
    required this.myName,
    this.createWithMembers,
  });

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> with WidgetsBindingObserver {
  final _controller = TableController();
  Widget? _view;
  GameSession? _session;
  String? _error;
  bool _initSent = false;
  bool _online = false;
  bool _announced = false;
  int _clockOffset = 0;
  StreamSubscription<void>? _resultsWatch;
  StreamSubscription<int>? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final roomId = widget.roomId;
    if (roomId == null) {
      setState(() => _view = _buildView());
      return;
    }
    _online = true; // acquire() counts us even if sign-in fails
    try {
      await GamesDatabase.instance.acquire();
    } catch (e) {
      debugPrint('games sign-in: $e');
      if (mounted) {
        setState(() => _error = "Couldn't connect to the game server. Try again.");
      }
      return;
    }
    if (!mounted) return;
    final db = FirebaseGameDb(GamesDatabase.instance.db);
    _session = GameSession(
      db: db,
      roomId: roomId,
      send: _controller.send,
      onUpdated: (values) => _onPageUpdate(db, roomId, values),
    );
    _clock = db.clockOffset.listen((o) => _clockOffset = o, onError: (_) {});
    setState(() => _view = _buildView());
  }

  Widget _buildView() => buildTableView(
        url: Uri.parse('$kGamesBase/${widget.gameId}/'),
        origin: kGamesOrigin,
        base: kGamesBase,
        controller: _controller,
        onMessage: _onMessage,
        onLoaded: _sendInit,
      );

  TableLink? get _link {
    final roomId = widget.roomId;
    if (roomId == null) return null;
    return TableLink(roomId: roomId, groupId: widget.groupId, gameId: widget.gameId);
  }

  /// The page created the room as us (its first update writes meta with
  /// hostUid = me): list the table in the group's Games tab, post a chat
  /// card with a Join button, and take the listing off when the match has
  /// results. Watching the room before it exists isn't allowed by the
  /// rules, which is why this waits for the page's own write.
  void _onPageUpdate(GameDb db, String roomId, Map<String, Object?> values) {
    if (_announced || widget.createWithMembers == null) return;
    final meta = values['rooms/$roomId/meta'];
    if (meta is! Map || meta['hostUid'] != widget.myUid) return;
    _announced = true;

    OpenTables.instance
        .list(widget.groupId, roomId, widget.gameId, widget.myUid, widget.myName)
        .catchError((Object e) => debugPrint('games list table: $e'));

    final link = _link!;
    if ((widget.createWithMembers?.length ?? 0) > 1) {
      ChatService.instance
          .sendText(
            groupId: widget.groupId,
            text: '🃏 I opened a ${link.gameName()} table. Come play!\n'
                '${link.toUri()}',
          )
          .catchError((Object e) => debugPrint('games chat card: $e'));
    }

    _resultsWatch = db.watch('rooms/$roomId/results', (r) {
      if (r == null) return;
      _resultsWatch?.cancel();
      OpenTables.instance
          .unlist(widget.groupId, roomId)
          .catchError((Object e) => debugPrint('games unlist: $e'));
    });
  }

  /// The waiting room's Invite button: share (Android) or copy (web) a
  /// link that opens this table.
  Future<void> _invite() async {
    final link = _link;
    if (link == null) return;
    final text = 'Join my ${link.gameName()} table on EFOC: ${link.toUri()}';
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite link copied — paste it anywhere'),
          duration: Duration(milliseconds: 1600),
        ),
      );
      return;
    }
    await Share.share(text, subject: 'Join my table');
  }

  void _sendInit() {
    // The page may reload (it never does on its own); one init per load.
    _initSent = true;
    final pad = MediaQuery.of(context).padding;
    final roomId = widget.roomId;
    final avatar = gameAvatarFor(widget.myUid);
    _controller.send({
      't': 'init',
      'gameId': widget.gameId,
      'mySeat': 0,
      'isHost': widget.createWithMembers != null,
      'isSpectator': false,
      'practice': roomId == null,
      'players': [
        {'name': widget.myName, 'avatar': avatar},
      ],
      'locale': Localizations.localeOf(context).toLanguageTag(),
      'insets': {'top': pad.top, 'right': pad.right, 'bottom': pad.bottom, 'left': pad.left},
      if (roomId != null)
        'online': {
          'room': roomId,
          'uid': widget.myUid,
          'name': widget.myName,
          'avatar': avatar,
          'clockOffset': _clockOffset,
          if (widget.createWithMembers != null)
            'create': {
              'groupId': widget.groupId,
              'allowed': widget.createWithMembers,
            },
        },
    });
  }

  void _onMessage(Object? msg) {
    if (msg is! Map) return;
    if (_session?.handle(msg) == true) return;
    switch (msg['t']) {
      case 'ready':
        // On the web build the page's first `ready` only reaches efoc.party;
        // init also goes out on load, and the page ignores a second one.
        if (!_initSent) _sendInit();
      case 'haptic':
        switch (msg['kind']) {
          case 'light':
            HapticFeedback.selectionClick();
          case 'medium':
            HapticFeedback.mediumImpact();
          case 'strong':
            HapticFeedback.heavyImpact();
          case 'error':
            HapticFeedback.vibrate();
        }
      case 'invite':
        _invite();
      case 'exit':
        if (mounted) Navigator.of(context).maybePop(true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller.send({'t': 'pause'});
    } else if (state == AppLifecycleState.resumed) {
      _controller.send({'t': 'resume'});
    }
  }

  Future<bool> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EfocColors.surface,
        title: const Text(
          'Leave the table?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'A bot will take your seat.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Leave', style: TextStyle(color: EfocColors.accentBright)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultsWatch?.cancel();
    _clock?.cancel();
    _session?.close();
    _controller.sender = null;
    if (_online) GamesDatabase.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        // The page's own Leave button already asked.
        if (result == true || await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: EfocColors.bg,
        body: _error != null
            ? _ErrorView(message: _error!, onBack: () => Navigator.of(context).pop())
            : _view ??
                Center(child: CircularProgressIndicator(color: EfocColors.accent)),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onBack;

  const _ErrorView({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🃏', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: onBack, child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}
