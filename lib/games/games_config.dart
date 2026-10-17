/// Where the card games live. Override for local testing with
/// `--dart-define=GAMES_ORIGIN=http://localhost:5173` (the games-web dev
/// server).
const String kGamesOrigin = String.fromEnvironment(
  'GAMES_ORIGIN',
  defaultValue: 'https://games.efoc.party',
);

/// Realtime Database for live tables (project efoc-fcf44, asia-southeast1).
const String kGamesDatabaseUrl = String.fromEnvironment(
  'GAMES_DATABASE_URL',
  defaultValue:
      'https://efoc-fcf44-default-rtdb.asia-southeast1.firebasedatabase.app',
);

class GameInfo {
  final String id;
  final String name;
  final String emoji;
  final String blurb;
  final bool ready;

  const GameInfo(this.id, this.name, this.emoji, this.blurb, {this.ready = false});
}

const List<GameInfo> kGames = [
  GameInfo('bigtwo', 'Big Two', '🃏', '2–8 players · get rid of every card',
      ready: true),
  GameInfo('hearts', 'Hearts', '♥️', 'Coming soon'),
  GameInfo('21', '21', '🎰', 'Coming soon'),
  GameInfo('lucky7', 'Lucky 7', '🍀', 'Coming soon'),
  GameInfo('zombie', 'Zombie', '🧟', 'Coming soon'),
];

/// Seat avatars in the table are emoji (the rules cap them at 16 chars),
/// picked from the uid so each friend keeps the same one.
String gameAvatarFor(String uid) {
  const pool = ['😎', '🦁', '🐸', '🐵', '🦄', '🐙', '🦖', '🐧', '🦊', '🐼', '🐯', '🐨'];
  final h = uid.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
  return pool[h % pool.length];
}
