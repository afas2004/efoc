import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'save_file.dart';

/// One on-demand vlog request (a row in public.exports).
class EfocExport {
  final String id;
  final String status; // queued | running | done | failed
  final String? storagePath;
  final int? clipCount;
  final String? error;
  final DateTime createdAt;
  final List<String> groupIds;

  /// Null = every hour.
  final List<int>? hours;

  const EfocExport({
    required this.id,
    required this.status,
    required this.storagePath,
    required this.clipCount,
    required this.error,
    required this.createdAt,
    this.groupIds = const [],
    this.hours,
  });

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isFinished => isDone || isFailed;

  factory EfocExport.fromRow(Map<String, dynamic> r) => EfocExport(
        id: r['id'] as String,
        status: r['status'] as String,
        storagePath: r['storage_path'] as String?,
        clipCount: r['clip_count'] as int?,
        error: r['error'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        groupIds: (r['group_ids'] as List?)?.cast<String>() ?? const [],
        hours: (r['hours'] as List?)?.cast<int>(),
      );
}

/// "Make a vlog": stitched on demand by GitHub (worker/export.py), started
/// through the start-export Edge Function, saved straight to the phone.
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  SupabaseClient get _client => Supabase.instance.client;

  static const _cols =
      'id, status, storage_path, clip_count, error, created_at, group_ids, hours';

  /// Fresh stitches per person per rolling 24 hours. Enforced by RLS in
  /// supabase/migrations/20261018_export_daily_cap.sql; keep in sync.
  static const dailyLimit = 5;

  /// Fresh stitches you've started in the last 24 hours (failed ones don't
  /// count, same as the RLS cap).
  Future<int> usedToday() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final rows = await _client
        .from('exports')
        .select('id')
        .neq('status', 'failed')
        .gte('created_at', since.toIso8601String());
    return rows.length;
  }

  /// Your last finished vlog of the same day, Logs and hours, if no clip
  /// has been added since it was made: saving it again needs no stitch.
  Future<EfocExport?> findReusable({
    required DateTime day,
    required List<String> groupIds,
    required List<int>? hours,
    required int clipCount,
  }) async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final rows = await _client
        .from('exports')
        .select(_cols)
        .eq('status', 'done')
        .eq('day', _dateString(day))
        .gte('created_at', since.toIso8601String())
        .order('created_at', ascending: false);

    final wantGroups = groupIds.toSet();
    final wantHours = hours?.toSet();
    for (final e in rows.map(EfocExport.fromRow)) {
      if (e.storagePath == null || e.clipCount != clipCount) continue;
      final sameGroups = e.groupIds.toSet().length == wantGroups.length &&
          e.groupIds.toSet().containsAll(wantGroups);
      final h = e.hours?.toSet();
      final sameHours = (h == null && wantHours == null) ||
          (h != null &&
              wantHours != null &&
              h.length == wantHours.length &&
              h.containsAll(wantHours));
      if (!sameGroups || !sameHours) continue;

      var newer = _client
          .from('clips')
          .select('id')
          .eq('recorded_on', _dateString(day))
          .inFilter('group_id', groupIds)
          .gt('created_at', e.createdAt.toUtc().toIso8601String());
      if (hours != null) newer = newer.inFilter('hour_of_day', hours);
      final fresh = await newer.limit(1);
      return fresh.isEmpty ? e : null;
    }
    return null;
  }

  /// Clips per hour today across [groupIds], one per person per hour (the
  /// same recording sent to several Logs counts once, like the stitch).
  Future<Map<int, int>> todaysClipsByHour(List<String> groupIds) async {
    if (groupIds.isEmpty) return {};
    final rows = await _client
        .from('clips')
        .select('user_id, hour_of_day')
        .eq('recorded_on', _dateString(DateTime.now()))
        .inFilter('group_id', groupIds);
    final seen = <String>{};
    final byHour = <int, int>{};
    for (final r in rows) {
      final hour = r['hour_of_day'] as int;
      if (seen.add('${r['user_id']}-$hour')) {
        byHour[hour] = (byHour[hour] ?? 0) + 1;
      }
    }
    return byHour;
  }

  /// Queues the vlog and starts it. Returns the export id.
  Future<String> start({
    required DateTime day,
    required List<String> groupIds,
    List<int>? hours,
  }) async {
    final row = await _client
        .from('exports')
        .insert({
          'day': _dateString(day),
          'group_ids': groupIds,
          'hours': hours,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    await _client.functions.invoke('start-export', body: {'export_id': id});
    return id;
  }

  Future<EfocExport?> fetch(String id) async {
    final row =
        await _client.from('exports').select(_cols).eq('id', id).maybeSingle();
    return row == null ? null : EfocExport.fromRow(row);
  }

  /// Your most recent finished vlog from the last day, if any.
  Future<EfocExport?> latestDone() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final row = await _client
        .from('exports')
        .select(_cols)
        .eq('status', 'done')
        .gte('created_at', since.toIso8601String())
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : EfocExport.fromRow(row);
  }

  /// Polls until the vlog is done or failed (GitHub usually takes 1–2 min).
  Stream<EfocExport> watch(String id) async* {
    final until = DateTime.now().add(const Duration(minutes: 10));
    while (DateTime.now().isBefore(until)) {
      final e = await fetch(id);
      if (e != null) {
        yield e;
        if (e.isFinished) return;
      }
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  /// Downloads and saves the vlog. [onProgress] gets 0–1 while downloading
  /// (only when the server sends a size).
  Future<void> save(
    EfocExport e, {
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    final url = await _client.storage
        .from('exports')
        .createSignedUrl(e.storagePath!, 600);
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) {
        throw Exception('Download failed (${res.statusCode})');
      }
      final total = res.contentLength ?? 0;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.stream) {
        bytes.add(chunk);
        if (total > 0) onProgress?.call(bytes.length / total);
      }
      await saveVideo(bytes.takeBytes(), fileName);
    } finally {
      client.close();
    }
  }

  static String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
