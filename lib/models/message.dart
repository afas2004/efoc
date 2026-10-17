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

class EfocMessage {
  final String id;
  final String groupId;
  final String userId;
  final String? text;
  final String? clipId;
  final String? clipStoragePath;
  final String? replyToId;
  final DateTime createdAt;

  final String senderName;
  final Color senderColor;
  final String? senderAvatarUrl;
  final bool isMe;

  final String? replyPreviewText;
  final String? replySenderName;

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
    required this.senderName,
    required this.senderColor,
    required this.senderAvatarUrl,
    required this.isMe,
    required this.replyPreviewText,
    required this.replySenderName,
    required this.reactions,
  });

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
      senderName: senderName,
      senderColor: senderColor,
      senderAvatarUrl: senderAvatarUrl,
      isMe: isMe,
      replyPreviewText: replyPreviewText,
      replySenderName: replySenderName,
      reactions: next,
    );
  }
}
