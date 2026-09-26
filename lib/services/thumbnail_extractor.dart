import 'dart:typed_data';

import 'thumbnail_extractor_native.dart'
    if (dart.library.js_interop) 'thumbnail_extractor_web.dart'
    as impl;

/// Extracts a single JPEG frame from a video file.
///
/// On native: [path] is a filesystem path.
/// On web: [path] is a blob: URL.
///
/// Returns the JPEG bytes, or null if extraction failed.
Future<Uint8List?> extractThumbnailJpeg(String path) {
  return impl.extractThumbnailJpeg(path);
}