import 'package:flutter/widgets.dart';

import 'table_view_native.dart'
    if (dart.library.js_interop) 'table_view_web.dart' as impl;

/// Lets the table screen send bridge messages to the game page.
class TableController {
  void Function(Map<String, Object?> msg)? _send;

  /// Set by the platform view once the page can receive.
  set sender(void Function(Map<String, Object?> msg)? f) => _send = f;

  void send(Map<String, Object?> msg) => _send?.call(msg);
}

/// The game page: an Android WebView (flutter_inappwebview, JS handler
/// `efoc`) or, on the web build, an `<iframe>` talking over postMessage.
/// Either way only pages under [base] (on [origin]) may load and talk to
/// the app; other sites on the same origin are refused.
Widget buildTableView({
  required Uri url,
  required String origin,
  required String base,
  required TableController controller,
  required void Function(Object? msg) onMessage,
  required VoidCallback onLoaded,
}) =>
    impl.buildTableView(
      url: url,
      origin: origin,
      base: base,
      controller: controller,
      onMessage: onMessage,
      onLoaded: onLoaded,
    );
