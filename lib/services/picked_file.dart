import 'dart:typed_data';

/// A file the user picked, already read into memory.
///
/// Small by design: the only things we pick are sticker packs and sticker
/// images, all of which are well under a megabyte.
///
/// Named `PickedBytes` rather than `PickedFile` because `image_picker` exports
/// its own `PickedFile` and the two would collide at every import site.
class PickedBytes {
  final String name;
  final Uint8List bytes;

  const PickedBytes(this.name, this.bytes);
}
