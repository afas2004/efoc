import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> saveFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Give the browser a moment to start the download before freeing it.
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
