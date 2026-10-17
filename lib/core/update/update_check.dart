import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Version of this build (keep in sync with `pubspec.yaml`).
const appVersion = '0.2.0';

/// Releases of the project on GitHub.
const releasesApi =
    'https://api.github.com/repos/mayroncachina/promptorium/releases/latest';

/// `v0.2.1` / `0.2.1-beta` → [0, 2, 1] (null = not a version).
List<int>? parseVersion(String tag) {
  final m = RegExp(r'^v?(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(tag.trim());
  if (m == null) return null;
  return [
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3) ?? '0'),
  ];
}

/// Whether [latest] is newer than [current].
bool isNewer(String latest, String current) {
  final a = parseVersion(latest), b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// A release newer than [appVersion].
@immutable
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.url});

  final String version;
  final String url;
}

/// Reads the latest release (null = none / offline / not a JSON).
typedef ReleaseFetcher = Future<Map<String, dynamic>?> Function();

Future<Map<String, dynamic>?> fetchLatestRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(releasesApi));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'promptorium/$appVersion');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body);
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

final releaseFetcherProvider = Provider<ReleaseFetcher>(
  (ref) => fetchLatestRelease,
);

/// "Aviso de versão nova" (F18): once a day (Configurações can turn it off)
/// the latest GitHub release is compared with [appVersion].
class UpdateChecker extends Notifier<AvailableUpdate?> {
  static const enabledKey = 'update.check';
  static const lastKey = 'update.lastCheck';

  @override
  AvailableUpdate? build() => null;

  bool get enabled =>
      ref.read(appSettingsProvider.notifier).get(enabledKey) != '0';

  /// Checks when due (or [force]); returns the update found.
  Future<AvailableUpdate?> check({bool force = false, DateTime? now}) async {
    final settings = ref.read(appSettingsProvider.notifier);
    if (!force && !enabled) return null;
    final at = now ?? DateTime.now();
    final last = DateTime.tryParse(settings.get(lastKey) ?? '');
    if (!force && last != null && at.difference(last).inHours < 24) {
      return state;
    }
    await settings.set(lastKey, at.toIso8601String());
    final r = await ref.read(releaseFetcherProvider)();
    final tag = '${r?['tag_name'] ?? ''}';
    if (r == null || r['draft'] == true || !isNewer(tag, appVersion)) {
      return state = null;
    }
    return state = AvailableUpdate(
      version: tag.replaceFirst(RegExp('^v'), ''),
      url:
          '${r['html_url'] ?? 'https://github.com/mayroncachina/promptorium/releases'}',
    );
  }
}

final updateCheckerProvider = NotifierProvider<UpdateChecker, AvailableUpdate?>(
  UpdateChecker.new,
);
