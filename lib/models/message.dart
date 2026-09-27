import 'package:flutter/material.dart';

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

  /// emoji -> list of user ids who reacted with it.
  final Map<String, List<String>> reactions;

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
}