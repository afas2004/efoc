import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/log_group.dart';
import '../theme/colors.dart';
import 'games_config.dart';
import 'games_database.dart';
import 'open_tables.dart';
import 'table_screen.dart';

/// The Games tab of one group: its open tables, and the games with
/// "Open a table" and "Practice vs bots".
class GamesScreen extends StatefulWidget {
  final EfocLogGroup group;

  const GamesScreen({super.key, required this.group});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  Stream<List<OpenTable>>? _tables;
  bool _connecting = true;
  bool _offline = false;
  String? _offlineReason;
  bool _acquired = false;

  String get _myUid => Supabase.instance.client.auth.currentUser?.id ?? '';

  String get _myName {
    final me = widget.group.members.where((m) => m.isMe).firstOrNull;
    return me?.name ?? 'Player';
  }

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    _acquired = true;
    try {
      await GamesDatabase.instance.acquire();
      if (!mounted) return;
      setState(() {
        _tables = OpenTables.instance.watch(widget.group.id);
        _connecting = false;
      });
    } catch (e) {
      debugPrint('games connect: $e');
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _offline = true;
        _offlineReason = '$e';
      });
    }
  }

  @override
  void dispose() {
    if (_acquired) GamesDatabase.instance.release();
    super.dispose();
  }

  void _openTable(GameInfo game) {
    _push(TableScreen(
      gameId: game.id,
      roomId: OpenTables.instance.newRoomId(),
      groupId: widget.group.id,
      myUid: _myUid,
      myName: _myName,
      createWithMembers: [for (final m in widget.group.members) m.id],
    ));
  }

  void _join(OpenTable t) {
    _push(TableScreen(
      gameId: t.gameId,
      roomId: t.roomId,
      groupId: widget.group.id,
      myUid: _myUid,
      myName: _myName,
    ));
  }

  void _practice(GameInfo game) {
    _push(TableScreen(
      gameId: game.id,
      groupId: widget.group.id,
      myUid: _myUid,
      myName: _myName,
    ));
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EfocColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Games',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          widget.group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: EfocColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                children: [
                  _sectionTitle('Open tables'),
                  _openTables(),
                  const SizedBox(height: 18),
                  _sectionTitle('Play'),
                  for (final g in kGames) _GameCard(
                    game: g,
                    canOpen: !_offline && !_connecting,
                    onOpen: () => _openTable(g),
                    onPractice: () => _practice(g),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: EfocColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _openTables() {
    if (_connecting) {
      return _note('Connecting…');
    }
    if (_offline) {
      return _note(
        "Couldn't reach the game server. Practice still works.",
        detail: _offlineReason,
      );
    }
    return StreamBuilder<List<OpenTable>>(
      stream: _tables,
      builder: (context, snap) {
        if (snap.hasError) return _note("Couldn't load tables.");
        final tables = snap.data;
        if (tables == null) return _note('Loading…');
        if (tables.isEmpty) return _note('No tables open. Open one below!');
        return Column(
          children: [
            for (final t in tables) _OpenTableTile(table: t, myUid: _myUid, onJoin: () => _join(t)),
          ],
        );
      },
    );
  }

  Widget _note(String text, {String? detail}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EfocColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                detail,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ],
        ),
      );
}

class _OpenTableTile extends StatelessWidget {
  final OpenTable table;
  final String myUid;
  final VoidCallback onJoin;

  const _OpenTableTile({required this.table, required this.myUid, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final game = kGames.where((g) => g.id == table.gameId).firstOrNull;
    final mine = table.hostUid == myUid;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EfocColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Text(game?.emoji ?? '🃏', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game?.name ?? table.gameId,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                Text(
                  mine ? 'Your table' : "${table.hostName}'s table",
                  style: const TextStyle(color: EfocColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: EfocColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            onPressed: onJoin,
            child: Text(mine ? 'Back in' : 'Join', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameInfo game;
  final bool canOpen;
  final VoidCallback onOpen;
  final VoidCallback onPractice;

  const _GameCard({
    required this.game,
    required this.canOpen,
    required this.onOpen,
    required this.onPractice,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: game.ready ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EfocColors.surface,
          borderRadius: BorderRadius.circular(18),
          gradient: game.ready
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [EfocColors.accentDark.withValues(alpha: 0.55), EfocColors.surface],
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(game.emoji, style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.name,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      Text(game.blurb, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            if (game.ready) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: EfocColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      onPressed: canOpen ? onOpen : null,
                      child: const Text('Open a table', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: EfocColors.accentBright),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      onPressed: onPractice,
                      child: const Text('Practice vs bots', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
