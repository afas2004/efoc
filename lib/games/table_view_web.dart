import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'table_view.dart';

int _views = 0;

@JS('JSON.parse')
external JSAny? _jsonParse(JSString s);

@JS('JSON.stringify')
external JSString? _jsonStringify(JSAny? v);

Widget buildTableView({
  required Uri url,
  required String origin,
  required String base,
  required TableController controller,
  required void Function(Object? msg) onMessage,
  required VoidCallback onLoaded,
}) {
  final viewType = 'efoc-table-${_views++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final frame = web.HTMLIFrameElement()
      ..src = url.toString()
      ..allow = 'autoplay; vibrate'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = 'transparent';

    web.EventListener? listener;
    listener = ((web.MessageEvent e) {
      if (!frame.isConnected) {
        web.window.removeEventListener('message', listener);
        controller.sender = null;
        return;
      }
      // Only the games origin, and only this iframe's window.
      if (e.origin != origin) return;
      final src = e.source;
      final win = frame.contentWindow;
      if (src == null || win == null || !src.strictEquals(win).toDart) return;
      final s = _jsonStringify(e.data);
      if (s == null) return;
      onMessage(jsonDecode(s.toDart));
    }).toJS;
    web.window.addEventListener('message', listener);

    frame.addEventListener(
      'load',
      ((web.Event _) => onLoaded()).toJS,
    );
    controller.touchableSetter =
        (on) => frame.style.pointerEvents = on ? 'auto' : 'none';
    controller.sender = (msg) {
      frame.contentWindow?.postMessage(_jsonParse(jsonEncode(msg).toJS), origin.toJS);
    };
    return frame;
  });
  return HtmlElementView(viewType: viewType);
}
