import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The files that decide which build runs. Re-fetching them with
/// `cache: 'reload'` overwrites whatever the browser cached, so the reload
/// below can't come back up on the old build (which would show the update
/// banner again, forever).
const _appFiles = ['flutter_bootstrap.js', 'main.dart.js'];

/// Refreshes the cached app code, then hard-reloads the page with a
/// cache-busting query param.
Future<void> reloadApp() async {
  final origin = web.window.location.origin;
  try {
    await Future.wait([
      for (final f in _appFiles)
        web.window
            .fetch('$origin/$f'.toJS, web.RequestInit(cache: 'reload'))
            .toDart,
    ]).timeout(const Duration(seconds: 20));
  } catch (_) {
    // Offline or slow: reload anyway, worst case it's the old build.
  }
  final bust = DateTime.now().millisecondsSinceEpoch;
  web.window.location.href = '$origin/?t=$bust';
}
