import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/dictation/dictation_controller.dart';
import 'package:promptorium/features/dictation/dictation_widgets.dart';
import 'package:promptorium/features/dictation/voice_io.dart';
import 'package:promptorium/features/dictation/voice_model.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import 'dictation_test_utils.dart';

/// One composer, as the screens have it.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.onSend});

  final VoidCallback onSend;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final text = TextEditingController(text: 'Ajuste o lembrete para');
  final focus = FocusNode();
  late final target = DictationTarget(
    id: 'test',
    controller: text,
    focusNode: focus,
  );

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      DictationNotices(target: target),
      DictationLock(
        id: target.id,
        builder: (locked) => TextField(
          key: const ValueKey('field'),
          controller: text,
          focusNode: focus,
          readOnly: locked,
        ),
      ),
      DictationActions(
        target: target,
        child: Row(
          key: const ValueKey('actions'),
          children: [
            const Spacer(),
            DictationButton(target: target),
            TextButton(
              key: const ValueKey('send'),
              onPressed: sendHeld(ref, target.id) ? null : widget.onSend,
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    ],
  );
}

const mic = 'dictation-button-test';

late ProviderContainer c;

/// A test that ends with no timer left: the recording, the 800 ms of Enviar
/// and the notice.
void t(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      unawaited(c.read(dictationProvider.notifier).cancel());
      await settle(tester);
      await tester.pump(const Duration(seconds: 7));
    });

