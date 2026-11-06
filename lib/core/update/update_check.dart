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

/// The query didn't get an answer it can use (SPEC-038 R10): the network, a
/// timeout and a bad response end up here, never as "no release".
class ReleaseFetchException implements Exception {
  const ReleaseFetchException(this.message);

  final String message;

  @override
  String toString() => 'ReleaseFetchException: $message';
}

/// Reads the latest release: null when the project has none; throws when the
/// query fails.
typedef ReleaseFetcher = Future<Map<String, dynamic>?> Function(
  String appVersion,
);

Future<Map<String, dynamic>?> fetchLatestRelease(
  String appVersion, {
  String url = releasesApi,
}) async {
  const timeout = Duration(seconds: 10);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'promptorium/$appVersion');
    final res = await req.close().timeout(timeout);
    if (res.statusCode == HttpStatus.notFound) return null;
    if (res.statusCode != HttpStatus.ok) {
      throw ReleaseFetchException('HTTP ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    final j = jsonDecode(body);
    if (j is Map<String, dynamic>) return j;
    throw const ReleaseFetchException('resposta inválida');
  } finally {
    client.close(force: true);
  }
}

final releaseFetcherProvider = Provider<ReleaseFetcher>(
  (ref) => fetchLatestRelease,
);

/// How the last query ended.
enum UpdateCheckOutcome { upToDate, found, failed }

/// Result of the last query, kept in the settings so a restart within the 24 h
/// without a query doesn't turn it into "versão mais recente" (SPEC-038 R10).
@immutable
class UpdateCheckResult {
  const UpdateCheckResult(this.outcome, this.at);

  final UpdateCheckOutcome outcome;
  final DateTime at;

  String encode() => '${outcome.name} ${at.toIso8601String()}';

  /// Null when [raw] is absent or unreadable.
  static UpdateCheckResult? parse(String? raw) {
    final parts = raw?.split(' ') ?? const [];
    if (parts.length != 2) return null;
    final outcome = UpdateCheckOutcome.values.asNameMap()[parts.first];
    final at = DateTime.tryParse(parts.last);
    return outcome == null || at == null
        ? null
        : UpdateCheckResult(outcome, at);
  }
}

/// "Aviso de versão nova" (F18): once a day (Configurações can turn it off)
/// the latest GitHub release is compared with [appVersionProvider].
class UpdateChecker extends Notifier<AvailableUpdate?> {
  static const enabledKey = 'update.check';
  static const lastKey = 'update.lastCheck';
  static const resultKey = 'update.lastResult';

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
    final Map<String, dynamic>? r;
    try {
      r = await ref.read(releaseFetcherProvider)(current);
    } catch (e) {
      debugPrint('atualização: $e');
      return _failed(at);
    }
    if (r == null || r['draft'] == true) return _upToDate(at);
    final tag = '${r['tag_name'] ?? ''}';
    if (parseVersion(tag) == null) return _failed(at);
    if (!isNewer(tag, current)) return _upToDate(at);
    await _record(UpdateCheckOutcome.found, at);
    return state = AvailableUpdate(
      version: tag.replaceFirst(RegExp('^v'), ''),
      url:
          '${r['html_url'] ?? 'https://github.com/mayroncachina/promptorium/releases'}',
      notes: r['body'] is String ? r['body'] as String : '',
      publishedAt: DateTime.tryParse('${r['published_at'] ?? ''}'),
      assets: parseReleaseAssets(r['assets']),
    );
  }

  Future<AvailableUpdate?> _upToDate(DateTime at) async {
    await _record(UpdateCheckOutcome.upToDate, at);
    return state = null;
  }

  /// [state] stays: an update already found is still there (R10).
  Future<AvailableUpdate?> _failed(DateTime at) async {
    await _record(UpdateCheckOutcome.failed, at);
    return state;
  }

  Future<void> _record(UpdateCheckOutcome outcome, DateTime at) => ref
      .read(appSettingsProvider.notifier)
      .set(resultKey, UpdateCheckResult(outcome, at).encode());
}

final updateCheckerProvider = NotifierProvider<UpdateChecker, AvailableUpdate?>(
  UpdateChecker.new,
);

/// How the last query ended; null when none is on record.
final lastCheckProvider = Provider<UpdateCheckResult?>(
  (ref) => UpdateCheckResult.parse(
    ref.watch(
      appSettingsProvider.select((s) => s[UpdateChecker.resultKey]),
    ),
  ),
);
