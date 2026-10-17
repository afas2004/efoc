import 'dart:async';

import 'package:efoc/games/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDb implements GameDb {
  final Map<String, Object?> data = {};
  final List<String> calls = [];
  final StreamController<void> _changes = StreamController.broadcast();
  int _push = 0;

  @override
  Future<Object?> get(String path) async {
    calls.add('get $path');
    return data[path];
  }

  @override
  Future<void> set(String path, Object? value) async {
    calls.add('set $path');
    data[path] = value;
    _changes.add(null);
  }

  @override
  Future<void> update(Map<String, Object?> values) async {
    calls.add('update ${values.keys.join(',')}');
    data.addAll(values);
    _changes.add(null);
  }

  @override
  Future<String> push(String path, Object? value) async {
    final k = 'k${_push++}';
    await set('$path/$k', value);
    return k;
  }

  @override
  Future<void> onDisconnectSet(String path, Object? value) async {
    calls.add('onDisconnect $path');
  }

  @override
  StreamSubscription<void> watch(String path, void Function(Object?) onValue) {
    calls.add('watch $path');
    scheduleMicrotask(() => onValue(data[path]));
    return _changes.stream.listen((_) => onValue(data[path]));
  }

  @override
  StreamSubscription<void> watchChildren(
      String path, void Function(String key, Object? value) onChild) {
    calls.add('children $path');
    final seen = <String>{};
    void fire() {
      for (final k in data.keys.where((k) => k.startsWith('$path/'))) {
        if (seen.add(k)) onChild(k.substring(path.length + 1), data[k]);
      }
    }

    scheduleMicrotask(fire);
    return _changes.stream.listen((_) => fire());
  }

  @override
  Stream<int> get clockOffset => Stream.value(42);
}

void main() {
  late FakeDb db;
  late List<Map<String, Object?>> sent;
  late GameSession s;

  setUp(() {
    db = FakeDb();
    sent = [];
    s = GameSession(db: db, roomId: 'r1', send: sent.add);
  });

  tearDown(() => s.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('only this room\'s rooms/presence/chat paths are allowed', () {
    expect(s.allowed('rooms/r1/meta'), isTrue);
    expect(s.allowed('presence/r1/u1'), isTrue);
    expect(s.allowed('chat/r1'), isTrue);
    expect(s.allowed('rooms/r2/meta'), isFalse);
    expect(s.allowed('rooms'), isFalse);
    expect(s.allowed('tables/g1/r1'), isFalse);
    expect(s.allowed('users/u1'), isFalse);
    expect(s.allowed('rooms/r1/../r2'), isFalse);
    expect(s.allowed('rooms/r1//x'), isFalse);
    expect(s.allowed('.info/connected'), isFalse);
    expect(s.allowed(null), isFalse);
  });

  test('set, get and push answer with dbResult', () async {
    s.handle({'t': 'db', 'id': 1, 'op': 'set', 'path': 'rooms/r1/meta', 'value': {'a': 1}});
    s.handle({'t': 'db', 'id': 2, 'op': 'get', 'path': 'rooms/r1/meta'});
    s.handle({'t': 'db', 'id': 3, 'op': 'push', 'path': 'rooms/r1/intents', 'value': {'uid': 'u1'}});
    await settle();
    final results = sent.where((m) => m['t'] == 'dbResult').toList();
    expect(results.map((m) => m['id']), [1, 2, 3]);
    expect(results.every((m) => m['ok'] == true), isTrue);
    expect(results[1]['value'], {'a': 1});
    expect(results[2]['value'], 'k0');
    expect(sent.any((m) => m['t'] == 'dbClock' && m['offset'] == 42), isTrue);
  });

  test('refuses other paths without touching the database', () async {
    s.handle({'t': 'db', 'id': 7, 'op': 'set', 'path': 'rooms/other/meta', 'value': 1});
    s.handle({
      't': 'db',
      'id': 8,
      'op': 'update',
      'values': {'rooms/r1/a': 1, 'users/x': 2},
    });
    s.handle({'t': 'db', 'id': 9, 'op': 'watch', 'path': 'chat/zzz'});
    await settle();
    expect(db.calls, isEmpty);
    final results = sent.where((m) => m['t'] == 'dbResult').toList();
    expect(results.map((m) => [m['id'], m['ok']]), [
      [7, false],
      [8, false],
    ]);
  });

  test('watch and watchChildren stream until unwatch', () async {
    s.handle({'t': 'db', 'id': 4, 'op': 'watch', 'path': 'rooms/r1/meta'});
    s.handle({'t': 'db', 'id': 5, 'op': 'watchChildren', 'path': 'rooms/r1/log'});
    await settle();
    await db.set('rooms/r1/log/000001', {'seat': 0});
    await db.set('rooms/r1/meta', {'status': 'playing'});
    await settle();
    expect(sent.where((m) => m['t'] == 'dbChild').single,
        {'t': 'dbChild', 'id': 5, 'key': '000001', 'value': {'seat': 0}});
    expect(sent.where((m) => m['t'] == 'dbValue' && m['id'] == 4).last['value'],
        {'status': 'playing'});

    s.handle({'t': 'db', 'id': 4, 'op': 'unwatch'});
    final before = sent.length;
    await db.set('rooms/r1/meta', {'status': 'done'});
    await settle();
    expect(sent.skip(before).where((m) => m['id'] == 4), isEmpty);
  });

  test('ignores non-db messages and stops after close', () async {
    expect(s.handle({'t': 'haptic', 'kind': 'light'}), isFalse);
    s.close();
    expect(s.handle({'t': 'db', 'id': 1, 'op': 'get', 'path': 'rooms/r1/meta'}), isFalse);
  });
}
