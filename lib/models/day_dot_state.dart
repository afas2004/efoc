import 'vlog.dart';

enum DayDotKind { today, stitchedUnviewed, stitchedViewed, missed }

class DayDotData {
  final String label;
  final DateTime date;
  final DayDotKind kind;

  /// The stitched vlog for this day, when there is one.
  final EfocVlog? vlog;

  const DayDotData({
    required this.label,
    required this.date,
    required this.kind,
    this.vlog,
  });
}
