import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

Future<Uint8List?> extractThumbnailJpeg(String path) {
  return VideoThumbnail.thumbnailData(
    video: path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 400,
    quality: 70,
    timeMs: 200,
  );
}