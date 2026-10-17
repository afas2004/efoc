import 'package:shared_preferences/shared_preferences.dart';

import 'table_link.dart';

/// The table this phone is sitting at, kept while the table screen is open.
/// If the app or browser tab dies mid-game (phones often reload a tab in
/// the background), the next launch finds it here and goes straight back.
/// Leaving the table, or the match ending, clears it.
class ActiveTable {
  ActiveTable._();

  static const _key = 'games.activeTable';
  static const _maxAge = Duration(hours: 1);

  static Future<void> save(TableLink link) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, '${DateTime.now().millisecondsSinceEpoch} ${link.toUri()}');
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// The saved table, if it's recent enough to still be going.
  static Future<TableLink?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final space = raw.indexOf(' ');
      final at = int.tryParse(raw.substring(0, space < 0 ? 0 : space));
      final uri = Uri.tryParse(raw.substring(space + 1));
      if (at == null || uri == null) return null;
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(at));
      if (age > _maxAge) {
        await prefs.remove(_key);
        return null;
      }
      return TableLink.fromUri(uri);
    } catch (_) {
      return null;
    }
  }
}
