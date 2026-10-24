import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// Must match web/share-target-sw.js.
const _cacheName = 'efoc-share-v1';
const _cacheKey = '/__efoc_share__';

Future<PickedBytes?> takeInboundShare() async {
  try {
    final cache = await web.window.caches.open(_cacheName).toDart;
    final response = await cache.match(_cacheKey.toJS).toDart;
    if (response == null) return null;

    final body = (await response.text().toDart).toDart;
    // Take it once: a refresh shouldn't import the same sticker twice.
    await cache.delete(_cacheKey.toJS).toDart;

    final map = jsonDecode(body) as Map<String, dynamic>;
    final b64 = map['b64'] as String?;
    if (b64 == null || b64.isEmpty) return null;

    return PickedBytes(
      (map['name'] as String?) ?? 'shared',
      base64Decode(b64),
    );
  } catch (_) {
    return null;
  }
}
