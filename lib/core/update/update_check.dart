import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/providers.dart';

/// Version of the installed app (`PackageInfo.version`); `0.0.0` when it
/// can't be read.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final v = (await PackageInfo.fromPlatform()).version;
    return v.isEmpty ? '0.0.0' : v;
  } catch (_) {
    return '0.0.0';
  }
});

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

/// A release newer than the running app version.
@immutable
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.url,
    this.notes = '',
    this.publishedAt,
    this.assets = const [],
  });

  final String version;
  final String url;

  /// Release body (Markdown); empty when absent.
  final String notes;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;
}

/// A downloadable file of a release (`browser_download_url`).
@immutable
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size});

  final String name;
  final String url;

  /// Size in bytes announced by the release; null when absent.
  final int? size;
}

/// Tolerant of missing/mistyped fields: bad entries are skipped.
List<ReleaseAsset> parseReleaseAssets(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final a in raw)
      if (a is Map &&
          a['name'] is String &&
          a['browser_download_url'] is String)
        ReleaseAsset(
          name: a['name'] as String,
          url: a['browser_download_url'] as String,
          size: a['size'] is int ? a['size'] as int : null,
        ),
  ];
}

/// Reads the latest release (null = none / offline / not a JSON).
typedef ReleaseFetcher = Future<Map<String, dynamic>?> Function(
  String appVersion,
);

Future<Map<String, dynamic>?> fetchLatestRelease(String appVersion) async {
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
/// the latest GitHub release is compared with [appVersionProvider].
class UpdateChecker extends Notifier<AvailableUpdate?> {
  static const enabledKey = 'update.check';
  static const lastKey = 'update.lastCheck';

  @override
  AvailableUpdate? build() => null;

  bool get enabled =>
      ref.read(appSettingsProvider.notifier).get(enabledKey) != '0';

  /// Checks when due (or [force]); returns the update found. [version]
  /// defaults to [appVersionProvider].
  Future<AvailableUpdate?> check({
    bool force = false,
    DateTime? now,
    String? version,
  }) async {
    final settings = ref.read(appSettingsProvider.notifier);
    if (!force && !enabled) return null;
    final at = now ?? DateTime.now();
    final last = DateTime.tryParse(settings.get(lastKey) ?? '');
    if (!force && last != null && at.difference(last).inHours < 24) {
      return state;
    }
    await settings.set(lastKey, at.toIso8601String());
    final String current = version ?? await ref.read(appVersionProvider.future);
    final r = await ref.read(releaseFetcherProvider)(current);
    final tag = '${r?['tag_name'] ?? ''}';
    if (r == null || r['draft'] == true || !isNewer(tag, current)) {
      return state = null;
    }
    return state = AvailableUpdate(
      version: tag.replaceFirst(RegExp('^v'), ''),
      url:
          '${r['html_url'] ?? 'https://github.com/mayroncachina/promptorium/releases'}',
      notes: r['body'] is String ? r['body'] as String : '',
      publishedAt: DateTime.tryParse('${r['published_at'] ?? ''}'),
      assets: parseReleaseAssets(r['assets']),
    );
  }
}

final updateCheckerProvider = NotifierProvider<UpdateChecker, AvailableUpdate?>(
  UpdateChecker.new,
);
