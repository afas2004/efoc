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

  Future<List<EfocMessage>> fetchMessages({
    required String groupId,
    int limit = 100,
  }) async {
    final userId = _client.auth.currentUser?.id;

    final rows = await _client
        .from('messages')
        .select(
          'id, group_id, user_id, text, clip_id, reply_to_id, created_at, '
          'author:profiles!messages_user_id_fkey(display_name, username, avatar_url), '
          'reply:reply_to_id(id, text, user_id, '
          '  author:profiles!messages_user_id_fkey(display_name, username)), '
          'clip:clip_id(id, storage_path)',
        )
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .limit(limit);
    if (rows.isNotEmpty) {
      debugPrint('=== RAW ROW ===');
      debugPrint('KEYS: ${rows.first.keys.toList()}');
      debugPrint('AUTHOR: ${rows.first['author']}');
    }

    final ids = rows.map((r) => r['id'] as String).toList();
    final Map<String, Map<String, List<String>>> reactionsByMessage = {};
    if (ids.isNotEmpty) {
      final rx = await _client
          .from('message_reactions')
          .select('message_id, user_id, emoji')
          .inFilter('message_id', ids);

      for (final r in rx) {
        final mid = r['message_id'] as String;
        final emoji = r['emoji'] as String;
        final uid = r['user_id'] as String;
        reactionsByMessage
            .putIfAbsent(mid, () => {})
            .putIfAbsent(emoji, () => [])
            .add(uid);
      }
    }

    final messages = rows.map((row) {
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

      final String? replyPreviewText =
          hasReply ? (reply?['text'] as String?) : null;

      return EfocMessage(
        id: row['id'] as String,
        groupId: row['group_id'] as String,
        userId: row['user_id'] as String,
        text: row['text'] as String?,
        clipId: row['clip_id'] as String?,
        clipStoragePath: clip?['storage_path'] as String?,
        replyToId: row['reply_to_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        senderName: (profile?['display_name'] as String?)?.trim().isNotEmpty ==
                true
            ? profile!['display_name'] as String
            : (profile?['username'] as String? ?? 'User'),
        senderColor: _colorForId(row['user_id'] as String),
        senderAvatarUrl: profile?['avatar_url'] as String?,
        isMe: row['user_id'] == userId,
        replyPreviewText: replyPreviewText,
        replySenderName: replySenderName,
        reactions: reactionsByMessage[row['id']] ?? const {},
      );
    }).toList();

    return messages.reversed.toList();
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

  Future<void> deleteMessage(String id) async {
    await _client.from('messages').delete().eq('id', id);
  }

  Future<void> toggleReaction({
    required String messageId,
    required String emoji,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final existing = await _client
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .eq('emoji', emoji)
        .maybeSingle();

    if (existing != null) {
      await _client.from('message_reactions').delete().eq('id', existing['id']);
    } else {
      await _client.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': userId,
        'emoji': emoji,
      });
    }
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