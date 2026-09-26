import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<Uint8List?> extractThumbnailJpeg(String blobUrl) async {
  final video = web.HTMLVideoElement()
    ..src = blobUrl
    ..muted = true
    ..crossOrigin = 'anonymous';

  video.style.display = 'none';
  web.document.body?.append(video);

  try {
    // Wait for metadata
    final metadataCompleter = Completer<void>();
    video.onLoadedMetadata.listen((_) {
      if (!metadataCompleter.isCompleted) metadataCompleter.complete();
    });
    video.onError.listen((_) {
      if (!metadataCompleter.isCompleted) {
        metadataCompleter.completeError('video failed to load');
      }
    });

    await metadataCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('metadata load'),
    );

    // Seek
    final seekCompleter = Completer<void>();
    video.onSeeked.listen((_) {
      if (!seekCompleter.isCompleted) seekCompleter.complete();
    });

    video.currentTime = 0.2;
    await seekCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('seek'),
    );

    // Draw frame to canvas
    final canvas = web.HTMLCanvasElement()
      ..width = video.videoWidth
      ..height = video.videoHeight;

    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return null;
    ctx.drawImage(video, 0, 0);

    final dataUrl = canvas.toDataURL('image/jpeg', 0.7.toJS);
    final base64String = dataUrl.split(',').last;
    return Uint8List.fromList(base64Decode(base64String));
  } finally {
    video.remove();
  }
}