import 'dart:convert';

import 'package:http/http.dart' as http;
import 'update_reload_native.dart'
    if (dart.library.js_interop) 'update_reload_web.dart'
    as impl;

import '../version.dart';

/// Outcome of an update check.
enum UpdateStatus {
  /// Current build matches or exceeds the server's latest.
  upToDate,

  /// A newer build is available on the server.
  updateAvailable,

  /// The check could not complete (network, parse, etc.).
  failed,
}

class UpdateResult {
  final UpdateStatus status;
  final int latestBuild;
  final String latestVersion;
  final String releaseNotes;
  final String? errorMessage;

  const UpdateResult._({
    required this.status,
    this.latestBuild = 0,
    this.latestVersion = '',
    this.releaseNotes = '',
    this.errorMessage,
  });

  factory UpdateResult.upToDate(int build, String version) => UpdateResult._(
        status: UpdateStatus.upToDate,
        latestBuild: build,
        latestVersion: version,
      );

  factory UpdateResult.updateAvailable({
    required int latestBuild,
    required String latestVersion,
    required String releaseNotes,
  }) =>
      UpdateResult._(
        status: UpdateStatus.updateAvailable,
        latestBuild: latestBuild,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
      );

  factory UpdateResult.failed(String message) => UpdateResult._(
        status: UpdateStatus.failed,
        errorMessage: message,
      );
}

class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  static const String _manifestUrl = 'https://efoc.party/update.json';

  /// Fetches update.json and compares against [kAppBuild].
  ///
  /// Never throws. All failures come back as [UpdateStatus.failed] so the
  /// caller can decide whether to surface them (manual check) or stay silent
  /// (auto check).
  Future<UpdateResult> check() async {
    try {
      // Cache-bust so we never read a stale manifest, even if a proxy ignored
      // the Cache-Control header. The server also sets no-cache, this is the
      // belt to that suspenders.
      final bust = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$_manifestUrl?t=$bust');

      final response = await http
          .get(url, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return UpdateResult.failed('HTTP ${response.statusCode}');
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map) {
        return UpdateResult.failed('Malformed manifest');
      }

      final latestBuild = decoded['latest_build'];
      final latestVersion = decoded['latest_version'];
      final releaseNotes = decoded['release_notes'] ?? '';

      if (latestBuild is! int || latestVersion is! String) {
        return UpdateResult.failed('Malformed manifest');
      }

      if (latestBuild <= kAppBuild) {
        return UpdateResult.upToDate(latestBuild, latestVersion);
      }

      return UpdateResult.updateAvailable(
        latestBuild: latestBuild,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes is String ? releaseNotes : '',
      );
    } catch (e) {
      return UpdateResult.failed(e.toString());
    }
  }

  /// Hard-reloads the page with a cache-busting query param.
  ///
  /// The timestamp forces the browser to re-fetch index.html, which references
  /// the new main.dart.js. The service worker picks up the new build on that
  /// navigation. Flutter's URL strategy strips the param on next route change,
  /// so the user never sees it linger.
  void reload() => impl.reloadApp();
}
