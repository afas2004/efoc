/// Single source of truth for the app's current build number at runtime.
///
/// Must stay in sync with:
///   - pubspec.yaml  (version: X.Y.Z+N)
///   - web/update.json  (latest_build: N)
///
/// Bump all three together on every release. There is no build-time
/// substitution here on purpose ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â a hardcoded const keeps the update
/// check dependency-free and trivially debuggable.
const int kAppBuild = 4;

/// Human-readable version, used only for display.
const String kAppVersion = '1.2.0';
