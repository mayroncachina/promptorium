import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/dictation/dictation_controller.dart';
import 'package:promptorium/features/dictation/model_store.dart';
import 'package:promptorium/features/dictation/voice_io.dart';
import 'package:promptorium/features/dictation/voice_model.dart';

class FakeRecording implements VoiceRecording {
  @override
  double level = .4;
  bool stopped = false;
  bool cancelled = false;

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> cancel() async => cancelled = true;
}

class FakeRecorder implements VoiceRecorder {
  final started = <String>[];
  final recordings = <FakeRecording>[];
  bool noMicrophone = false;

  /// Holds [start], as a slow `arecord` does.
  Completer<void>? gate;
  List<MicDevice> mics = const [MicDevice('plughw:0,0', 'Microfone interno')];

  @override
  Future<VoiceRecording> start(String path, {String? device}) async {
    await gate?.future;
    if (noMicrophone) throw const NoMicrophone();
    File(path).writeAsBytesSync([1, 2, 3]);
    started.add(path);
    final r = FakeRecording();
    recordings.add(r);
    return r;
  }

  @override
  Future<List<MicDevice>> devices() async => mics;
}

class FakeTranscriber implements VoiceTranscriber {
  final runs = <({String audio, String model, String language})>[];
  Object? error;
  String text = 'texto ditado';
  Completer<void>? gate;

  @override
  Future<String> transcribe(
    String audio, {
    required String model,
    required String language,
    Future<void>? cancelled,
  }) async {
    runs.add((audio: audio, model: model, language: language));
    final wait = gate;
    if (wait != null) {
      await Future.any([wait.future, ?cancelled]);
    }
    if (error != null) throw error!;
    return text;
  }
}

/// A store whose download the test drives.
class FakeStore extends ModelStore {
  FakeStore(super.directory);

  void Function(int, int)? progress;
  void Function()? verifying;
  VoiceModel? downloading;
  Completer<void>? run;
  ModelDownloadToken? token;

  void install(VoiceModel m) {
    directory.createSync(recursive: true);
    fileOf(m).writeAsStringSync('x');
  }

  void partial(VoiceModel m) {
    directory.createSync(recursive: true);
    partOf(m).writeAsStringSync('x');
  }

  @override
  Future<void> download(
    VoiceModel m, {
    required void Function(int, int) onProgress,
    required void Function() onVerifying,
    ModelDownloadToken? token,
  }) async {
    downloading = m;
    progress = onProgress;
    verifying = onVerifying;
    this.token = token;
    final done = run = Completer<void>();
    unawaited(
      token?.whenStopped.then((_) {
        if (!done.isCompleted) {
          done.completeError(const ModelDownloadCancelled());
        }
      }),
    );
    await done.future;
    install(m);
  }

  void finish() => run!.complete();
  void fail() => run!.completeError(const ModelDownloadException('sem rede'));
}

/// Overrides that make the dictation available with fakes.
List<Override> dictationOverrides({
  required FakeStore store,
  required FakeRecorder recorder,
  required FakeTranscriber transcriber,
}) => [
  modelStoreProvider.overrideWithValue(store),
  voiceRecorderProvider.overrideWithValue(recorder),
  voiceTranscriberProvider.overrideWithValue(transcriber),
];

Finder key(String k) => find.byKey(ValueKey(k));

/// Real file IO does not run under FakeAsync.
Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  for (var i = 0; DateTime.now().isBefore(end); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (i >= 4 && (until?.call() ?? true)) return;
  }
}
