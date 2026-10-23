import 'dart:io';

/// App metadata shown in the splash / about.
abstract final class AppInfo {
  static String get platformName {
    final os = Platform.operatingSystem;
    return os.isEmpty ? os : '${os[0].toUpperCase()}${os.substring(1)}';
  }
}
