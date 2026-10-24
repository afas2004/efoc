import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message.dart';

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  SupabaseClient get _client => Supabase.instance.client;

  static const _palette = [
    Color(0xFFA855F7),
    Color(0xFF06B6D4),
    Color(0xFF4ECDC4),
    Color(0xFFFF8A65),
    Color(0xFFC77DFF),
    Color(0xFFFFD93D),
    Color(0xFFB388FF),
    Color(0xFFEF5350),
  ];

  Color _colorForId(String id) {
    final hash =
        id.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }

  static const _select =
      'id, group_id, user_id, text, clip_id, reply_to_id, created_at, '
      'kind, vlog_id, sticker_pack_id, sticker_url, card_path, card_hour, '
      'card_rotation, '
      'card_caption, card_date, '
      'author:profiles!messages_user_id_fkey(display_name, username, avatar_url), '
      'reply:reply_to_id(id, text, user_id, kind, card_hour, card_caption, '
      '  sticker_url, '
      '  author:profiles!messages_user_id_fkey(display_name, username)), '
      'clip:clip_id(id, storage_path, rotation)';

  Future<List<EfocMessage>> fetchMessages({
    required String groupId,
    int limit = 100,
  }) async {
    final rows = await _client
        .from('messages')
        .select(_select)
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .limit(limit);
    final messages = await _toMessages(rows);
    return messages.reversed.toList();
  }

  /// The chat card a clip was posted as, if it has one.
  Future<EfocMessage?> fetchClipCard(String clipId) async {
    final rows = await _client
        .from('messages')
        .select(_select)
        .eq('kind', 'clip')
        .eq('clip_id', clipId)
        .limit(1);
    final messages = await _toMessages(rows);
    return messages.firstOrNull;
  }

  Future<List<EfocMessage>> _toMessages(List<Map<String, dynamic>> rows) async {
    final userId = _client.auth.currentUser?.id;

    final ids = rows.map((r) => r['id'] as String).toList();
    final Map<String, List<EfocReaction>> reactionsByMessage = {};
    if (ids.isNotEmpty) {
      final rx = await _client
          .from('message_reactions')
          .select('message_id, user_id, emoji, created_at')
          .inFilter('message_id', ids)
          .order('created_at', ascending: false);

      for (final r in rx) {
        final uid = r['user_id'] as String;
        reactionsByMessage
            .putIfAbsent(r['message_id'] as String, () => [])
            .add(
              EfocReaction(
                userId: uid,
                emoji: r['emoji'] as String,
                createdAt:
                    DateTime.parse(r['created_at'] as String).toLocal(),
                isMe: uid == userId,
              ),
            );
      }
    }

    return rows.map((row) {
      final profile = row['author'] as Map<String, dynamic>?;
      final reply = row['reply'] as Map<String, dynamic>?;
      final replyProfile = reply?['author'] as Map<String, dynamic>?;
      final clip = row['clip'] as Map<String, dynamic>?;

      // Reply context is null when there's no reply. Only compute
      // sender name / preview if a reply actually exists.
      final bool hasReply = reply != null;

      final String? replySenderName = hasReply
          ? ((replyProfile?['display_name'] as String?)
                          ?.trim()
                          .isNotEmpty ==
                      true
                  ? replyProfile!['display_name'] as String
                  : (replyProfile?['username'] as String? ?? 'User'))
          : null;

      final replyKind = hasReply ? messageKindOf(reply['kind'] as String?) : null;
      final replyCaption = (reply?['card_caption'] as String?)?.trim();
      final String? replyPreviewText = switch (replyKind) {
        null => null,
        MessageKind.text => reply!['text'] as String?,
        MessageKind.clip =>
          replyCaption?.isNotEmpty == true ? replyCaption : 'Clip',
        MessageKind.vlog => 'Daily vlog',
        // The quote draws the sticker itself; this is only the fallback.
        MessageKind.sticker => null,
      };

      final cardDate = row['card_date'] as String?;

      return EfocMessage(
        id: row['id'] as String,
        groupId: row['group_id'] as String,
        userId: row['user_id'] as String,
        text: row['text'] as String?,
        clipId: row['clip_id'] as String?,
        clipStoragePath: clip?['storage_path'] as String?,
        // The card's copy survives retention; the clip's row does not.
        clipRotation: (row['card_rotation'] as num?)?.toInt() ??
            (clip?['rotation'] as num?)?.toInt() ??
            0,
        replyToId: row['reply_to_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        kind: messageKindOf(row['kind'] as String?),
        vlogId: row['vlog_id'] as String?,
        stickerPackId: row['sticker_pack_id'] as String?,
        stickerUrl: row['sticker_url'] as String?,
        cardPath: row['card_path'] as String?,
        cardHour: row['card_hour'] as int?,
        cardCaption: row['card_caption'] as String?,
        cardDate: cardDate == null ? null : DateTime.parse(cardDate),
        senderName: (profile?['display_name'] as String?)?.trim().isNotEmpty ==
                true
            ? profile!['display_name'] as String
            : (profile?['username'] as String? ?? 'User'),
        senderColor: _colorForId(row['user_id'] as String),
        senderAvatarUrl: profile?['avatar_url'] as String?,
        isMe: row['user_id'] == userId,
        replyPreviewText: replyPreviewText,
        replySenderName: replySenderName,
        replyKind: replyKind,
        replyHour: reply?['card_hour'] as int?,
        replyStickerUrl: reply?['sticker_url'] as String?,
        reactions: reactionsByMessage[row['id']] ?? const [],
      );
    }).toList();
  }

  /// Group ids with a message from someone else since you last read them.
  Future<Set<String>> fetchUnreadGroupIds() async {
    final rows = await _client.rpc('unread_chat_groups') as List<dynamic>;
    return rows.map((r) => r as String).toSet();
  }

  /// Marks [groupId]'s chat as read up to now (server time).
  Future<void> markRead(String groupId) async {
    await _client.rpc('mark_chat_read', params: {'gid': groupId});
  }

  Future<void> sendText({
    required String groupId,
    required String text,
    String? replyToId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _client.from('messages').insert({
      'group_id': groupId,
      'user_id': userId,
      'text': trimmed,
      'reply_to_id': replyToId,
    });
  }

  /// Posts a sticker message. The URL is copied onto the message so the bubble
  /// still draws after the pack is deleted (same idea as a clip card's path).
  Future<void> sendSticker({
    required String groupId,
    required String stickerPackId,
    required String stickerUrl,
    String? replyToId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    await _client.from('messages').insert({
      'group_id': groupId,
      'user_id': userId,
      'kind': 'sticker',
      'sticker_pack_id': stickerPackId,
      'sticker_url': stickerUrl,
      'reply_to_id': replyToId,
    });
  }

  Future<void> deleteMessage(String id) async {    await _client.from('messages').delete().eq('id', id);
  }

  /// WhatsApp rules: one reaction per person. The same emoji again (or
  /// null) removes it, a different one replaces it.
  Future<void> react({
    required String messageId,
    required String? emoji,
  }) async {
    await _client.rpc(
      'react_to_message',
      params: {'mid': messageId, 'e': emoji},
    );
  }

  RealtimeChannel subscribe({
    required String groupId,
    required void Function() onChange,
  }) {
    return _client
        .channel('chat-$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (_) => onChange(),
        )
        .subscribe();
  }
}