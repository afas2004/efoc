import 'picked_file.dart';

import 'inbound_share_stub.dart'
    if (dart.library.js_interop) 'inbound_share_web.dart' as impl;

export 'picked_file.dart';

/// Takes the file Android handed us through the share sheet, if any.
///
/// The share-target service worker (web/share-target-sw.js) stashes the file
/// in the Cache API and bounces the browser to `/?shared=1`; this pulls it
/// back out once and deletes it. Native builds have no equivalent and return
/// null.
Future<PickedBytes?> takeInboundShare() => impl.takeInboundShare();
