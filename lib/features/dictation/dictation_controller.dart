import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'model_store.dart';
import 'voice_io.dart';
import 'voice_model.dart';

/// The `whisper-cli` of the package, beside the executable of the app.
/// Null (`flutter run`, Windows) hides the dictation (SPEC-040 R8).
final whisperCliProvider = Provider<String?>((ref) {
  if (!Platform.isLinux) return null;
  final app = File(Platform.resolvedExecutable);
  final cli = File('${app.parent.path}/whisper-cli');
  return cli.existsSync() ? cli.path : null;
});

final _voiceDataDirProvider = FutureProvider<Directory>(
  (ref) => databaseDirectory(),
);

final modelStoreProvider = Provider<ModelStore?>((ref) {
  final dir = ref.watch(_voiceDataDirProvider).value;
  return dir == null ? null : ModelStore(Directory('${dir.path}/voice-models'));
});

final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => ArecordRecorder(),
);

final voiceTranscriberProvider = Provider<VoiceTranscriber?>((ref) {
  final cli = ref.watch(whisperCliProvider);
  return cli == null ? null : WhisperTranscriber(cli);
});

final micDevicesProvider = FutureProvider.autoDispose<List<MicDevice>>(
  (ref) => ref.watch(voiceRecorderProvider).devices(),
);

/// Whether the dictation exists in this install (R8).
final dictationAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(voiceTranscriberProvider) != null &&
      ref.watch(modelStoreProvider) != null,
);

enum ModelPhase { idle, downloading, verifying, ready, failed }

/// What the app says about a download in the background (R10).
enum ModelNotice { ready, failed }

@immutable
class VoiceModelsState {
  const VoiceModelsState({
    this.installed = const {},
    this.phase = ModelPhase.idle,
    this.target,
    this.received = 0,
    this.total = 0,
    this.background = false,
    this.notice,
    this.error,
  });

  final Set<VoiceModel> installed;
  final ModelPhase phase;

  /// The model being downloaded.
  final VoiceModel? target;
  final int received;
  final int total;
  final bool background;
  final ModelNotice? notice;
  final String? error;

  bool get running =>
      phase == ModelPhase.downloading || phase == ModelPhase.verifying;

  int get percent =>
      total == 0 ? 0 : (received * 100 / total).floor().clamp(0, 100);

  VoiceModelsState copyWith({
    Set<VoiceModel>? installed,
    ModelPhase? phase,
    VoiceModel? target,
    int? received,
    int? total,
    bool? background,
    ModelNotice? Function()? notice,
    String? Function()? error,
  }) => VoiceModelsState(
    installed: installed ?? this.installed,
    phase: phase ?? this.phase,
    target: target ?? this.target,
    received: received ?? this.received,
    total: total ?? this.total,
    background: background ?? this.background,
    notice: notice == null ? this.notice : notice(),
    error: error == null ? this.error : error(),
  );
}

/// The installed models and the download, which outlives the dialog (R2, R7,
/// R10).
class VoiceModels extends Notifier<VoiceModelsState> {
  ModelDownloadToken? _token;

  @override
  VoiceModelsState build() {
    final store = ref.watch(modelStoreProvider);
    ref.onDispose(() => _token?.pause());
    return VoiceModelsState(installed: store?.installed ?? const {});
  }

  /// The model of Configurações.
  VoiceModel get choice =>
      VoiceModel.values.asNameMap()[ref
          .read(appSettingsProvider.notifier)
          .get(AppSettingKeys.voiceModel)] ??
      VoiceModel.quality;

  /// R7: the model in use, which may be the old one until the new arrives.
  VoiceModel? get active {
    if (state.installed.contains(choice)) return choice;
    return state.installed.firstOrNull;
  }

  bool get hasPartial =>
      ref.read(modelStoreProvider)?.hasPartial(choice) ?? false;

