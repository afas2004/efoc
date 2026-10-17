import 'package:web/web.dart' as web;

/// Hard-reloads the page with a cache-busting query param.
void reloadApp() {
  final origin = web.window.location.origin;
  final bust = DateTime.now().millisecondsSinceEpoch;
  web.window.location.href = '$origin/?t=$bust';
}
