import 'package:efoc/games/table_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const link = TableLink(roomId: 'mvchxkkg-tznewtqw', groupId: '3f1c-aa', gameId: 'bigtwo');

  test('round-trips through the /join link', () {
    final back = TableLink.fromUri(link.toUri());
    expect(back?.roomId, link.roomId);
    expect(back?.groupId, link.groupId);
    expect(back?.gameId, 'bigtwo');
    expect(link.toUri().path, '/join');
  });

  test('a group invite link is not a table link', () {
    expect(TableLink.fromUri(Uri.parse('https://efoc.party/join?code=ABC123')), isNull);
  });

  test('rejects games that are not ready and odd ids', () {
    expect(TableLink.fromUri(Uri.parse('https://efoc.party/join?table=r1&group=g1&game=hearts')), isNull);
    expect(TableLink.fromUri(Uri.parse('https://efoc.party/join?table=../x&group=g1&game=bigtwo')), isNull);
  });

  test('finds the link in a chat message and strips it', () {
    final text = '🃏 I opened a Big Two table. Come play!\n${link.toUri()}';
    expect(TableLink.inText(text)?.roomId, link.roomId);
    expect(TableLink.withoutLink(text), '🃏 I opened a Big Two table. Come play!');
    expect(TableLink.inText('see https://efoc.party/join?code=ABC123'), isNull);
  });
}
