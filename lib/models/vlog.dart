/// A stitched daily vlog for one group, written by worker/stitch.py.
class EfocVlog {
  final String id;
  final String groupId;

  /// Calendar day the clips were recorded on (date only, local).
  final DateTime date;

  final String storagePath;
  final String? thumbnailPath;
  final int clipCount;
  final double? durationSeconds;

  const EfocVlog({
    required this.id,
    required this.groupId,
    required this.date,
    required this.storagePath,
    required this.thumbnailPath,
    required this.clipCount,
    required this.durationSeconds,
  });

  factory EfocVlog.fromRow(Map<String, dynamic> row) {
    final d = DateTime.parse(row['vlog_date'] as String);
    return EfocVlog(
      id: row['id'] as String,
      groupId: row['group_id'] as String,
      date: DateTime(d.year, d.month, d.day),
      storagePath: row['storage_path'] as String,
      thumbnailPath: row['thumbnail_path'] as String?,
      clipCount: (row['clip_count'] as int?) ?? 0,
      durationSeconds: (row['duration_seconds'] as num?)?.toDouble(),
    );
  }
}
