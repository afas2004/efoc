import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'table_view.dart';

Widget buildTableView({
  required Uri url,
  required String origin,
  required String base,
  required TableController controller,
  required void Function(Object? msg) onMessage,
  required VoidCallback onLoaded,
}) {
  bool fromGames(WebUri? u) =>
      u != null && u.origin == origin && u.toString().startsWith('$base/');

  return InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(url.toString())),
    initialSettings: InAppWebViewSettings(
      transparentBackground: true,
      supportZoom: false,
      builtInZoomControls: false,
      displayZoomControls: false,
      disableContextMenu: true,
      mediaPlaybackRequiresUserGesture: false,
      useShouldOverrideUrlLoading: true,
      allowFileAccess: false,
      allowContentAccess: false,
    ),
    onWebViewCreated: (c) {
      c.addJavaScriptHandler(
        handlerName: 'efoc',
        callback: (args) async {
          // Only the games page itself may talk to the app.
          if (!fromGames(await c.getUrl()) || args.isEmpty) return null;
          onMessage(args.first);
          return null;
        },
      );
      controller.sender = (msg) {
        c.evaluateJavascript(
          source: 'window.efoc && window.efoc.receive(${jsonEncode(msg)});',
        );
      };
    },
    onLoadStop: (c, u) {
      if (fromGames(u)) onLoaded();
    },
    // Navigation anywhere else is blocked.
    shouldOverrideUrlLoading: (c, action) async =>
        fromGames(action.request.url)
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL,
  );
}
