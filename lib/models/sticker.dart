import 'package:flutter/foundation.dart';

/// One sticker in a pack. [url] is a public, immutable CDN URL: a sticker's
/// bytes never change once uploaded, so the URL is cached forever by the
/// browser and by Flutter's image cache.
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

/// A set of stickers shared by one Log. Members can send any sticker in it.
@immutable
class EfocStickerPack {
  final String id;
  final String groupId;
  final String name;
  final String? trayUrl;
  final bool isMine;
  final List<EfocSticker> stickers;

  const EfocStickerPack({
    required this.id,
    required this.groupId,
    required this.name,
    required this.trayUrl,
    required this.isMine,
    required this.stickers,
  });

  /// The tab icon: the pack's tray, or its first sticker when a pack was
  /// imported without one.
  String? get iconUrl =>
      trayUrl ?? (stickers.isEmpty ? null : stickers.first.url);

  factory EfocStickerPack.fromRow(
    Map<String, dynamic> row, {
    String? myId,
  }) {
    final rows = (row['stickers'] as List?) ?? const [];
    final stickers = rows
        .cast<Map<String, dynamic>>()
        .map(EfocSticker.fromRow)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return EfocStickerPack(
      id: row['id'] as String,
      groupId: row['group_id'] as String,
      name: (row['name'] as String?) ?? 'Stickers',
      trayUrl: row['tray_url'] as String?,
      isMine: myId != null && row['owner_id'] == myId,
      stickers: stickers,
    );
  }
}
