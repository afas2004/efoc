import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sticker.dart';

/// The bytes of one sticker that is about to be uploaded, plus its emoji tags.
class StickerDraft {
  final Uint8List bytes;
  final String extension;
  final List<String> emojis;

  const StickerDraft({
    required this.bytes,
    required this.extension,
    this.emojis = const [],
  });

  /// Reads the format from the file name, falling back to the magic bytes.
  /// Everything WhatsApp produces is webp; photos from the gallery are usually
  /// jpg/png.
  factory StickerDraft.fromBytes(Uint8List bytes, {String? fileName}) {
    return StickerDraft(
      bytes: bytes,
      extension: imageExtension(bytes, fileName: fileName),
    );
  }
}

/// A whole pack read out of a `.wastickers` file, before anything is uploaded.
class ImportedPack {
  final String name;
  final StickerDraft? tray;
  final List<StickerDraft> stickers;

  const ImportedPack({
    required this.name,
    required this.tray,
    required this.stickers,
  });
}

class StickerService {
  StickerService._();
  static final StickerService instance = StickerService._();

  SupabaseClient get _client => Supabase.instance.client;

  static const _bucket = 'stickers';

  /// How many stickers upload at once. 30 stickers × 100 KB is small, but a
  /// phone on 4G chokes on 30 parallel requests.
  static const _parallelism = 5;

  static const _select =
      'id, group_id, owner_id, name, tray_url, created_at, '
      'stickers(id, pack_id, url, emojis, position)';

  // ------------------------------------------------------------
  // Read
  // ------------------------------------------------------------

  Future<List<EfocStickerPack>> fetchPacks(String groupId) async {
    final myId = _client.auth.currentUser?.id;
    final rows = await _client
        .from('sticker_packs')
        .select(_select)
        .eq('group_id', groupId)
        .order('created_at', ascending: true);

    return rows
        .map((r) => EfocStickerPack.fromRow(r, myId: myId))
        .where((p) => p.stickers.isNotEmpty)
        .toList();
  }

  // ------------------------------------------------------------
  // Write
  // ------------------------------------------------------------

