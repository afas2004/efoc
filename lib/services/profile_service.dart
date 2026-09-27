import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>?> fetchMyProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    return await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
  }

  /// Updates display name for a specific user id.
  /// Returns the updated row on success, or null if the write didn't
  /// land (RLS blocked, auth flipped, row missing, etc.).
  Future<Map<String, dynamic>?> updateDisplayName({
    required String targetUserId,
    required String displayName,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != targetUserId) return null;

    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return null;

    final rows = await _client
        .from('profiles')
        .update({
          'display_name': trimmed,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', targetUserId)
        .select('id, display_name');

    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Uploads [bytes] as the user's avatar and updates profiles.avatar_url.
  /// Returns the new public URL (with a cache-buster) on success, or null
  /// if auth flipped or the DB write was blocked.
  ///
  /// Path is overwritten on each upload, so the file lives at a stable
  /// location: {user_id}/avatar.png
  Future<String?> uploadAvatar({
    required String targetUserId,
    required Uint8List bytes,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != targetUserId) return null;

    final path = '$targetUserId/avatar.png';

    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );

    final baseUrl = _client.storage.from('avatars').getPublicUrl(path);
    final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';

    final rows = await _client
        .from('profiles')
        .update({
          'avatar_url': url,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', targetUserId)
        .select('id, avatar_url');

    if (rows.isEmpty) return null;
    return url;
  }
}