void main() {
  late Directory tmp;
  late FakeStore store;
  late FakeRecorder recorder;
  late FakeTranscriber transcriber;
  late int sends;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-dictation-');
    store = FakeStore(Directory('${tmp.path}/models'));
    recorder = FakeRecorder();
    transcriber = FakeTranscriber();
    sends = 0;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, {bool model = true}) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (model) store.install(VoiceModel.quality);
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        ...dictationOverrides(
          store: store,
          recorder: recorder,
          transcriber: transcriber,
        ),
      ],
    );
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: DictationHost(child: _Composer(onSend: () => sends++)),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(Duration.zero);
    });
    await settle(tester);
  }

  TextEditingController text(WidgetTester tester) =>
      tester.widget<TextField>(key('field')).controller!;

  DictationState state() => c.read(dictationProvider);

  Future<void> record(WidgetTester tester) async {
    await tester.tap(key(mic));
    await settle(tester, until: () => recorder.started.isNotEmpty);
    await settle(
      tester,
      until: () => key('dictation-recording').evaluate().isNotEmpty,
    );
  }

  Future<void> ctrlShiftM(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  group('R2', () {
    t('without a model the click asks; the download shows the '
        'percentage, then the check, and ends in Modelo pronto without '
        'recording; Falar agora starts', (tester) async {
      await pump(tester, model: false);
      await tester.tap(key(mic));
      await settle(
        tester,
        until: () => key('voice-dialog').evaluate().isNotEmpty,
      );
      expect(find.text('Ativar o ditado por voz'), findsOneWidget);
      expect(find.textContaining('190 MB'), findsOneWidget);

      await tester.tap(key('voice-download'));
      await settle(tester, until: () => store.progress != null);
      store.progress!(89000000, 190000000);
      await settle(tester);
      expect(find.text('Baixando o modelo de voz'), findsOneWidget);
      expect(find.text('89 MB de 190 MB'), findsOneWidget);
      expect(tester.widget<Text>(key('voice-percent')).data, '46%');

      store.verifying!();
      await settle(tester);
      expect(find.text('Conferindo o arquivo'), findsOneWidget);

      store.finish();
      await settle(
        tester,
        until: () => find.text('Modelo pronto').evaluate().isNotEmpty,
      );
      expect(recorder.started, isEmpty);
      await tester.tap(key('voice-talk'));
      await settle(tester, until: () => recorder.started.isNotEmpty);
      expect(recorder.started, hasLength(1));
    });

    t('Agora não closes and nothing is downloaded', (tester) async {
      await pump(tester, model: false);
      await tester.tap(key(mic));
      await settle(tester);
      await tester.tap(key('voice-not-now'));
      await settle(tester);
      expect(store.downloading, isNull);
      expect(key('voice-dialog'), findsNothing);
    });

    t('a partial file continues on the click', (tester) async {
      store.partial(VoiceModel.quality);
      await pump(tester, model: false);
      await tester.tap(key(mic));
      await settle(tester, until: () => store.progress != null);
      expect(store.downloading, VoiceModel.quality);
      expect(find.text('Baixando o modelo de voz'), findsOneWidget);
    });
  });

  group('R10', () {
    Future<void> downloadInBackground(WidgetTester tester) async {
      await pump(tester, model: false);
      await tester.tap(key(mic));
      await settle(tester);
      await tester.tap(key('voice-download'));
      await settle(tester, until: () => store.progress != null);
      store.progress!(47, 100);
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); // R2: Esc too
      await settle(tester, until: () => key('voice-dialog').evaluate().isEmpty);
    }

    t('the app stays usable, the button shows the progress and '
        'reopens the dialog; the final notice stays out of the composer and '
        'leaves alone', (tester) async {
      await downloadInBackground(tester);
      expect(c.read(voiceModelsProvider).background, isTrue);
      expect(key('dictation-button-percent'), findsOneWidget);
      expect(tester.widget<Text>(key('dictation-button-percent')).data, '47%');
      await tester.tap(key('send'));
      await tester.pump();
      expect(sends, 1);

      await tester.tap(key(mic));
      await settle(
        tester,
        until: () => key('voice-dialog').evaluate().isNotEmpty,
      );
      expect(find.text('Baixando o modelo de voz'), findsOneWidget);
      await tester.tap(key('voice-background'));
      await settle(tester, until: () => key('voice-dialog').evaluate().isEmpty);

      store.finish();
      await settle(
        tester,
        until: () => key('voice-notice').evaluate().isNotEmpty,
      );
      expect(
        find.text('Modelo pronto. Clique no microfone para falar.'),
        findsOneWidget,
      );
      expect(key('voice-dialog'), findsNothing);
      final notice = tester.getRect(key('voice-notice'));
      expect(notice.overlaps(tester.getRect(key('field'))), isFalse);
      expect(notice.overlaps(tester.getRect(key('send'))), isFalse);
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(key('voice-notice'), findsNothing);
    });

    t('a failure marks the button and waits; Ver detalhes offers '
        'Tentar de novo', (tester) async {
      await downloadInBackground(tester);
      store.fail();
      await settle(
        tester,
        until: () => key('voice-notice').evaluate().isNotEmpty,
      );
      expect(find.text('Não foi possível baixar o modelo'), findsOneWidget);
      expect(key('voice-dialog'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(key('voice-notice'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(key(mic));
      await settle(
        tester,
        until: () => key('voice-retry').evaluate().isNotEmpty,
      );
      expect(find.text('Não foi possível baixar o modelo'), findsOneWidget);
      await tester.tap(key('voice-retry'));
      await settle(tester, until: () => c.read(voiceModelsProvider).running);
      expect(find.text('Baixando o modelo de voz'), findsOneWidget);
    });
  });

  group('R3', () {
    t('Ctrl+Shift+M records into the focused field and stops; Esc '
        'cancels with the focus anywhere', (tester) async {
      await pump(tester);
      await tester.tap(key('field'));
      await tester.pump();
      await ctrlShiftM(tester);
      await settle(
        tester,
        until: () => key('dictation-recording').evaluate().isNotEmpty,
      );
      expect(find.text('Gravando'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(key('send'), findsNothing);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester, until: () => state().phase == DictationPhase.idle);
      expect(recorder.recordings.single.cancelled, isTrue);
      expect(File(recorder.started.single).existsSync(), isFalse);
      expect(text(tester).text, 'Ajuste o lembrete para');

      await tester.tap(key('field'));
      await tester.pump();
      await ctrlShiftM(tester);
      await settle(tester, until: () => recorder.started.length == 2);
      await settle(
        tester,
        until: () => key('dictation-recording').evaluate().isNotEmpty,
      );
      await ctrlShiftM(tester);
      await settle(tester, until: () => transcriber.runs.isNotEmpty);
      expect(recorder.recordings.last.stopped, isTrue);
    });

    t('Parar before the recorder is up still stops and transcribes', (
      tester,
    ) async {
      await pump(tester);
      recorder.gate = Completer();
      await tester.tap(key(mic));
      await settle(
        tester,
        until: () => key('dictation-recording').evaluate().isNotEmpty,
      );
      await tester.tap(key('dictation-stop'));
      await tester.pump();
      recorder.gate!.complete();
      await settle(tester, until: () => transcriber.runs.isNotEmpty);
      expect(recorder.recordings.single.stopped, isTrue);
    });

    t('only one recording at a time', (tester) async {
      await pump(tester);
      await record(tester);
      await c.read(dictationProvider.notifier).start('outro');
      expect(recorder.started, hasLength(1));
      expect(state().targetId, 'test');
    });

    t('it stops alone at 5 minutes and transcribes', (tester) async {
      await pump(tester);
      await record(tester);
      expect(DictationController.maxDuration, const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await settle(tester, until: () => transcriber.runs.isNotEmpty);
      expect(recorder.recordings.single.stopped, isTrue);
    });

    t('leaving the screen cancels and says so', (tester) async {
      await pump(tester);
      await record(tester);
      final path = recorder.started.single;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: DictationHost(child: SizedBox())),
          ),
        ),
      );
      await settle(tester, until: () => recorder.recordings.single.cancelled);
      await settle(tester, until: () => !File(path).existsSync());
      expect(File(path).existsSync(), isFalse);
      expect(state().phase, DictationPhase.idle);
    });
  });

  group('R4, R5', () {
    t('the field locks while transcribing; the audio is deleted; '
        'the text enters at the cursor, is not sent and Enviar waits 800 ms', (
      tester,
    ) async {
      await pump(tester);
      unawaited(
        c
            .read(appSettingsProvider.notifier)
            .set(AppSettingKeys.voiceLanguage, VoiceLanguage.auto.name),
      );
      await settle(tester);
      await record(tester);
      final path = recorder.started.single;
      transcriber
        ..text = 'as nove horas'
        ..gate = Completer();
      await tester.tap(key('dictation-stop'));
      await settle(tester, until: () => transcriber.runs.isNotEmpty);
      expect(find.text('Transcrevendo…'), findsOneWidget);
      expect(tester.widget<TextField>(key('field')).readOnly, isTrue);
      expect(transcriber.runs.single.language, 'auto');
      expect(
        transcriber.runs.single.model,
        store.fileOf(VoiceModel.quality).path,
      );

      transcriber.gate!.complete();
      await settle(
        tester,
        until: () => key('dictation-inserted').evaluate().isNotEmpty,
      );
      expect(text(tester).text, 'Ajuste o lembrete para as nove horas');
      expect(File(path).existsSync(), isFalse);
      expect(find.text('Texto inserido. Revise e envie.'), findsOneWidget);
      expect(sends, 0);
      expect(tester.widget<TextButton>(key('send')).onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();
      expect(tester.widget<TextButton>(key('send')).onPressed, isNotNull);

      text(tester).text = 'editado';
      await tester.pump();
      expect(key('dictation-inserted'), findsNothing);
    });

    t('Cancelar during the transcription deletes the audio and '
        'leaves the field', (tester) async {
      await pump(tester);
      await record(tester);
      final path = recorder.started.single;
      transcriber.gate = Completer();
      await tester.tap(key('dictation-stop'));
      await settle(tester, until: () => transcriber.runs.isNotEmpty);
      await tester.tap(key('dictation-cancel'));
      await settle(tester, until: () => state().phase == DictationPhase.idle);
      await settle(tester, until: () => !File(path).existsSync());
      expect(File(path).existsSync(), isFalse);
      expect(text(tester).text, 'Ajuste o lembrete para');
      expect(find.text('Transcrição cancelada.'), findsOneWidget);
    });

    test('the text enters with spaces only when needed', () {
      TextEditingValue at(String t, int a, [int? b]) => TextEditingValue(
        text: t,
        selection: TextSelection(baseOffset: a, extentOffset: b ?? a),
      );
      expect(insertDictated(at('', 0), 'oi').text, 'oi');
      expect(insertDictated(at('olá ', 4), 'oi').text, 'olá oi');
      expect(insertDictated(at('olá', 3), 'oi').text, 'olá oi');
      expect(insertDictated(at('a b', 1), 'oi').text, 'a oi b');
      expect(insertDictated(at('ab', 1), 'oi').text, 'a oi b');
      expect(insertDictated(at('a.', 1), 'oi').text, 'a oi.');
      expect(insertDictated(at('a xx b', 2, 4), 'oi').text, 'a oi b');
      expect(insertDictated(at('olá', 3), 'oi').selection.baseOffset, 6);
    });
  });

  group('R6', () {
    t('no microphone keeps the text and offers the next step', (tester) async {
      await pump(tester);
      recorder.noMicrophone = true;
      await tester.tap(key(mic));
      await settle(
        tester,
        until: () => key('dictation-issue').evaluate().isNotEmpty,
      );
      expect(find.text('Nenhum microfone encontrado'), findsOneWidget);
      expect(key('dictation-settings'), findsOneWidget);
      expect(text(tester).text, 'Ajuste o lembrete para');
      recorder.noMicrophone = false;
      await tester.tap(key('dictation-retry'));
      await settle(tester, until: () => recorder.started.isNotEmpty);
      await settle(
        tester,
        until: () => key('dictation-recording').evaluate().isNotEmpty,
      );
    });

    t('no speech deletes the audio and keeps the text', (tester) async {
      await pump(tester);
      transcriber.text = '';
      await record(tester);
      final path = recorder.started.single;
      await tester.tap(key('dictation-stop'));
      await settle(
        tester,
        until: () => key('dictation-issue').evaluate().isNotEmpty,
      );
      expect(find.text('Nenhuma fala detectada'), findsOneWidget);
      expect(File(path).existsSync(), isFalse);
      expect(text(tester).text, 'Ajuste o lembrete para');
    });

    t('a failed transcription keeps the audio, locks the microphone '
        'and discards only with confirmation; Tentar de novo uses the same '
        'audio', (tester) async {
      await pump(tester);
      transcriber.error = const TranscribeFailure('falhou');
      await record(tester);
      final path = recorder.started.single;
      await tester.tap(key('dictation-stop'));
      await settle(
        tester,
        until: () => key('dictation-issue').evaluate().isNotEmpty,
      );
      expect(find.text('Não foi possível transcrever'), findsOneWidget);
      expect(File(path).existsSync(), isTrue);
      expect(state().blocked, isTrue);
      expect(text(tester).text, 'Ajuste o lembrete para');

      await tester.tap(key(mic), warnIfMissed: false);
      await settle(tester);
      expect(recorder.started, hasLength(1)); // locked

      await tester.tap(key('dictation-discard'));
      await settle(tester);
      expect(find.text('Descartar a gravação?'), findsOneWidget);
      final keep = tester.widget<FilledButton>(key('dictation-discard-keep'));
      expect(keep.autofocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(File(path).existsSync(), isTrue);

      transcriber.error = null;
      await tester.tap(key('dictation-retry'));
      await settle(
        tester,
        until: () => key('dictation-inserted').evaluate().isNotEmpty,
      );
      expect(transcriber.runs.map((r) => r.audio), [path, path]);
      expect(text(tester).text, 'Ajuste o lembrete para texto ditado');
      expect(File(path).existsSync(), isFalse);
      expect(state().blocked, isFalse);
    });

    t('Descartar áudio removes it', (tester) async {
      await pump(tester);
      transcriber.error = const TranscribeFailure('falhou');
      await record(tester);
      final path = recorder.started.single;
      await tester.tap(key('dictation-stop'));
      await settle(
        tester,
        until: () => key('dictation-issue').evaluate().isNotEmpty,
      );
      await tester.tap(key('dictation-discard'));
      await settle(tester);
      await tester.tap(key('dictation-discard-confirm'));
      await settle(tester, until: () => !File(path).existsSync());
      expect(File(path).existsSync(), isFalse);
      expect(state().blocked, isFalse);
      expect(find.text('Gravação descartada.'), findsOneWidget);
    });
  });

  group('R7', () {
    t('switching models keeps the current one until the new one '
        'arrives, and removes it only then', (tester) async {
      await pump(tester);
      final models = c.read(voiceModelsProvider.notifier);
      unawaited(models.choose(VoiceModel.fast));
      await settle(tester);
      expect(models.active, VoiceModel.quality);
      unawaited(models.start());
      await settle(tester, until: () => store.progress != null);
      expect(store.isInstalled(VoiceModel.quality), isTrue);
      expect(models.active, VoiceModel.quality);
      store.finish();
      await settle(
        tester,
        until: () => c.read(voiceModelsProvider).phase == ModelPhase.ready,
      );
      expect(store.isInstalled(VoiceModel.quality), isFalse);
      expect(models.active, VoiceModel.fast);
    });
  });
}
