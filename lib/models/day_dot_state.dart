enum DayDotKind { today, stitchedUnviewed, stitchedViewed, missed }

class DayDotData {
  final String label;
  final DayDotKind kind;

  const DayDotData({required this.label, required this.kind});
}