  Future<void> choose(VoiceModel m) async {
    await ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.voiceModel, m.name);
    ref.notifyListeners();
  }

  Future<void> start({bool background = false}) async {
    final store = ref.read(modelStoreProvider);
    if (store == null || state.running) return;
    final m = choice;
    final token = _token = ModelDownloadToken();
    state = state.copyWith(
      phase: ModelPhase.downloading,
      target: m,
      received: 0,
      total: m.bytes,
      background: background,
      notice: () => null,
      error: () => null,
    );
    try {
      await store.download(
        m,
        token: token,
        onProgress: (received, total) {
          if (ref.mounted) {
            state = state.copyWith(received: received, total: total);
          }
        },
        onVerifying: () {
          if (ref.mounted) state = state.copyWith(phase: ModelPhase.verifying);
        },
      );
      if (!ref.mounted) return;
      // R7: only now the previous model leaves.
      for (final other in VoiceModel.values) {
        if (other != m) await store.remove(other);
      }
      state = state.copyWith(
        installed: store.installed,
        phase: ModelPhase.ready,
        notice: () => state.background ? ModelNotice.ready : null,
      );
    } on ModelDownloadCancelled {
      if (ref.mounted) {
        state = state.copyWith(phase: ModelPhase.idle, background: false);
      }
    } catch (e) {
      debugPrint('Download do modelo de voz: $e');
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: ModelPhase.failed,
        error: () => '$e',
        notice: () => state.background ? ModelNotice.failed : null,
      );
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  void cancel() {
    _token?.cancel();
    if (!state.running) {
      state = state.copyWith(
        phase: ModelPhase.idle,
        background: false,
        notice: () => null,
      );
    }
  }

  /// "Continuar em segundo plano" (R10).
  void toBackground() {
    if (state.running) state = state.copyWith(background: true);
  }

  /// The dialog came back: its screens replace the notice.
  void toForeground() =>
      state = state.copyWith(background: false, notice: () => null);

  /// The end was seen ("Modelo pronto").
  void acknowledge() {
    if (state.phase == ModelPhase.ready) {
      state = state.copyWith(
        phase: ModelPhase.idle,
        background: false,
        notice: () => null,
      );
    }
  }

  void dismissNotice() {
    if (state.notice == ModelNotice.ready) {
      acknowledge();
    } else {
      state = state.copyWith(notice: () => null);
    }
  }

  Future<void> remove() async {
    final store = ref.read(modelStoreProvider);
    if (store == null) return;
    for (final m in VoiceModel.values) {
      await store.remove(m);
    }
    state = state.copyWith(installed: store.installed);
  }
}

final voiceModelsProvider = NotifierProvider<VoiceModels, VoiceModelsState>(
  VoiceModels.new,
);

/// A text field that takes dictation (R1).
class DictationTarget {
  DictationTarget({
    required this.id,
    required this.controller,
    required this.focusNode,
    this.onInserted,
  });

  final String id;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// The text changed outside the field's `onChanged`.
  final VoidCallback? onInserted;
}

enum DictationPhase { idle, recording, transcribing }

enum DictationIssue { noMicrophone, noSpeech, transcribeFailed }

@immutable
class DictationState {
  const DictationState({
    this.phase = DictationPhase.idle,
    this.targetId,
    this.elapsed = Duration.zero,
    this.level = 0,
    this.issue,
    this.savedAudio,
    this.insertedIn,
    this.sendHeldIn,
    this.message,
  });

  final DictationPhase phase;

  /// The field of the recording, of the transcription or of the [issue].
  final String? targetId;
  final Duration elapsed;
  final double level;
  final DictationIssue? issue;

  /// R6: audio kept after a failed transcription.
  final String? savedAudio;

  /// "Texto inserido. Revise e envie." (R5).
  final String? insertedIn;

  /// R5: [insertedIn] just got text; Enviar waits a moment.
  final String? sendHeldIn;

  /// Toast to show once ("Gravação cancelada.").
  final String? message;

  bool activeIn(String id) => phase != DictationPhase.idle && targetId == id;

  /// R6: a new recording would lose the saved audio.
  bool get blocked => savedAudio != null;
}

/// Records and transcribes, one at a time, for the field that asked (R3–R6).
class DictationController extends Notifier<DictationState> {
  static const maxDuration = Duration(minutes: 5);
  static const sendHold = Duration(milliseconds: 800);
  static const _tick = Duration(milliseconds: 200);

  final _targets = <String, DictationTarget>{};
  VoiceRecording? _recording;
  String? _audio;
  Timer? _timer;
  Timer? _hold;
  Completer<void>? _cancelRun;
  VoidCallback? _watchEdit;

