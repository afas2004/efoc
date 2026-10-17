import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vlog.dart';
import 'save_file.dart';

class VlogService {
  VlogService._();
  static final VlogService instance = VlogService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Vlogs for [groupIds] recorded on or after [since].
  Future<List<EfocVlog>> fetchRecent({
    required List<String> groupIds,
    required DateTime since,
  }) async {
    if (groupIds.isEmpty) return [];
    final rows = await _client
        .from('vlogs')
        .select(
          'id, group_id, vlog_date, storage_path, thumbnail_path, clip_count, duration_seconds',
        )
        .inFilter('group_id', groupIds)
        .gte('vlog_date', _dateString(since));
    return rows.map(EfocVlog.fromRow).toList();
  }

  /// Ids of the vlogs in [vlogIds] the current user has already watched.
  Future<Set<String>> fetchViewedIds(List<String> vlogIds) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || vlogIds.isEmpty) return {};
    final rows = await _client
        .from('vlog_views')
        .select('vlog_id')
        .eq('user_id', userId)
        .inFilter('vlog_id', vlogIds);
    return rows.map((r) => r['vlog_id'] as String).toSet();
  }

  Future<void> markViewed(String vlogId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('vlog_views').upsert(
      {'user_id': userId, 'vlog_id': vlogId},
      onConflict: 'user_id,vlog_id',
      ignoreDuplicates: true,
    );
  }

  Future<String> signedUrl(String storagePath) {
    return _client.storage.from('vlogs').createSignedUrl(storagePath, 3600);
  }

  /// Downloads the vlog to the phone (a browser download on the web, the
  /// share sheet in the Android app).
  Future<void> shareVlog(EfocVlog vlog, {required String groupName}) async {
    final url = await signedUrl(vlog.storagePath);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }
    final name = 'efoc-${_slug(groupName)}-${_dateString(vlog.date)}.mp4';
    // Straight to Downloads on the web; share sheet in the Android app.
    await saveVideo(response.bodyBytes, name);
  }

  String _slug(String s) {
    final slug = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return slug.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _dateString(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
