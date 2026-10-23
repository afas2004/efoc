import 'package:flutter/foundation.dart';

/// One sticker in a pack. [url] is a public, immutable CDN URL: a sticker's
/// bytes never change once uploaded, so the URL is cached forever.
@immutable
class EfocSticker {
  final String id;
  final String packId;
  final String url;
  final List<String> emojis;
  final int position;

  const EfocSticker({
    required this.id,
    required this.packId,
    required this.url,
    this.emojis = const [],
    this.position = 0,
  });

  factory EfocSticker.fromRow(Map<String, dynamic> row) {
    return EfocSticker(
      id: row['id'] as String,
      packId: row['pack_id'] as String,
      url: row['url'] as String,
      emojis: (row['emojis'] as List?)?.cast<String>() ?? const [],
      position: (row['position'] as int?) ?? 0,
    );
  }
}

/// A set of stickers owned by one person.
///
/// Packs are personal, not per-Log: the owner's tray carries them into every
/// chat. [installed] is whether THIS user has them in their tray, which is a
/// separate thing from owning them.
@immutable
class EfocStickerPack {
  final String id;
  final String ownerId;
  final String slug;
  final String name;
  final String? trayUrl;
  final bool isMine;
  final bool installed;
  final bool archived;
  final List<EfocSticker> stickers;

  const EfocStickerPack({
    required this.id,
    required this.ownerId,
    required this.slug,
    required this.name,
    required this.trayUrl,
    required this.isMine,
    required this.installed,
    required this.archived,
    required this.stickers,
  });

  int get count => stickers.length;

  /// The tab icon: the pack's tray, or its first sticker.
  String? get iconUrl =>
      trayUrl ?? (stickers.isEmpty ? null : stickers.first.url);

  /// What the share link carries.
  String get shareUrl => 'https://efoc.party/?pack=$slug';

  factory EfocStickerPack.fromRow(
    Map<String, dynamic> row, {
    String? myId,
    bool installed = false,
    bool archived = false,
  }) {
    final rows = (row['stickers'] as List?) ?? const [];
    final stickers = rows
        .cast<Map<String, dynamic>>()
        .map(EfocSticker.fromRow)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return EfocStickerPack(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      slug: row['slug'] as String,
      name: (row['name'] as String?) ?? 'Stickers',
      trayUrl: row['tray_url'] as String?,
      isMine: myId != null && row['owner_id'] == myId,
      installed: installed,
      archived: archived,
      stickers: stickers,
    );
  }
}
