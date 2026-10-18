import 'package:flutter/widgets.dart';

import 'table_view_native.dart'
    if (dart.library.js_interop) 'table_view_web.dart' as impl;

/// Lets the table screen send bridge messages to the game page.
class TableController {
  void Function(Map<String, Object?> msg)? _send;

  /// Set by the platform view once the page can receive.
  set sender(void Function(Map<String, Object?> msg)? f) => _send = f;

  void send(Map<String, Object?> msg) => _send?.call(msg);

  void Function(bool)? _setTouchable;

  /// Set by the web view: whether the iframe takes taps. Over an iframe the
  /// browser sends taps to it, not to a sheet or dialog Flutter draws on
  /// top, so the table screen switches it off while one is open.
  set touchableSetter(void Function(bool)? f) => _setTouchable = f;

  void setTouchable(bool on) => _setTouchable?.call(on);

  /// Shows [open]'s sheet or dialog with the page not taking taps.
  Future<T> whileCovered<T>(Future<T> Function() open) async {
    setTouchable(false);
    try {
      return await open();
    } finally {
      setTouchable(true);
    }
  }
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
