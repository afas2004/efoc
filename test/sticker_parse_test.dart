import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:efoc/services/sticker_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1x1 transparent PNG, enough for the extension sniffer.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
]);

Uint8List _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

List<int> _json(Map<String, dynamic> map) => utf8.encode(jsonEncode(map));

void main() {
  group('parseWastickers', () {
    test('our own export shape: contents.json at the root', () {
      final bytes = _zip({
        'contents.json': _json({
          'identifier': 'kopi',
          'name': 'Kopi Gang',
          'tray_image_file': 'tray.png',
          'stickers': [
            {'image_file': '00.png', 'emojis': ['☕']},
            {'image_file': '01.png', 'emojis': ['😀']},
          ],
        }),
        'tray.png': _png,
        '00.png': _png,
        '01.png': _png,
      });

      final pack = StickerService.parseWastickers(bytes);
      expect(pack.name, 'Kopi Gang');
      expect(pack.stickers, hasLength(2));
      expect(pack.stickers.first.emojis, ['☕']);
      expect(pack.tray, isNotNull);
    });

    test('contents.json inside a folder, images beside it', () {
      final bytes = _zip({
        'pack/contents.json': _json({
          'name': 'Wrapped',
          'stickers': [
            {'image_file': 'a.png'},
          ],
        }),
        'pack/a.png': _png,
      });

      final pack = StickerService.parseWastickers(bytes);
      expect(pack.name, 'Wrapped');
      expect(pack.stickers, hasLength(1));
    });

    test('the {"sticker_packs": [...]} wrapper', () {
      final bytes = _zip({
        'contents.json': _json({
          'android_play_store_link': '',
          'sticker_packs': [
            {
              'identifier': 'myprojectstickers',
              'name': 'Packed',
              'tray_image_file': 'tray.png',
              'stickers': [
                {'image_file': '01.webp', 'emojis': ['✌️']},
              ],
            },
          ],
        }),
        'tray.png': _png,
        '01.webp': _png,
      });

      final pack = StickerService.parseWastickers(bytes);
      expect(pack.name, 'Packed');
      expect(pack.stickers, hasLength(1));
    });

    test('alternate key names are still understood', () {
      final bytes = _zip({
        'contents.json': _json({
          'title': 'Alternate',
          'stickers': [
            {'file': 'x.png', 'emoji': '🙂'},
            {'image': 'y.png'},
          ],
        }),
        'x.png': _png,
        'y.png': _png,
      });

      final pack = StickerService.parseWastickers(bytes);
      expect(pack.name, 'Alternate');
      expect(pack.stickers, hasLength(2));
      expect(pack.stickers.first.emojis, ['🙂']);
    });

    test('no contents.json at all: every image becomes a sticker', () {
      final bytes = _zip({
        'My Pack/tray.png': _png,
        'My Pack/one.png': _png,
        'My Pack/two.png': _png,
      });

      final pack = StickerService.parseWastickers(bytes);
      expect(pack.name, 'My Pack');
      expect(pack.stickers, hasLength(2)); // tray skipped
    });

    test('a zip inside a zip', () {
      final inner = _zip({
        'contents.json': _json({
          'name': 'Nested',
          'stickers': [
            {'image_file': 'n.png'},
          ],
        }),
        'n.png': _png,
      });
      final outer = _zip({'Nested.wastickers': inner});

      final pack = StickerService.parseWastickers(outer);
      expect(pack.name, 'Nested');
      expect(pack.stickers, hasLength(1));
    });

    test('a json that lists image files it does not contain falls back', () {
      final bytes = _zip({
        'contents.json': _json({
          'name': 'Broken',
          'stickers': [
            {'image_file': 'missing.png'},
          ],
        }),
        'real.png': _png,
      });

      final pack = StickerService.parseWastickers(bytes);
      expect(pack.stickers, hasLength(1));
    });

    test('junk is rejected with a readable message', () {
      final bytes = _zip({'readme.txt': utf8.encode('hello')});
      expect(
        () => StickerService.parseWastickers(bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
