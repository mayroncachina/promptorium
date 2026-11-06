import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;

import 'voice_model.dart';

/// Why a model could not be downloaded.
class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// "Cancelar" of a download.
class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();
}

/// Stops a download: [cancel] drops the partial file, [pause] keeps it.
class ModelDownloadToken {
  final _stop = Completer<void>();
  bool _keepPartial = true;

  bool get stopped => _stop.isCompleted;
  bool get keepsPartial => _keepPartial;
  Future<void> get whenStopped => _stop.future;

  void cancel() {
    _keepPartial = false;
    if (!_stop.isCompleted) _stop.complete();
  }

  void pause() {
    if (!_stop.isCompleted) _stop.complete();
  }
}

Future<String> _sha256Of(String path) => Isolate.run(() async {
  final digest = await crypto.sha256.bind(File(path).openRead()).first;
  return digest.toString();
});

/// The model files, in the data folder of the app (SPEC-040 R2). What is
/// being downloaded stays in `<file>.part`: only a file whose `sha256` was
/// checked gets the final name.
class ModelStore {
  ModelStore(
    this.directory, {
    Uri Function(VoiceModel)? urlOf,
    String Function(VoiceModel)? hashOf,
    Future<String> Function(String path)? hash,
    this.verifyLimit = const Duration(seconds: 30),
    this.stallLimit = const Duration(seconds: 30),
  }) : _urlOf = urlOf ?? ((m) => m.url),
       _hashOf = hashOf ?? ((m) => m.sha256),
       _hash = hash ?? _sha256Of;

  final Directory directory;
  final Uri Function(VoiceModel) _urlOf;
  final String Function(VoiceModel) _hashOf;
  final Future<String> Function(String path) _hash;

  /// R2: a check that takes longer than this is a failed download.
  final Duration verifyLimit;

  /// No data for this long fails the download.
  final Duration stallLimit;

  File fileOf(VoiceModel m) => File('${directory.path}/${m.file}');
  File partOf(VoiceModel m) => File('${directory.path}/${m.file}.part');

  bool isInstalled(VoiceModel m) => fileOf(m).existsSync();

  /// A download stopped halfway, which the next one continues.
  bool hasPartial(VoiceModel m) => partOf(m).existsSync();

  Set<VoiceModel> get installed => {
    for (final m in VoiceModel.values)
      if (isInstalled(m)) m,
  };

  Future<void> remove(VoiceModel m) async {
    for (final f in [fileOf(m), partOf(m)]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// Downloads [m], from where it stopped, and checks it. Throws
  /// [ModelDownloadCancelled] when [token] stops it and
  /// [ModelDownloadException] on a failure, which keeps what arrived unless
  /// the file came wrong.
  Future<void> download(
    VoiceModel m, {
    required void Function(int received, int total) onProgress,
    required void Function() onVerifying,
    ModelDownloadToken? token,
  }) async {
    final stop = token ?? ModelDownloadToken();
    await directory.create(recursive: true);
    final part = partOf(m);
    try {
      await _fetch(m, part, stop, onProgress);
      if (stop.stopped) throw const ModelDownloadCancelled();
      onVerifying();
      await _verify(m, part, stop);
      await part.rename(fileOf(m).path);
    } on ModelDownloadCancelled {
      if (!stop.keepsPartial && await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<void> _fetch(
    VoiceModel m,
    File part,
    ModelDownloadToken stop,
    void Function(int, int) onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = stallLimit;
    unawaited(stop.whenStopped.then((_) => client.close(force: true)));
    IOSink? sink;
    try {
      var start = await part.exists() ? await part.length() : 0;
      final request = await client.getUrl(_urlOf(m));
      if (start > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
      }
      final response = await request.close().timeout(stallLimit);
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        return; // everything is here already; the check decides
      }
      if (response.statusCode == HttpStatus.ok) {
        start = 0; // the server ignored the range
      } else if (response.statusCode != HttpStatus.partialContent) {
        throw ModelDownloadException(
          'O servidor respondeu ${response.statusCode}.',
        );
      }
      final total = response.contentLength < 0
          ? m.bytes
          : start + response.contentLength;
      var received = start;
      onProgress(received, total);
      sink = part.openWrite(
        mode: start > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly,
      );
      await for (final chunk in response.timeout(stallLimit)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      if (received < total) {
        throw const ModelDownloadException('A conexão terminou antes do fim.');
      }
    } on ModelDownloadException {
      if (stop.stopped) throw const ModelDownloadCancelled();
      rethrow;
    } on ModelDownloadCancelled {
      rethrow;
    } catch (e) {
      if (stop.stopped) throw const ModelDownloadCancelled();
      throw ModelDownloadException('$e');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<void> _verify(VoiceModel m, File part, ModelDownloadToken stop) async {
    final String hash;
    try {
      hash = await Future.any([
        _hash(part.path),
        stop.whenStopped.then<String>(
          (_) => throw const ModelDownloadCancelled(),
        ),
      ]).timeout(verifyLimit);
    } on TimeoutException {
      throw const ModelDownloadException(
        'A conferência do arquivo demorou demais.',
      );
    }
    if (hash != _hashOf(m)) {
      await part.delete();
      throw const ModelDownloadException('O arquivo baixado não confere.');
    }
  }
}
