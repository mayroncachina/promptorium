import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
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

final _debName = RegExp(r'^promptorium_[0-9][\w.+~-]*_amd64\.deb$');
final _tarName = RegExp(r'^promptorium-[0-9][\w.+~-]*-linux-x64\.tar\.gz$');

/// Throws [FileSystemException] unless [asset] is a package this app ships:
/// an `https://github.com/.../releases/download/...` URL whose last segment is
/// the asset name, and a name matching the `.deb` / `.tar.gz` patterns.
void validateAsset(ReleaseAsset asset) {
  final uri = Uri.tryParse(asset.url);
  if (uri == null || uri.scheme != 'https') {
    throw FileSystemException('Download recusado: só HTTPS (${asset.url}).');
  }
  if (uri.host != 'github.com') {
    throw FileSystemException(
      'Download recusado: host ${uri.host} não é github.com.',
    );
  }
  final segs = uri.pathSegments;
  if (!segs.contains('releases') ||
      !segs.contains('download') ||
      segs.last != asset.name) {
    throw FileSystemException(
      'Download recusado: URL fora do padrão (${asset.url}).',
    );
  }
  if (!_debName.hasMatch(asset.name) && !_tarName.hasMatch(asset.name)) {
    throw FileSystemException(
      'Download recusado: nome de pacote inesperado (${asset.name}).',
    );
  }
}

bool _trustedRedirect(Uri u) =>
    u.scheme == 'https' &&
    (u.host == 'github.com' ||
        u.host.endsWith('.github.com') ||
        u.host.endsWith('.githubusercontent.com'));

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
  const UpdateInstaller({
    this.tempRoot,
    this.skipUrlCheck = false,
    this.executable,
  });

  /// Tests only: lets the download talk to a local http server.
  @visibleForTesting
  final bool skipUrlCheck;

  /// Where the fresh download directory is created (default: system temp).
  final Directory? tempRoot;

  /// The running executable (default: [Platform.resolvedExecutable]).
  final String? executable;

  String get _executable => executable ?? Platform.resolvedExecutable;

  /// Whether the update should be the `.deb`: only when this copy is the
  /// one the `.deb` installs (`/opt/promptorium`) and `pkexec` exists. A
  /// copy extracted elsewhere (`~/.local/share/promptorium/app`) gets the
  /// `.tar.gz` over itself: the `.deb` would install a second copy in /opt
  /// and the restart would open this old one again.
  Future<bool> prefersDeb() async =>
      _executable.startsWith('/opt/promptorium/') && await hasPkexec();

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
      final dir = File(_executable).parent;
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
    await Process.start(_executable, const [], mode: ProcessStartMode.detached);
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

  /// GETs [uri], following redirects by hand so every hop stays on https and
  /// on GitHub's hosts (the release CDN is `*.githubusercontent.com`).
  Future<HttpClientResponse> _open(HttpClient client, Uri uri) async {
    client.autoUncompress = false;
    for (var hop = 0; hop < 5; hop++) {
      final req = await client.getUrl(uri)
        ..followRedirects = false;
      req.headers.set('User-Agent', 'promptorium');
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        final next = loc == null ? null : uri.resolve(loc);
        if (next == null || (!skipUrlCheck && !_trustedRedirect(next))) {
          throw FileSystemException('Redirecionamento recusado: $loc.');
        }
        uri = next;
        continue;
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      return res;
    }
    throw const FileSystemException('Redirecionamentos demais.');
  }

  /// Lowercase hex digest from the release's `<name>.sha256`, or null when the
  /// release doesn't publish one.
  Future<String?> _expectedSha256(
    HttpClient client,
    ReleaseAsset asset,
    List<ReleaseAsset> releaseAssets,
  ) async {
    for (final a in releaseAssets) {
      if (a.name != '${asset.name}.sha256') continue;
      if (!skipUrlCheck) {
        final uri = Uri.tryParse(a.url);
        if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
          throw FileSystemException('Download recusado: ${a.url}.');
        }
      }
      final res = await _open(client, Uri.parse(a.url));
      final body = await res.transform(utf8.decoder).join();
      final m = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(body);
      if (m == null) {
        throw FileSystemException('Arquivo ${a.name} inválido.');
      }
      return m.group(0)!.toLowerCase();
    }
    return null;
  }

  /// Downloads [asset] into a new, empty temporary directory, emitting
  /// progress; the last event carries the file. [releaseAssets] is searched for
  /// a `<name>.sha256` to check the digest. Aborts (deleting the download,
  /// throwing [FileSystemException]) when the URL, the name, the size or the
  /// digest doesn't check out.
  Stream<DownloadProgress> download(
    ReleaseAsset asset, {
    List<ReleaseAsset> releaseAssets = const [],
  }) async* {
    if (!skipUrlCheck) validateAsset(asset);
    final root = tempRoot ?? Directory.systemTemp;
    final dir = await root.createTemp('promptorium-update-');
    final file = File('${dir.path}/${asset.name.split('/').last}');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final expectedSha = await _expectedSha256(client, asset, releaseAssets);
      final res = await _open(client, Uri.parse(asset.url));
      final total = res.contentLength >= 0 ? res.contentLength : null;
      final sink = file.openWrite();
      final digestOut = _DigestSink();
      final digest = crypto.sha256.startChunkedConversion(digestOut);
      var received = 0;
      try {
        yield DownloadProgress(received: 0, total: total);
        await for (final chunk in res) {
          sink.add(chunk);
          digest.add(chunk);
          received += chunk.length;
          yield DownloadProgress(received: received, total: total);
        }
      } finally {
        await sink.close();
      }
      digest.close();
      final want = asset.size ?? total;
      if (want != null && received != want) {
        throw FileSystemException(
          'Tamanho do download não confere ($received de $want bytes).',
        );
      }
      if (expectedSha != null && digestOut.hex != expectedSha) {
        throw const FileSystemException('SHA-256 do download não confere.');
      }
      yield DownloadProgress(received: received, total: total, file: file);
    } catch (_) {
      await dir.delete(recursive: true).catchError((_) => dir);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

final updateInstallerProvider = Provider<UpdateInstaller>(
  (ref) => const UpdateInstaller(),
);

class _DigestSink implements Sink<crypto.Digest> {
  String? hex;

  @override
  void add(crypto.Digest data) => hex = data.toString();

  @override
  void close() {}
}
