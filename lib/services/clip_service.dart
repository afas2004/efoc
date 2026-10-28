import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'thumbnail_extractor.dart';

class ClipService {
  ClipService._();
  static final ClipService instance = ClipService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------- signed URL cache ----------
  final Map<String, String> _signedUrlCache = {};

  /// Drops cached signed URLs. Call on logout so a new user
  /// doesn't inherit another session's URLs.
  void clearCache() {
    _signedUrlCache.clear();
  }

  Future<String> getSignedUrl(String storagePath) async {
    final cached = _signedUrlCache[storagePath];
    if (cached != null) return cached;

    final url = await _client.storage
        .from('clips')
        .createSignedUrl(storagePath, 3600);

    _signedUrlCache[storagePath] = url;
    return url;
  }

  /// Public URL for a clip's thumbnail. Thumbnails live in their own
  /// public bucket, at the same path as the video but with a .jpg extension.
  String? publicThumbnailUrl(String storagePath) {
    final match = _videoExt.firstMatch(storagePath);
    // Older uploads from the web app had no real extension (the blob URL's
    // domain leaked in, e.g. `.party/<uuid>`), so their thumbnail was
    // stored under the exact same path as the video.
    final thumbPath = match == null
        ? storagePath
        : storagePath.replaceRange(match.start, match.end, '.jpg');
    return _client.storage.from('thumbnails').getPublicUrl(thumbPath);
  }

  static final _videoExt = RegExp(r'\.(mp4|webm|mov)$');

  // ---------- upload ----------

  /// How long after an hour ends a clip can still be sent for it, so a
  /// take started at 3:59 isn't lost at 4:00. The clips_hour_open trigger
  /// in supabase/migrations enforces the same window server-side.
  static const hourGrace = Duration(minutes: 5);

  /// The day [hour]'s slot belongs to if it can still take a clip at [now]:
  /// the current hour, or the one just ended while inside [hourGrace].
  /// Null once the slot has closed (or for a future hour).
  static DateTime? openSlotDay(int hour, [DateTime? now]) {
    final t = now ?? DateTime.now();
    if (hour == t.hour) return t;
    final graced = t.subtract(hourGrace);
    if (hour == graced.hour) return graced;
    return null;
  }

  Future<void> uploadClip({
    required String filePath,
    required String groupId,
    required int hour,
    required String text,
    required String fontKey,
    required String textColorHex,
    required String ratio,
    String? mimeType,
    double? textX,
    double? textY,
    int rotation = 0,
    String? textBg,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    // 1. Prepare bytes + path
    final Uint8List bytes = await _readFileBytes(filePath);
    final ext = _extFor(filePath, mimeType);

    // Dated by the slot's own day, so 11 PM sent at 12:03 AM stays yesterday.
    final slotDay = openSlotDay(hour);
    if (slotDay == null) throw const HourClosedException();
    final dateStr = _dateString(slotDay);
    final hourStr = hour.toString().padLeft(2, '0');
    final storagePath = '$groupId/$userId/$hourStr-$dateStr.$ext';

    // 2. Upload video
    await _client.storage.from('clips').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(ext),
            upsert: true,
          ),
        );

    // 3. Extract + upload thumbnail (runs on both web and native)
    await _extractAndUploadThumbnail(
      videoPath: filePath,
      storagePath: storagePath,
    );

    // 4. Upsert clip row
    debugPrint(
      'SEND hour=$hour date=$dateStr user=$userId group=$groupId path=$storagePath',
    );
    await _client.from('clips').upsert(
      {
        'user_id': userId,
        'group_id': groupId,
        'storage_path': storagePath,
        'hour_of_day': hour,
        'recorded_on': dateStr,
        'aspect_ratio': ratio.replaceAll('x', ':'),
        'text_overlay': text.isEmpty ? null : text,
        'text_font': fontKey,
        'text_color': textColorHex,
        'text_x': textX,
        'text_y': textY,
        'rotation': rotation,
        'text_bg': textBg,
      },
      onConflict: 'user_id,group_id,hour_of_day,recorded_on',
    );
  }

  Future<void> _extractAndUploadThumbnail({
    required String videoPath,
    required String storagePath,
  }) async {
    final thumbPath = storagePath.replaceAll(_videoExt, '.jpg');

    try {
      final bytes = await extractThumbnailJpeg(videoPath);
      if (bytes == null) {
        debugPrint('Thumbnail extraction returned null for $videoPath');
        return;
      }

        await _client.storage.from('thumbnails').uploadBinary(
            thumbPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      debugPrint('Thumbnail uploaded: $thumbPath');
    } catch (e) {
      // Non-fatal — the grid falls back to a gradient.
      debugPrint('Thumbnail failed: $e');
    }
  }

  // ---------- fetch ----------

  Future<Map<String, Map<String, dynamic>>> fetchClipsForDay({
    required String groupId,
    required DateTime date,
  }) async {
    final dateStr = _dateString(date);

    final rows = await _client
        .from('clips')
        .select()
        .eq('group_id', groupId)
        .eq('recorded_on', dateStr);

    final map = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final userId = row['user_id'] as String;
      final hour = row['hour_of_day'] as int;
      map['$userId-$hour'] = row;
    }
    return map;
  }

  // ---------- seen tracking ----------

  /// Ids in [clipIds] the current user has already watched.
  Future<Set<String>> fetchViewedIds(List<String> clipIds) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || clipIds.isEmpty) return {};
    final rows = await _client
        .from('clip_views')
        .select('clip_id')
        .eq('user_id', userId)
        .inFilter('clip_id', clipIds);
    return rows.map((r) => r['clip_id'] as String).toSet();
  }

  Future<void> markViewed(String clipId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('clip_views').upsert(
      {'user_id': userId, 'clip_id': clipId},
      onConflict: 'user_id,clip_id',
      ignoreDuplicates: true,
    );
  }

  /// Unwatched clips from other members, keyed by `groupId|yyyy-mm-dd`.
  Future<Map<String, int>> fetchUnseenCounts({required DateTime since}) async {
    final rows = await _client.rpc(
      'unseen_clip_counts',
      params: {'since': _dateString(since)},
    ) as List<dynamic>;
    return {
      for (final r in rows)
        '${r['group_id']}|${r['recorded_on']}': r['unseen'] as int,
    };
  }

  RealtimeChannel subscribeToGroupClips({
    required String groupId,
    required void Function() onChange,
  }) {
    final channel = _client
        .channel('clips-$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'clips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  // ============================================================
  // Helpers
  // ============================================================

  Future<Uint8List> _readFileBytes(String path) async {
    if (kIsWeb) {
      final response = await http.get(Uri.parse(path));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch blob: ${response.statusCode}');
      }
      return response.bodyBytes;
    } else {
      final file = File(path);
      if (!file.existsSync()) throw Exception('File not found: $path');
      return await file.readAsBytes();
    }
  }

  /// Picks the file extension from the file name, falling back to the
  /// recorder's MIME type. Web recordings are blob URLs with no extension.
  String _extFor(String path, String? mimeType) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot >= 0) {
      final ext = name.substring(dot + 1).toLowerCase();
      if (const {'mp4', 'webm', 'mov'}.contains(ext)) return ext;
    }
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('quicktime')) return 'mov';
    if (mime.isEmpty && kIsWeb) return 'webm';
    return 'mp4';
  }

  String _contentTypeFor(String ext) {
    switch (ext) {
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }

  String _dateString(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

/// Thrown when a clip is sent for an hour that is no longer open.
class HourClosedException implements Exception {
  const HourClosedException();

  @override
  String toString() => 'That hour has closed';
}
