import 'video_remux_native.dart'
    if (dart.library.js_interop) 'video_remux_web.dart' as impl;

class VideoRemuxService {
  static Future<String> fixForLooping(String inputPath) {
    return impl.fixForLooping(inputPath);
  }
}