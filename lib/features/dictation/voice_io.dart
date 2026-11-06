import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// No microphone answered (SPEC-040 R6).
class NoMicrophone implements Exception {
  const NoMicrophone();
}

/// `whisper-cli` failed (R6).
class TranscribeFailure implements Exception {
  const TranscribeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A microphone of Configurações (R7).
@immutable
class MicDevice {
  const MicDevice(this.id, this.label);

  /// `-D` of `arecord`.
  final String id;
  final String label;

  @override
  bool operator ==(Object other) => other is MicDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A recording in progress.
abstract class VoiceRecording {
  /// Loudness of the last moments, 0 to 1.
  double get level;

  /// Ends the recording, with the file complete.
  Future<void> stop();

  /// Ends the recording. The file stays for the caller to delete.
  Future<void> cancel();
}

abstract class VoiceRecorder {
  /// Starts writing a 16 kHz mono WAV to [path]. Throws [NoMicrophone].
  Future<VoiceRecording> start(String path, {String? device});

  Future<List<MicDevice>> devices();
}

abstract class VoiceTranscriber {
  /// Text of [audio]. Stopping [cancelled] kills the run. Throws
  /// [TranscribeFailure].
  Future<String> transcribe(
    String audio, {
    required String model,
    required String language,
    Future<void>? cancelled,
  });
}

/// Loudness of 16-bit little-endian samples, 0 to 1.
double pcmLevel(Uint8List bytes) {
  final samples = bytes.length ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768;
    sum += s * s;
  }
  return math.min(1, math.sqrt(sum / samples) * 4);
}

/// Microphones in the output of `arecord -l`.
List<MicDevice> parseArecordDevices(String output) => [
  for (final m in RegExp(
    r'^[^\d\n]*(\d+): [^\[\n]*\[([^\]]*)\], [^\d\n]*(\d+): [^\[\n]*\[([^\]]*)\]',
    multiLine: true,
  ).allMatches(output))
    MicDevice(
      'plughw:${m.group(1)},${m.group(3)}',
      m.group(4)!.isEmpty ? m.group(2)! : '${m.group(2)} · ${m.group(4)}',
    ),
];

/// What `whisper-cli` printed, without the marks of silence (`[BLANK_AUDIO]`,
/// `(música)`). Empty = no speech.
String cleanTranscript(String output) => output
    .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class _ArecordRecording implements VoiceRecording {
  _ArecordRecording(this._process, this._path);

  final Process _process;
  final String _path;
  bool _ended = false;

  @override
  double get level {
    try {
      final f = File(_path).openSync();
      try {
        final length = f.lengthSync();
        const window = 3200; // 100 ms
        if (length <= 44 + window) return 0;
        f.setPositionSync(length - window);
        return pcmLevel(f.readSync(window));
      } finally {
        f.closeSync();
      }
    } on FileSystemException {
      return 0;
    }
  }

  /// `arecord` completes the WAV header on SIGINT.
  Future<void> _end() async {
    if (_ended) return;
    _ended = true;
    _process.kill(ProcessSignal.sigint);
    await _process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  @override
  Future<void> stop() => _end();

  @override
  Future<void> cancel() => _end();
}

/// Records with `arecord` (`alsa-utils`, declared by the `.deb`).
class ArecordRecorder implements VoiceRecorder {
  @override
  Future<VoiceRecording> start(String path, {String? device}) async {
    final Process process;
    try {
      process = await Process.start('arecord', [
        '-q',
        '-f',
        'S16_LE',
        '-r',
        '16000',
        '-c',
        '1',
        '-t',
        'wav',
        if (device != null) ...['-D', device],
        path,
      ]);
    } on ProcessException {
      throw const NoMicrophone();
    }
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    // Without a device it exits at once.
    final early = await process.exitCode
        .then<int?>((c) => c)
        .timeout(const Duration(milliseconds: 300), onTimeout: () => null);
    if (early != null) throw const NoMicrophone();
    return _ArecordRecording(process, path);
  }

  @override
  Future<List<MicDevice>> devices() async {
    try {
      final r = await Process.run('arecord', ['-l']);
      return parseArecordDevices('${r.stdout}');
    } on ProcessException {
      return const [];
    }
  }
}

/// Transcribes with the `whisper-cli` of the package (R4, R8).
class WhisperTranscriber implements VoiceTranscriber {
  WhisperTranscriber(this.executable);

  final String executable;

  @override
  Future<String> transcribe(
    String audio, {
    required String model,
    required String language,
    Future<void>? cancelled,
  }) async {
    final Process process;
    try {
      process = await Process.start(executable, [
        '-m',
        model,
        '-f',
        audio,
        '-l',
        language,
        '-t',
        '${math.max(1, math.min(8, Platform.numberOfProcessors))}',
        '-nt',
        '-np',
      ]);
    } on ProcessException catch (e) {
      throw TranscribeFailure(e.message);
    }
    unawaited(cancelled?.then((_) => process.kill(ProcessSignal.sigkill)));
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    if (code != 0) throw TranscribeFailure((await err).trim());
    return cleanTranscript(await out);
  }
}
