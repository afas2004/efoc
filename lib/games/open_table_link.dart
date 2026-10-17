import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/app_state.dart';
import 'table_link.dart';
import 'table_screen.dart';

/// Opens the table a link or chat card points at, as a joining player.
/// Only for a group I'm in (the room's rules would refuse anyone else).
Future<void> openTableLink(BuildContext context, TableLink link) async {
  final state = context.read<AppState>();
  final uid = Supabase.instance.client.auth.currentUser?.id;
  final group = state.groups.where((g) => g.id == link.groupId).firstOrNull;
  if (uid == null || group == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("That table is in a Log you're not in")),
    );
    return;
  }
  final me = group.members.where((m) => m.isMe).firstOrNull;
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TableScreen(
        gameId: link.gameId,
        roomId: link.roomId,
        groupId: link.groupId,
        myUid: uid,
        myName: me?.name ?? 'Player',
      ),
    ),
  );
}
