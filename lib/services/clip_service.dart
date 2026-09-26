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

  Future<String> getSignedUrl(String storagePath) async {
    final cached = _signedUrlCache[storagePath];
    if (cached != null) return cached;

    final url = await _client.storage
        .from('clips')
        .createSignedUrl(storagePath, 3600);

    _signedUrlCache[storagePath] = url;
    return url;
  }

  /// Public URL for a clip's thumbnail. Works because the clips bucket
  /// allows public SELECT on `.jpg` files.
  String? publicThumbnailUrl(String storagePath) {
    String thumbPath;
    if (storagePath.endsWith('.mp4')) {
      thumbPath = storagePath.replaceAll('.mp4', '.jpg');
    } else if (storagePath.endsWith('.webm')) {
      thumbPath = storagePath.replaceAll('.webm', '.jpg');
    } else if (storagePath.endsWith('.mov')) {
      thumbPath = storagePath.replaceAll('.mov', '.jpg');
    } else {
      return null;
    }
    return _client.storage.from('clips').getPublicUrl(thumbPath);
  }

  // ---------- upload ----------

  Future<void> uploadClip({
    required String filePath,
    required String groupId,
    required int hour,
    required String text,
    required String fontKey,
    required String textColorHex,
    required String ratio,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    // 1. Prepare bytes + path
    final Uint8List bytes = await _readFileBytes(filePath);
    final ext = _extFromPath(filePath);

    final now = DateTime.now();
    final dateStr = _dateString(now);
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
      },
      onConflict: 'user_id,group_id,hour_of_day,recorded_on',
    );
  }

  Future<void> _extractAndUploadThumbnail({
    required String videoPath,
    required String storagePath,
  }) async {
    final thumbPath =
        storagePath.replaceAll(RegExp(r'\.(mp4|webm|mov)$'), '.jpg');

    try {
      final bytes = await extractThumbnailJpeg(videoPath);
      if (bytes == null) {
        debugPrint('Thumbnail extraction returned null for $videoPath');
        return;
      }

      await _client.storage.from('clips').uploadBinary(
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

  String _extFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'mp4';
    return path.substring(dot + 1).toLowerCase();
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