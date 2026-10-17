import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// The few Realtime Database operations a table needs. [FirebaseGameDb] is
/// the real one; tests use a fake.
abstract class GameDb {
  Future<Object?> get(String path);
  Future<void> set(String path, Object? value);
  Future<void> update(Map<String, Object?> values);
  Future<String> push(String path, Object? value);
  Future<void> onDisconnectSet(String path, Object? value);
  StreamSubscription<void> watch(String path, void Function(Object?) onValue);
  StreamSubscription<void> watchChildren(
      String path, void Function(String key, Object? value) onChild);

  /// Server time minus this phone's time, in ms.
  Stream<int> get clockOffset;
}

class FirebaseGameDb implements GameDb {
  final FirebaseDatabase db;
  FirebaseGameDb(this.db);

  @override
  Future<Object?> get(String path) async => (await db.ref(path).get()).value;

  @override
  Future<void> set(String path, Object? value) => db.ref(path).set(value);

  @override
  Future<void> update(Map<String, Object?> values) => db.ref().update(values);

  @override
  Future<String> push(String path, Object? value) async {
    final ref = db.ref(path).push();
    await ref.set(value);
    return ref.key!;
  }

  @override
  Future<void> onDisconnectSet(String path, Object? value) =>
      db.ref(path).onDisconnect().set(value);

  @override
  StreamSubscription<void> watch(String path, void Function(Object?) onValue) =>
      db.ref(path).onValue.listen(
            (e) => onValue(e.snapshot.value),
            onError: (Object e) => debugPrint('games watch $path: $e'),
          );

  @override
  StreamSubscription<void> watchChildren(
          String path, void Function(String key, Object? value) onChild) =>
      db.ref(path).orderByKey().onChildAdded.listen(
            (e) => onChild(e.snapshot.key!, e.snapshot.value),
            onError: (Object e) => debugPrint('games children $path: $e'),
          );

  @override
  Stream<int> get clockOffset => db
      .ref('.info/serverTimeOffset')
      .onValue
      .map((e) => (e.snapshot.value as num?)?.round() ?? 0);
}

/// One table. The game page has no Firebase token: it sends `{t:'db', ...}`
/// bridge messages (games/apps/games-web/src/net/bridgeStore.ts) and this
/// runs them on the database, only under `rooms/{roomId}`,
/// `presence/{roomId}` and `chat/{roomId}`. The security rules then decide
/// every read and write as the signed-in player.
class GameSession {
  final GameDb db;
  final String roomId;

  /// Sends one message to the page (`window.efoc.receive` / postMessage).
  final void Function(Map<String, Object?> msg) send;

  final Map<int, StreamSubscription<void>> _subs = {};
  StreamSubscription<int>? _clock;
  bool _closed = false;

  GameSession({required this.db, required this.roomId, required this.send}) {
    _clock = db.clockOffset.listen(
      (o) => _send({'t': 'dbClock', 'offset': o}),
      onError: (_) {},
    );
  }

  static final RegExp _segment = RegExp(r'^[^.#$\[\]/]+$');

  /// Only this room's own paths, with plain key names.
  bool allowed(Object? path) {
    if (path is! String || path.isEmpty || path.length > 300) return false;
    final parts = path.split('/');
    if (parts.length < 2) return false;
    if (!const {'rooms', 'presence', 'chat'}.contains(parts[0])) return false;
    if (parts[1] != roomId) return false;
    return parts.every(_segment.hasMatch);
  }

  /// Handles one message from the page. Returns false if it wasn't a `db` one.
  bool handle(Object? raw) {
    if (_closed || raw is! Map || raw['t'] != 'db') return false;
    final id = raw['id'];
    final op = raw['op'];
    if (id is! num || op is! String) return true;
    final n = id.toInt();

    if (op == 'unwatch') {
      _subs.remove(n)?.cancel();
      return true;
    }

    final path = raw['path'];
    final values = raw['values'];
    final paths = op == 'update'
        ? (values is Map ? values.keys.toList() : const [null])
        : [path];
    if (!paths.every(allowed)) {
      debugPrint('games: refused $op ${paths.join(',')}');
      if (op != 'watch' && op != 'watchChildren') {
        _reply(n, ok: false, error: 'path not allowed');
      }
      return true;
    }

    switch (op) {
      case 'get':
        _run(n, () => db.get(path as String));
      case 'set':
        _run(n, () => db.set(path as String, raw['value']));
      case 'update':
        _run(n, () => db.update({
              for (final e in (values as Map).entries) e.key as String: e.value,
            }));
      case 'push':
        _run(n, () => db.push(path as String, raw['value']));
      case 'onDisconnect':
        _run(n, () => db.onDisconnectSet(path as String, raw['value']));
      case 'watch':
        _subs.remove(n)?.cancel();
        _subs[n] = db.watch(path as String,
            (v) => _send({'t': 'dbValue', 'id': n, 'value': plain(v)}));
      case 'watchChildren':
        _subs.remove(n)?.cancel();
        _subs[n] = db.watchChildren(
            path as String,
            (k, v) =>
                _send({'t': 'dbChild', 'id': n, 'key': k, 'value': plain(v)}));
      default:
        _reply(n, ok: false, error: 'unknown op');
    }
    return true;
  }

  void _run(int id, Future<Object?> Function() f) {
    f().then(
      (v) => _reply(id, ok: true, value: plain(v)),
      onError: (Object e) {
        debugPrint('games db: $e');
        _reply(id, ok: false, error: e.toString());
      },
    );
  }

  void _reply(int id, {required bool ok, Object? value, String? error}) {
    _send({
      't': 'dbResult',
      'id': id,
      'ok': ok,
      'value': value,
      'error': ?error,
    });
  }

  void _send(Map<String, Object?> msg) {
    if (!_closed) send(msg);
  }

  /// Database values as plain JSON (string keys, lists and maps).
  static Object? plain(Object? v) {
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': plain(e.value)};
    }
    if (v is List) return [for (final x in v) plain(x)];
    return v;
  }

  void close() {
    _closed = true;
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    _clock?.cancel();
  }
}
