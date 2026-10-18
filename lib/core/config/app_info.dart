import 'dart:io';

/// App metadata shown in the splash / about.
abstract final class AppInfo {
  /// Keep in sync with `version:` in pubspec.yaml.
  static const version = '0.2.0';

  static String get platformName {
    final os = Platform.operatingSystem;
    return os.isEmpty ? os : '${os[0].toUpperCase()}${os.substring(1)}';
  }
}
