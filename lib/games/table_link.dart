import 'games_config.dart';

/// A link straight into a table: https://efoc.party/join?table=…&group=…&game=…
/// It reuses the /join path, so Android's existing invite deep link (and
/// the web build's catch-all route) already open the app with it.
class TableLink {
  final String roomId;
  final String groupId;
  final String gameId;

  const TableLink({required this.roomId, required this.groupId, required this.gameId});

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  Uri toUri() => Uri.https('efoc.party', '/join', {
        'table': roomId,
        'group': groupId,
        'game': gameId,
      });

  static TableLink? fromUri(Uri uri) {
    final q = uri.queryParameters;
    final room = q['table'], group = q['group'], game = q['game'];
    if (room == null || group == null || game == null) return null;
    if (!_id.hasMatch(room) || !_id.hasMatch(group)) return null;
    if (!kGames.any((g) => g.id == game && g.ready)) return null;
    return TableLink(roomId: room, groupId: group, gameId: game);
  }

  static final RegExp _inText = RegExp(r'https://efoc\.party/join\?\S*table=\S+');

  /// The first table link in a chat message, if any.
  static TableLink? inText(String text) {
    final m = _inText.firstMatch(text);
    if (m == null) return null;
    final uri = Uri.tryParse(m.group(0)!);
    return uri == null ? null : fromUri(uri);
  }

  /// The message text without its link.
  static String withoutLink(String text) =>
      text.replaceAll(_inText, '').trim();

  String gameName() =>
      kGames.where((g) => g.id == gameId).firstOrNull?.name ?? gameId;
}
