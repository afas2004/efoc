import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveVideo(Uint8List bytes, String fileName) async {
  await Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: 'video/mp4', name: fileName)],
    fileNameOverrides: [fileName],
  );
}
