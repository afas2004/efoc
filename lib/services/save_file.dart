import 'dart:typed_data';

import 'save_file_native.dart'
    if (dart.library.js_interop) 'save_file_web.dart' as impl;

/// Saves a video to the phone. Web: a normal browser download (goes to
/// Downloads, no share sheet). Android app: the system share sheet, which
/// has "Save to Files/Photos".
Future<void> saveVideo(Uint8List bytes, String fileName) =>
    impl.saveVideo(bytes, fileName);
