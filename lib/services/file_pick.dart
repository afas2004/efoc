import 'file_pick_native.dart'
    if (dart.library.js_interop) 'file_pick_web.dart' as impl;
import 'picked_file.dart';

export 'picked_file.dart';

/// Opens a file chooser and returns the chosen files as bytes.
///
/// Web builds use their own `<input type="file">`; native builds go through
/// `file_picker`. See `file_pick_web.dart` for why the web path does not.
Future<List<PickedBytes>> pickFiles({
  bool multiple = false,
  String? accept,
}) =>
    impl.pickFiles(multiple: multiple, accept: accept);
