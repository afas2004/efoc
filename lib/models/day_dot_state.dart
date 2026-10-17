import 'vlog.dart';

enum DayDotKind { today, stitchedUnviewed, stitchedViewed, missed }

class DayDotData {
  final String label;
  final DateTime date;
  final DayDotKind kind;

  /// The stitched vlog for this day, when there is one.
  final EfocVlog? vlog;

  /// Someone else uploaded a clip that day you haven't opened yet.
  final bool hasUnseenClips;

  const DayDotData({
    required this.label,
    required this.date,
    required this.kind,
    this.vlog,
    this.hasUnseenClips = false,
  });
}
