import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';

import 'games_database.dart';

class OpenTable {
  final String roomId;
  final String gameId;
  final String hostUid;
  final String hostName;
  final DateTime createdAt;

  const OpenTable({
    required this.roomId,
    required this.gameId,
    required this.hostUid,
    required this.hostName,
    required this.createdAt,
  });
}

/// The group's open tables, at `tables/{groupId}/{roomId}` in the Realtime
/// Database (see games/firebase/database.rules.json). The host lists a
/// table once its room exists; it comes off when the match has results.
class OpenTables {
  OpenTables._();
  static final OpenTables instance = OpenTables._();

  /// Tables older than this are left over from a host that never finished.
  static const maxAge = Duration(hours: 6);

  DatabaseReference _ref(String groupId) =>
      GamesDatabase.instance.db.ref('tables/$groupId');

  /// A new room id: time-ordered and hard to guess.
  String newRoomId() {
    const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '$t-${List.generate(8, (_) => chars[r.nextInt(chars.length)]).join()}';
  }

  Stream<List<OpenTable>> watch(String groupId) {
    return _ref(groupId).onValue.map((e) {
      final v = e.snapshot.value;
      if (v is! Map) return const <OpenTable>[];
      final cutoff = DateTime.now().subtract(maxAge);
      final out = <OpenTable>[];
      for (final entry in v.entries) {
        final t = entry.value;
        if (t is! Map) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(
            (t['createdAt'] as num?)?.toInt() ?? 0);
        if (at.isBefore(cutoff)) continue;
        out.add(OpenTable(
          roomId: '${entry.key}',
          gameId: '${t['gameId'] ?? ''}',
          hostUid: '${t['hostUid'] ?? ''}',
          hostName: '${t['hostName'] ?? ''}',
          createdAt: at,
        ));
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    });
  }

  Future<void> list(String groupId, String roomId, String gameId,
          String hostUid, String hostName) =>
      _ref(groupId).child(roomId).set({
        'gameId': gameId,
        'hostUid': hostUid,
        'hostName': hostName.length > 40 ? hostName.substring(0, 40) : hostName,
        'createdAt': ServerValue.timestamp,
      });

  Future<void> unlist(String groupId, String roomId) =>
      _ref(groupId).child(roomId).remove();
}
