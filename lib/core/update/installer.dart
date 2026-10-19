import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_check.dart';

/// Picks the Linux package of a release: `.deb` when [preferDeb] (pkexec is
/// available), `.tar.gz` otherwise; falls back to the other format. Null when
/// the release has no compatible asset.
ReleaseAsset? pickAsset(List<ReleaseAsset> assets, {bool preferDeb = true}) {
  ReleaseAsset? find(String ext) {
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith(ext)) return a;
    }
    return null;
  }

  final deb = find('.deb'), tar = find('.tar.gz');
  return preferDeb ? (deb ?? tar) : (tar ?? deb);
}

/// One step of a download. [file] is set only on the last event.
@immutable
class DownloadProgress {
  const DownloadProgress({required this.received, this.total, this.file});

  final int received;

  /// Null when the server didn't send a length.
  final int? total;
  final File? file;

  /// 0..1, or null when the total is unknown.
  double? get fraction =>
      total == null || total! <= 0 ? null : (received / total!).clamp(0.0, 1.0);
}

class UpdateInstaller {
  const UpdateInstaller({this.tempRoot});

  /// Where the fresh download directory is created (default: system temp).
  final Directory? tempRoot;

  /// Whether `pkexec` is on the PATH (needed to install a `.deb`).
  Future<bool> hasPkexec() async {
    try {
      return (await Process.run('which', ['pkexec'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Downloads [asset] into a new, empty temporary directory, emitting
  /// progress; the last event carries the file.
  Stream<DownloadProgress> download(ReleaseAsset asset) async* {
    final root = tempRoot ?? Directory.systemTemp;
    final dir = await root.createTemp('promptorium-update-');
    final file = File('${dir.path}/${asset.name.split('/').last}');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(asset.url));
      req.headers.set('User-Agent', 'promptorium');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException(
          'HTTP ${res.statusCode}',
          uri: Uri.parse(asset.url),
        );
      }
      final total = res.contentLength >= 0 ? res.contentLength : null;
      final sink = file.openWrite();
      var received = 0;
      try {
        yield DownloadProgress(received: 0, total: total);
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          yield DownloadProgress(received: received, total: total);
        }
      } finally {
        await sink.close();
      }
      yield DownloadProgress(received: received, total: total, file: file);
    } finally {
      client.close(force: true);
    }
  }
}

final updateInstallerProvider = Provider<UpdateInstaller>(
  (ref) => const UpdateInstaller(),
);
