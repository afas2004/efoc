import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// Opens the browser's file chooser from a plain `<input type="file">`.
///
/// This is hand-rolled instead of going through `file_picker` because the
/// plugin's web path does nothing when it is reached from a tap that already
/// closed a bottom sheet — the input click lands outside the user gesture and
/// Chrome swallows it. Building the element ourselves keeps the click in the
/// same task as the tap.
Future<List<PickedBytes>> pickFiles({
  bool multiple = false,
  String? accept,
}) async {
  final completer = Completer<List<PickedBytes>>();

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = multiple
    ..style.display = 'none';
  if (accept != null) input.accept = accept;

  void finish(List<PickedBytes> files) {
    input.remove();
    if (!completer.isCompleted) completer.complete(files);
  }

  // The listener itself has to be synchronous: dart2js rejects a `toJS`
  // function whose signature returns a Future.
  input.addEventListener(
    'change',
    (web.Event _) {
      final list = input.files;
      final chosen = <web.File>[];
      if (list != null) {
        for (var i = 0; i < list.length; i++) {
          final file = list.item(i);
          if (file != null) chosen.add(file);
        }
      }
      unawaited(_read(chosen).then(finish));
    }.toJS,
  );

  // Chrome 113+ fires this when the dialog is dismissed with no selection.
  input.addEventListener(
    'cancel',
    ((web.Event _) => finish(const [])).toJS,
  );

  web.document.body?.append(input);
  input.click();

  // Never leave the caller awaiting forever if neither event arrives (some
  // in-app browsers drop both).
  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () {
      input.remove();
      return const <PickedBytes>[];
    },
  );
}

Future<List<PickedBytes>> _read(List<web.File> files) async {
  final picked = <PickedBytes>[];
  for (final file in files) {
    final buffer = await file.arrayBuffer().toDart;
    picked.add(PickedBytes(file.name, buffer.toDart.asUint8List()));
  }
  return picked;
}
