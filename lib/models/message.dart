import 'package:flutter/material.dart';

class EfocReaction {
  final String userId;
  final String emoji;
  final DateTime createdAt;
  final bool isMe;

  const EfocReaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
    required this.isMe,
  });
}

enum MessageKind { text, clip, vlog, sticker }

class EfocMessage {
  final String id;
  final String groupId;
  final String userId;
  final String? text;
  final String? clipId;
  final String? clipStoragePath;
  final String? replyToId;
  final DateTime createdAt;

  /// Clip and vlog cards are posted by database triggers (see
  /// supabase/migrations/20261018_clip_chat_cards.sql).
  final MessageKind kind;
  final String? vlogId;

  /// A sticker message's pack entry (null once the pack is deleted) and the
  /// copy of its public URL, which is what the bubble actually draws.
  final String? stickerId;
  final String? stickerUrl;

  /// Copies kept on the card so it still draws after the clip is deleted.
  /// Clip: the video's storage path. Vlog: its thumbnail path.
  final String? cardPath;
  final int? cardHour;
  final String? cardCaption;
  final DateTime? cardDate;

  final String senderName;
  final Color senderColor;
  final String? senderAvatarUrl;
  final bool isMe;

  final String? replyPreviewText;
  final String? replySenderName;
  final MessageKind? replyKind;
  final int? replyHour;

  /// At most one per person, newest first.
  final List<EfocReaction> reactions;

  const EfocMessage({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.text,
    required this.clipId,
    required this.clipStoragePath,
    required this.replyToId,
    required this.createdAt,
    this.kind = MessageKind.text,
    this.vlogId,
    this.stickerId,
    this.stickerUrl,
    this.cardPath,
    this.cardHour,
    this.cardCaption,
    this.cardDate,
    required this.senderName,
    required this.senderColor,
    required this.senderAvatarUrl,
    required this.isMe,
    required this.replyPreviewText,
    required this.replySenderName,
    this.replyKind,
    this.replyHour,
    required this.reactions,
  });

  bool get isCard => kind == MessageKind.clip || kind == MessageKind.vlog;

  bool get isSticker => kind == MessageKind.sticker;

  /// What Copy puts on the clipboard: the text, or a card's caption.
  String? get copyText {
    final t = isCard ? cardCaption : text;
    return (t == null || t.trim().isEmpty) ? null : t;
  }

  /// One line for reply previews.
  String get previewText => switch (kind) {
        MessageKind.text => text ?? '',
        MessageKind.clip => copyText ?? 'Clip',
        MessageKind.vlog => 'Daily vlog',
        MessageKind.sticker => 'Sticker',
      };

  /// Your current reaction, if any.
  String? get myReaction =>
      reactions.where((r) => r.isMe).map((r) => r.emoji).firstOrNull;

  /// Distinct emojis, most used first (ties: most recent first).
  List<String> get topEmojis {
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final order = reactions.map((r) => r.emoji).toSet().toList();
    order.sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return order;
  }

  /// Applies your reaction locally the way the server will: same emoji or
  /// null removes it, anything else adds or replaces it.
  EfocMessage withMyReaction(String? emoji, String myId) {
    final current = myReaction;
    final others = reactions.where((r) => !r.isMe).toList();
    final next = emoji == null || emoji == current
        ? others
        : [
            EfocReaction(
              userId: myId,
              emoji: emoji,
              createdAt: DateTime.now(),
              isMe: true,
            ),
            ...others,
          ];
    return EfocMessage(
      id: id,
      groupId: groupId,
      userId: userId,
      text: text,
      clipId: clipId,
      clipStoragePath: clipStoragePath,
      replyToId: replyToId,
      createdAt: createdAt,
      kind: kind,
      vlogId: vlogId,
      stickerId: stickerId,
      stickerUrl: stickerUrl,
      cardPath: cardPath,
      cardHour: cardHour,
      cardCaption: cardCaption,
      cardDate: cardDate,
      senderName: senderName,
      senderColor: senderColor,
      senderAvatarUrl: senderAvatarUrl,
      isMe: isMe,
      replyPreviewText: replyPreviewText,
      replySenderName: replySenderName,
      replyKind: replyKind,
      replyHour: replyHour,
      reactions: next,
    );
  }
}

MessageKind messageKindOf(String? s) => switch (s) {
      'clip' => MessageKind.clip,
      'vlog' => MessageKind.vlog,
      'sticker' => MessageKind.sticker,
      _ => MessageKind.text,
    };

/// 3 PM, 12 AM.
String formatHour12(int hour) {
  if (hour == 0) return '12 AM';
  if (hour < 12) return '$hour AM';
  if (hour == 12) return '12 PM';
  return '${hour - 12} PM';
}
