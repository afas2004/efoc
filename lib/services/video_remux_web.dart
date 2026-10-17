import 'dart:async';
import 'dart:js_interop';

@JS('efocFixWebm')
external void _efocFixWebm(String blobUrl, int durationMs, JSFunction onDone);

Future<String> fixForLooping(String blobUrl, int durationMs) {
  final completer = Completer<String>();
  _efocFixWebm(
    blobUrl,
    durationMs,
    ((String? result) {
      if (result == null) {
        completer.completeError('fix-webm-duration failed');
      } else {
        completer.complete(result);
      }
    }).toJS,
  );
  return completer.future;
}