  /// Uploads [drafts] as a new pack. Each sticker is its own object under
  /// `{group}/{pack}/`, so one bad file doesn't take the pack down.
  Future<EfocStickerPack> createPack({
    required String groupId,
    required String name,
    required List<StickerDraft> drafts,
    StickerDraft? tray,
    void Function(int done, int total)? onProgress,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');
    if (drafts.isEmpty) throw Exception('No stickers to upload');

    final pack = await _client
        .from('sticker_packs')
        .insert({
          'group_id': groupId,
          'owner_id': userId,
          'name': name.trim().isEmpty ? 'Stickers' : name.trim(),
        })
        .select('id')
        .single();
    final packId = pack['id'] as String;

    try {
      String? trayUrl;
      if (tray != null) {
        trayUrl = await _upload(
          tray.bytes,
          tray.extension,
          '$groupId/$packId/tray.${tray.extension}',
        );
        await _client
            .from('sticker_packs')
            .update({'tray_url': trayUrl}).eq('id', packId);
      }

      // Upload in small waves, then one insert for the rows.
      final urls = List<String?>.filled(drafts.length, null);
      var done = 0;
      for (var start = 0; start < drafts.length; start += _parallelism) {
        final end = (start + _parallelism).clamp(0, drafts.length);
        await Future.wait([
          for (var i = start; i < end; i++)
            _upload(
              drafts[i].bytes,
              drafts[i].extension,
              '$groupId/$packId/$i.${drafts[i].extension}',
            ).then((url) {
              urls[i] = url;
              done++;
              onProgress?.call(done, drafts.length);
            }),
        ]);
      }

      await _client.from('stickers').insert([
        for (var i = 0; i < drafts.length; i++)
          if (urls[i] != null)
            {
              'pack_id': packId,
              'url': urls[i],
              'emojis': drafts[i].emojis,
              'position': i,
            },
      ]);

      final row = await _client
          .from('sticker_packs')
          .select(_select)
          .eq('id', packId)
          .single();
      return EfocStickerPack.fromRow(row, myId: userId);
    } catch (e) {
      // Don't leave half a pack behind in the group's picker.
      try {
        await _client.from('sticker_packs').delete().eq('id', packId);
      } catch (_) {}
      rethrow;
    }
  }

  /// Deletes a pack and the files behind it. Stickers already sent in a chat
  /// keep drawing, because each message carries its own copy of the URL.
  Future<void> deletePack(String packId) async {
    final paths = <String>[];

    final stickers =
        await _client.from('stickers').select('url').eq('pack_id', packId);
    for (final row in stickers) {
      final path = _pathOf(row['url'] as String?);
      if (path != null) paths.add(path);
    }

    final pack = await _client
        .from('sticker_packs')
        .select('tray_url')
        .eq('id', packId)
        .maybeSingle();
    final trayPath = _pathOf(pack?['tray_url'] as String?);
    if (trayPath != null) paths.add(trayPath);

    // Rows first: a failed delete should not leave stickers pointing at
    // missing files.
    await _client.from('sticker_packs').delete().eq('id', packId);

    if (paths.isNotEmpty) {
      try {
        await _client.storage.from(_bucket).remove(paths);
      } catch (_) {
        // Orphaned objects are cheap; a failed pack delete is not.
      }
    }
  }

  /// Turns a public sticker URL back into its object path.
  static String? _pathOf(String? url) {
    if (url == null) return null;
    final marker = '/$_bucket/';
    final i = url.indexOf(marker);
    if (i < 0) return null;
    return Uri.decodeComponent(url.substring(i + marker.length));
  }

  Future<String> _upload(
    Uint8List bytes,
    String extension,
    String path,
  ) async {
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentTypeFor(extension),
            upsert: true,
            // Stickers never change at a given path, so let the CDN keep them.
            cacheControl: '31536000',
          ),
        );
    return _client.storage.from(_bucket).getPublicUrl(path);
  }

  // ------------------------------------------------------------
  // .wastickers
  // ------------------------------------------------------------
  //
  // A .wastickers is a ZIP holding `contents.json`, `title.txt` and the
  // sticker images. contents.json is either one pack object or
  // `{"sticker_packs": [ ... ]}`; each sticker is
  // `{"image_file": "01.webp", "emojis": ["😀"]}`.
  //
  // There is no export in WhatsApp itself. Packs are produced by sticker
  // makers (Sticker Maker, Sticker.ly) and traded as this file.

  /// Throws [FormatException] when [bytes] isn't a usable pack.
  static ImportedPack parseWastickers(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        "That file isn't a sticker pack. Pick a .wastickers file.",
      );
    }

    final files = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      files[_normalise(f.name)] = f;
    }

    String? contentsKey;
    for (final key in files.keys) {
      if (key == 'contents.json' || key.endsWith('/contents.json')) {
        contentsKey = key;
        break;
      }
    }
    if (contentsKey == null) {
      throw const FormatException(
        "That pack has no contents.json — is it a .wastickers file?",
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(files[contentsKey]!.content))
          as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException("That pack's contents.json is unreadable.");
    }

    final pack = json['sticker_packs'] is List
        ? (json['sticker_packs'] as List).first as Map<String, dynamic>
        : json;

    final base = contentsKey.substring(0, contentsKey.length - 13); // + slash
    final name = (pack['name'] as String?)?.trim();

    final drafts = <StickerDraft>[];
    for (final entry in (pack['stickers'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final imageFile = entry['image_file'] as String?;
      if (imageFile == null) continue;

      final found = _find(files, base, imageFile);
      if (found == null) continue;

      drafts.add(
        StickerDraft(
          bytes: _bytesOf(found),
          extension: imageExtension(_bytesOf(found), fileName: imageFile),
          emojis: (entry['emojis'] as List?)?.cast<String>() ?? const [],
        ),
      );
    }

    if (drafts.isEmpty) {
      throw const FormatException('That pack has no stickers in it.');
    }

    final trayFile = pack['tray_image_file'] as String?;
    final trayEntry = trayFile == null ? null : _find(files, base, trayFile);

    return ImportedPack(
      name: name == null || name.isEmpty ? 'Imported stickers' : name,
      tray: trayEntry == null
          ? null
          : StickerDraft(
              bytes: _bytesOf(trayEntry),
              extension: imageExtension(
                _bytesOf(trayEntry),
                fileName: trayFile,
              ),
            ),
      stickers: drafts,
    );
  }

  static String _normalise(String name) =>
      name.replaceAll('\\', '/').toLowerCase();

  static ArchiveFile? _find(
    Map<String, ArchiveFile> files,
    String base,
    String imageFile,
  ) {
    final key = _normalise(imageFile);
    final candidates = [
      '$base$key',
      key,
      if (key.contains('/')) key.substring(key.lastIndexOf('/') + 1),
    ];
    for (final c in candidates) {
      final hit = files[c];
      if (hit != null) return hit;
    }
    // Last resort: same base name anywhere in the zip.
    final baseName = key.substring(key.lastIndexOf('/') + 1);
    for (final entry in files.entries) {
      if (entry.key.endsWith('/$baseName') || entry.key == baseName) {
        return entry.value;
      }
    }
    return null;
  }

  static Uint8List _bytesOf(ArchiveFile file) => file.content;
}

/// `webp`/`png`/`gif`/`jpg`, from the file name or the magic bytes.
String imageExtension(Uint8List bytes, {String? fileName}) {
  final name = fileName?.toLowerCase() ?? '';
  for (final ext in const ['webp', 'png', 'gif', 'jpg', 'jpeg']) {
    if (name.endsWith('.$ext')) return ext == 'jpeg' ? 'jpg' : ext;
  }
  if (bytes.length >= 4) {
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[8] == 0x57) {
      return 'webp'; // RIFF....WEBP
    }
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
    if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
  }
  return 'png';
}

String contentTypeFor(String extension) {
  return switch (extension) {
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'jpg' => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    _ => 'image/png',
  };
}
