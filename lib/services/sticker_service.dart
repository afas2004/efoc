import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
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

/// Packs belong to people, the tray belongs to the viewer.
///
/// The split that matters: `sticker_packs` + `stickers` are the pack (owned by
/// one user, readable by anyone signed in), `sticker_pack_installs` is what
/// lands in *your* tray. Sending never depends on either — a message carries
/// its own sticker URL.
class StickerService {
  StickerService._();
  static final StickerService instance = StickerService._();

  SupabaseClient get _client => Supabase.instance.client;

  static const _bucket = 'stickers';

  /// How many stickers upload at once.
  static const _parallelism = 5;

  static const _select =
      'id, owner_id, slug, name, tray_url, created_at, '
      'stickers(id, pack_id, url, emojis, position)';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw Exception('Not signed in');
    return id;
  }

  // ------------------------------------------------------------
  // The tray
  // ------------------------------------------------------------

  /// Installed packs, most recently used first. Archived ones included; the
  /// caller splits them so it can show the archive separately.
  Future<List<EfocStickerPack>> fetchTray() async {
    final rows = await _client
        .from('sticker_pack_installs')
        .select('archived, last_used_at, pack:sticker_packs($_select)')
        .eq('user_id', _uid)
        .order('last_used_at', ascending: false);

    return rows
        .where((r) => r['pack'] != null)
        .map(
          (r) => EfocStickerPack.fromRow(
            r['pack'] as Map<String, dynamic>,
            myId: _uid,
            installed: true,
            archived: (r['archived'] as bool?) ?? false,
          ),
        )
        .toList();
  }

  /// Ids the viewer already has, so a received sticker can offer "Add pack"
  /// only when it is actually missing.
  Future<Set<String>> installedIds() async {
    final rows = await _client
        .from('sticker_pack_installs')
        .select('pack_id')
        .eq('user_id', _uid);
    return rows.map((r) => r['pack_id'] as String).toSet();
  }

  /// A pack anyone can open from a share link, installed or not.
  Future<EfocStickerPack?> fetchBySlug(String slug) async {
    final row = await _client
        .from('sticker_packs')
        .select(_select)
        .eq('slug', slug)
        .maybeSingle();
    if (row == null) return null;

    final install = await _client
        .from('sticker_pack_installs')
        .select('archived')
        .eq('user_id', _uid)
        .eq('pack_id', row['id'])
        .maybeSingle();

    return EfocStickerPack.fromRow(
      row,
      myId: _uid,
      installed: install != null,
      archived: (install?['archived'] as bool?) ?? false,
    );
  }

  // ------------------------------------------------------------
  // Install / remove
  // ------------------------------------------------------------

  /// Adds the pack to the tray. The database archives the least recently used
  /// pack once the tray is full, so this never fails for being full.
  Future<void> install(String packId) async {
    await _client.rpc(
      'install_sticker_pack',
      params: {'p_pack': packId},
    );
  }

  Future<void> uninstall(String packId) async {
    await _client
        .from('sticker_pack_installs')
        .delete()
        .eq('user_id', _uid)
        .eq('pack_id', packId);
  }

  /// Sending a sticker moves its pack to the front of the tray.
  Future<void> touch(String packId) async {
    try {
      await _client.rpc('touch_sticker_pack', params: {'p_pack': packId});
    } catch (_) {
      // Ordering is a nicety; never fail a send over it.
    }
  }

  // ------------------------------------------------------------
  // Creating and filling packs
  // ------------------------------------------------------------

  Future<EfocStickerPack> createPack({
    required String name,
    required List<StickerDraft> drafts,
    StickerDraft? tray,
    void Function(int done, int total)? onProgress,
  }) async {
    if (drafts.isEmpty) throw Exception('No stickers to upload');
    final uid = _uid;
    final slug = await _uniqueSlug(name);

    final inserted = await _client
        .from('sticker_packs')
        .insert({
          'owner_id': uid,
          'slug': slug,
          'name': name.trim().isEmpty ? 'Stickers' : name.trim(),
        })
        .select('id')
        .single();
    final packId = inserted['id'] as String;

    try {
      String? trayUrl;
      if (tray != null) {
        trayUrl = await _upload(
          tray.bytes,
          tray.extension,
          '$uid/$packId/tray.${tray.extension}',
        );
        await _client
            .from('sticker_packs')
            .update({'tray_url': trayUrl}).eq('id', packId);
      }

      await _uploadAll(
        packId: packId,
        ownerId: uid,
        drafts: drafts,
        onProgress: onProgress,
      );

      final row = await _client
          .from('sticker_packs')
          .select(_select)
          .eq('id', packId)
          .single();
      return EfocStickerPack.fromRow(row, myId: uid, installed: true);
    } catch (e) {
      try {
        await _client.from('sticker_packs').delete().eq('id', packId);
      } catch (_) {}
      rethrow;
    }
  }

  /// Tops up a pack the viewer owns.
  Future<EfocStickerPack> addStickers({
    required EfocStickerPack pack,
    required List<StickerDraft> drafts,
    void Function(int done, int total)? onProgress,
  }) async {
    if (drafts.isEmpty) throw Exception('No stickers to upload');
    if (!pack.isMine) throw Exception('Only the owner can add stickers');
    final uid = _uid;

    await _uploadAll(
      packId: pack.id,
      ownerId: uid,
      drafts: drafts,
      startPosition: pack.count,
      namePrefix: '${DateTime.now().millisecondsSinceEpoch}_',
      onProgress: onProgress,
    );

    final row = await _client
        .from('sticker_packs')
        .select(_select)
        .eq('id', pack.id)
        .single();
    return EfocStickerPack.fromRow(row, myId: uid, installed: true);
  }

  Future<void> _uploadAll({
    required String packId,
    required String ownerId,
    required List<StickerDraft> drafts,
    int startPosition = 0,
    String namePrefix = '',
    void Function(int done, int total)? onProgress,
  }) async {
    final urls = List<String?>.filled(drafts.length, null);
    var done = 0;

    for (var start = 0; start < drafts.length; start += _parallelism) {
      final end = (start + _parallelism).clamp(0, drafts.length);
      await Future.wait([
        for (var i = start; i < end; i++)
          _upload(
            drafts[i].bytes,
            drafts[i].extension,
            '$ownerId/$packId/$namePrefix$i.${drafts[i].extension}',
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
            'position': startPosition + i,
          },
    ]);
  }

  Future<void> deletePack(EfocStickerPack pack) async {
    final paths = <String>[];
    for (final sticker in pack.stickers) {
      final path = _pathOf(sticker.url);
      if (path != null) paths.add(path);
    }
    final trayPath = _pathOf(pack.trayUrl);
    if (trayPath != null) paths.add(trayPath);

    await _client.from('sticker_packs').delete().eq('id', pack.id);

    if (paths.isNotEmpty) {
      try {
        await _client.storage.from(_bucket).remove(paths);
      } catch (_) {
        // Orphaned objects are cheap; a failed delete is not.
      }
    }
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

  /// Turns a public sticker URL back into its object path.
  static String? _pathOf(String? url) {
    if (url == null) return null;
    final marker = '/$_bucket/';
    final i = url.indexOf(marker);
    if (i < 0) return null;
    return Uri.decodeComponent(url.substring(i + marker.length));
  }

  // ------------------------------------------------------------
  // Slugs
  // ------------------------------------------------------------

  /// `Kopi Gang` → `kopi-gang`, then `kopi-gang-2` if that is taken.
  Future<String> _uniqueSlug(String name) async {
    final base = slugify(name);
    for (var attempt = 1; attempt <= 20; attempt++) {
      final candidate = attempt == 1 ? base : '$base-$attempt';
      final hit = await _client
          .from('sticker_packs')
          .select('id')
          .eq('slug', candidate)
          .maybeSingle();
      if (hit == null) return candidate;
    }
    return '$base-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  static String slugify(String name) {
    final s = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.isEmpty) return 'stickers';
    return s.length > 40 ? s.substring(0, 40).replaceAll(RegExp(r'-+$'), '') : s;
  }

  // ------------------------------------------------------------
  // Export
  // ------------------------------------------------------------

  /// Writes the pack back out as a `.wastickers` file, for leaving efoc —
  /// into WhatsApp, or to someone who isn't in the app.
  Future<Uint8List> exportWastickers(EfocStickerPack pack) async {
    final archive = Archive();
    final entries = <Map<String, dynamic>>[];

    for (var i = 0; i < pack.stickers.length; i++) {
      final sticker = pack.stickers[i];
      final bytes = await _download(sticker.url);
      final ext = imageExtension(bytes, fileName: sticker.url);
      final name = '${i.toString().padLeft(2, '0')}.$ext';
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      entries.add({'image_file': name, 'emojis': sticker.emojis});
    }
    if (entries.isEmpty) throw Exception('This pack has no stickers');

    String? trayName;
    final trayUrl = pack.trayUrl;
    if (trayUrl != null) {
      try {
        final bytes = await _download(trayUrl);
        final ext = imageExtension(bytes, fileName: trayUrl);
        trayName = 'tray.$ext';
        archive.addFile(ArchiveFile(trayName, bytes.length, bytes));
      } catch (_) {
        // A missing tray is not worth failing the export over.
      }
    }

    final contents = <String, dynamic>{
      'identifier': pack.slug,
      'name': pack.name,
      'publisher': 'efoc',
      'tray_image_file': trayName ?? entries.first['image_file'],
      'image_data_version': '1',
      'avoid_cache': false,
      'animated_sticker_pack': false,
      'stickers': entries,
    };
    final contentsBytes = utf8.encode(jsonEncode(contents));
    archive.addFile(
      ArchiveFile('contents.json', contentsBytes.length, contentsBytes),
    );
    final titleBytes = utf8.encode(pack.name);
    archive.addFile(ArchiveFile('title.txt', titleBytes.length, titleBytes));

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<Uint8List> _download(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Could not fetch a sticker (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  // ------------------------------------------------------------
  // .wastickers
  // ------------------------------------------------------------

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

      final stickerBytes = _bytesOf(found);
      drafts.add(
        StickerDraft(
          bytes: stickerBytes,
          extension: imageExtension(stickerBytes, fileName: imageFile),
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
