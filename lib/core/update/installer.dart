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

  /// Installs the downloaded [file], closes the database through
  /// [closeDatabase] and restarts the app, in that order. Throws (before
  /// closing anything) when the installation fails.
  Future<void> installAndRestart(
    File file, {
    required Future<void> Function() closeDatabase,
  }) async {
    await install(file);
    await closeDatabase();
    await restart();
  }

  /// `.deb`: `pkexec apt install`; `.tar.gz`: extracted over the executable's
  /// directory when it is writable.
  Future<void> install(File file) async {
    final name = file.path.toLowerCase();
    if (name.endsWith('.deb')) {
      if (!await hasPkexec()) {
        throw const FileSystemException(
          'pkexec não encontrado; não dá para instalar o .deb.',
        );
      }
      final r = await Process.run('pkexec', [
        'apt',
        'install',
        '-y',
        file.path,
      ]);
      if (r.exitCode != 0) {
        throw ProcessException(
          'pkexec',
          ['apt', 'install'],
          '${r.stderr}'.trim(),
          r.exitCode,
        );
      }
    } else if (name.endsWith('.tar.gz')) {
      final dir = File(Platform.resolvedExecutable).parent;
      if (!await _writable(dir)) {
        throw FileSystemException('Sem permissão de escrita em ${dir.path}.');
      }
      // The archive has a single top-level directory (see scripts/package.sh).
      final r = await Process.run('tar', [
        '-xzf',
        file.path,
        '-C',
        dir.path,
        '--strip-components=1',
      ]);
      if (r.exitCode != 0) {
        throw ProcessException(
          'tar',
          ['-xzf'],
          '${r.stderr}'.trim(),
          r.exitCode,
        );
      }
    } else {
      throw const FileSystemException('Formato de pacote não suportado.');
    }
  }

  /// Opens the release page in the browser (fallback when the update fails).
  /// Errors only log.
  Future<void> openReleasePage(String url) async {
    try {
      await Process.run('xdg-open', [url]);
    } catch (e) {
      debugPrint('xdg-open $url: $e');
    }
  }

  /// Starts a detached copy of the app and exits this one.
  Future<void> restart() async {
    await Process.start(
      Platform.resolvedExecutable,
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  static Future<bool> _writable(Directory dir) async {
    try {
      final probe = await File('${dir.path}/.promptorium-write-test').create();
      await probe.delete();
      return true;
    } on FileSystemException {
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