  @override
  DictationState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _hold?.cancel();
      unawaited(_recording?.cancel());
    });
    return const DictationState();
  }

  void register(DictationTarget t) => _targets[t.id] = t;

  /// The field left the screen. A recording ends with it (R3).
  void unregister(DictationTarget t) {
    if (!identical(_targets[t.id], t)) return;
    _targets.remove(t.id);
    if (state.activeIn(t.id)) {
      final recording = state.phase == DictationPhase.recording;
      scheduleMicrotask(() {
        unawaited(cancel());
        if (recording) _tell('Gravação cancelada.');
      });
    }
  }

  /// The field with the focus, for the shortcut (R3).
  DictationTarget? get focused =>
      _targets.values.where((t) => t.focusNode.hasFocus).firstOrNull;

  DictationTarget? targetOf(String id) => _targets[id];

  void _tell(String message) => state = _with(message: () => message);

  void toastShown() => state = _with(message: () => null);

  DictationState _with({
    DictationPhase? phase,
    String? Function()? targetId,
    Duration? elapsed,
    double? level,
    DictationIssue? Function()? issue,
    String? Function()? savedAudio,
    String? Function()? insertedIn,
    String? Function()? sendHeldIn,
    String? Function()? message,
  }) => DictationState(
    phase: phase ?? state.phase,
    targetId: targetId == null ? state.targetId : targetId(),
    elapsed: elapsed ?? state.elapsed,
    level: level ?? state.level,
    issue: issue == null ? state.issue : issue(),
    savedAudio: savedAudio == null ? state.savedAudio : savedAudio(),
    insertedIn: insertedIn == null ? state.insertedIn : insertedIn(),
    sendHeldIn: sendHeldIn == null ? state.sendHeldIn : sendHeldIn(),
    message: message == null ? state.message : message(),
  );

  Future<void> _deleteAudio(String? path) async {
    if (path == null) return;
    try {
      await File(path).parent.delete(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('Áudio temporário: $e');
    }
  }

  /// Starts recording into [id].
  Future<void> start(String id) async {
    if (state.phase != DictationPhase.idle || state.blocked) return;
    state = _with(
      phase: DictationPhase.recording,
      targetId: () => id,
      elapsed: Duration.zero,
      level: 0,
      issue: () => null,
      insertedIn: () => null,
    );
    final dir = await Directory.systemTemp.createTemp('promptorium-voz-');
    final path = '${dir.path}/audio.wav';
    final device = ref
        .read(appSettingsProvider.notifier)
        .get(AppSettingKeys.voiceDevice);
    try {
      _recording = await ref
          .read(voiceRecorderProvider)
          .start(path, device: device);
    } on NoMicrophone {
      await _deleteAudio(path);
      state = _with(
        phase: DictationPhase.idle,
        issue: () => DictationIssue.noMicrophone,
      );
      return;
    }
    if (state.phase != DictationPhase.recording || state.targetId != id) {
      await _recording?.cancel();
      _recording = null;
      await _deleteAudio(path);
      return;
    }
    _audio = path;
    var ticks = 0;
    _timer = Timer.periodic(_tick, (_) {
      final elapsed = _tick * ++ticks;
      state = _with(elapsed: elapsed, level: _recording?.level ?? 0);
      if (elapsed >= maxDuration) unawaited(stop());
    });
  }

  void _endTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// "Parar e transcrever".
  Future<void> stop() async {
    final recording = _recording, path = _audio, id = state.targetId;
    if (state.phase != DictationPhase.recording ||
        recording == null ||
        path == null ||
        id == null) {
      return;
    }
    _endTimer();
    _recording = null;
    _audio = null;
    state = _with(phase: DictationPhase.transcribing, level: 0);
    await recording.stop();
    await _transcribe(id, path);
  }

  Future<void> _transcribe(String id, String path) async {
    final transcriber = ref.read(voiceTranscriberProvider);
    final store = ref.read(modelStoreProvider);
    final model = ref.read(voiceModelsProvider.notifier).active;
    final cancel = _cancelRun = Completer<void>();
    final name = ref
        .read(appSettingsProvider.notifier)
        .get(AppSettingKeys.voiceLanguage);
    final language =
        (VoiceLanguage.values.asNameMap()[name] ?? VoiceLanguage.portuguese)
            .code;
    try {
      if (transcriber == null || store == null || model == null) {
        throw const TranscribeFailure('O modelo de voz não está instalado.');
      }
      final text = await transcriber.transcribe(
        path,
        model: store.fileOf(model).path,
        language: language,
        cancelled: cancel.future,
      );
      if (cancel.isCompleted) {
        await _ended(path, 'Transcrição cancelada.');
        return;
      }
      await _deleteAudio(path);
      if (text.trim().isEmpty) {
        state = _with(
          phase: DictationPhase.idle,
          issue: () => DictationIssue.noSpeech,
          savedAudio: () => null,
        );
        return;
      }
      state = _with(phase: DictationPhase.idle, savedAudio: () => null);
      _insert(id, text.trim());
    } catch (e) {
      if (cancel.isCompleted) {
        await _ended(path, 'Transcrição cancelada.');
        return;
      }
      debugPrint('Transcrição: $e');
      state = _with(
        phase: DictationPhase.idle,
        issue: () => DictationIssue.transcribeFailed,
        savedAudio: () => path,
      );
    } finally {
      _cancelRun = null;
    }
  }

  Future<void> _ended(String path, String message) async {
    await _deleteAudio(path);
    state = _with(
      phase: DictationPhase.idle,
      targetId: () => null,
      savedAudio: () => null,
      issue: () => null,
      message: () => message,
    );
  }

  void _insert(String id, String text) {
    final t = _targets[id];
    if (t == null) return;
    t.controller.value = insertDictated(t.controller.value, text);
    t.onInserted?.call();
    t.focusNode.requestFocus();
    _stopWatchingEdit();
    final inserted = t.controller.text;
    void edited() {
      if (t.controller.text != inserted) clearInserted();
    }

    t.controller.addListener(edited);
    _watchEdit = () => t.controller.removeListener(edited);
    state = _with(insertedIn: () => id, sendHeldIn: () => id);
    _hold?.cancel();
    _hold = Timer(sendHold, () => state = _with(sendHeldIn: () => null));
  }

  void _stopWatchingEdit() {
    _watchEdit?.call();
    _watchEdit = null;
  }

  /// R5: the note ends at the next edit or send.
  void clearInserted() {
    _stopWatchingEdit();
    if (state.insertedIn != null) state = _with(insertedIn: () => null);
  }

  /// "Cancelar" and `Esc`: nothing goes to the field.
  Future<void> cancel() async {
    if (state.phase == DictationPhase.recording) {
      _endTimer();
      final recording = _recording, path = _audio;
      _recording = null;
      _audio = null;
      state = _with(phase: DictationPhase.idle, targetId: () => null);
      await recording?.cancel();
      await _deleteAudio(path);
    } else if (state.phase == DictationPhase.transcribing) {
      final run = _cancelRun;
      if (run != null && !run.isCompleted) run.complete();
    }
  }

  /// "Tentar de novo" of an issue (R6).
  Future<void> retry() async {
    final id = state.targetId, path = state.savedAudio;
    if (id == null) return;
    if (state.issue == DictationIssue.transcribeFailed && path != null) {
      state = _with(phase: DictationPhase.transcribing, issue: () => null);
      await _transcribe(id, path);
    } else {
      state = _with(issue: () => null);
      await start(id);
    }
  }

  /// Closes an issue that holds no audio.
  void dismissIssue() {
    if (state.savedAudio == null) {
      state = _with(issue: () => null, targetId: () => null);
    }
  }

  /// "Descartar áudio" after the confirmation.
  Future<void> discardAudio() async {
    final path = state.savedAudio;
    state = _with(
      savedAudio: () => null,
      issue: () => null,
      targetId: () => null,
      message: () => 'Gravação descartada.',
    );
    await _deleteAudio(path);
  }
}

final dictationProvider = NotifierProvider<DictationController, DictationState>(
  DictationController.new,
);

/// [value] with [text] at the cursor, keeping what was there, with a space
/// when the words would touch (R5).
TextEditingValue insertDictated(TextEditingValue value, String text) {
  final old = value.text;
  final sel = value.selection;
  final start = sel.isValid ? sel.start : old.length;
  final end = sel.isValid ? sel.end : old.length;
  final before = old.substring(0, start);
  final after = old.substring(end);
  final lead = before.isEmpty || RegExp(r'\s$').hasMatch(before) ? '' : ' ';
  final tail = after.isEmpty || RegExp(r'^[\s.,;:!?]').hasMatch(after)
      ? ''
      : ' ';
  final piece = '$lead$text$tail';
  return TextEditingValue(
    text: '$before$piece$after',
    selection: TextSelection.collapsed(offset: start + piece.length),
  );
}
