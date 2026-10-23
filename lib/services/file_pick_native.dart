import 'package:file_picker/file_picker.dart';

import 'picked_file.dart';

/// Android/iOS: the platform document picker, read into memory.
Future<List<PickedBytes>> pickFiles({
  bool multiple = false,
  String? accept,
}) async {
  final result = await FilePicker.pickFiles(
    allowMultiple: multiple,
    withData: true,
  );
  if (result == null) return const [];

  final picked = <PickedBytes>[];
  for (final file in result.files) {
    final bytes = file.bytes;
    if (bytes == null) continue;
    picked.add(PickedBytes(file.name, bytes));
  }
  return picked;
}
