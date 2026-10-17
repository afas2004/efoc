import 'video_remux_native.dart'
    if (dart.library.js_interop) 'video_remux_web.dart' as impl;

class VideoRemuxService {
  /// [durationMs] is written into the WebM header on web (browsers record
  /// WebM without a duration, which breaks seeking and looping).
  static Future<String> fixForLooping(String inputPath, int durationMs) {
    return impl.fixForLooping(inputPath, durationMs);
  }
}
