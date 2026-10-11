/// Identity and version information shown in the app's "About" section.
///
/// Kept in one place so the UI, the release notes and the build version can
/// never drift apart. `version` must match `version:` in `pubspec.yaml`
/// (enforced by `test/app_info_test.dart`).
class AppInfo {
  const AppInfo._();

  /// Product name.
  static const String name = 'JingerPicManager';

  /// Marketing version, e.g. `0.0.1`. Mirrors `version` in pubspec.yaml.
  static const String version = '0.0.1';

  /// Short product description used in the About dialog.
  static const String description = '本地优先的电脑相册管理';

  /// Author display name.
  static const String authorName = '靖待jinger';

  /// Author homepage / repository.
  static const String authorUrl = 'https://github.com/hubojing';

  /// `version` prefixed with a `v`, the form used for release tags.
  static String get tagVersion => 'v$version';

  /// Human readable "name version" label.
  static String get displayName => '$name $version';
}

/// Builds the process used to open [url] with the operating system's default
/// browser on Windows.
///
/// Separated from the actual launch so it can be unit tested without spawning
/// a real browser.
List<String> externalOpenCommand(String url) {
  final trimmed = url.trim();
  return ['explorer', trimmed];
}
