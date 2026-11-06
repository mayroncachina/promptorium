import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/dictation/dictation_controller.dart';
import 'package:promptorium/features/dictation/dictation_widgets.dart';
import 'package:promptorium/features/dictation/voice_io.dart';
import 'package:promptorium/features/dictation/voice_model.dart';
import 'package:promptorium/features/sessions/widgets/composer.dart';
import 'package:promptorium/features/sessions/widgets/question_card.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart' hide settle;
import 'dictation_test_utils.dart';

void main() {
  late Directory tmp;
  late FakeStore store;
  late FakeRecorder recorder;
  late FakeTranscriber transcriber;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-mic-');
    store = FakeStore(Directory('${tmp.path}/models'))
      ..install(VoiceModel.quality);
    recorder = FakeRecorder();
    transcriber = FakeTranscriber();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool available = true,
    Size size = const Size(1044, 628),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = ProviderContainer(
      overrides: [
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: FakeCli(),
          notifier: FakeNotifier(),
        ),
        if (available)
          ...dictationOverrides(
            store: store,
            recorder: recorder,
            transcriber: transcriber,
          )
        else ...[
          whisperCliProvider.overrideWithValue(null),
          modelStoreProvider.overrideWithValue(store),
        ],
      ],
    );
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: DictationHost(
              child: Align(alignment: Alignment.bottomCenter, child: child),
            ),
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

  const composer = SessionComposer(sessionId: 's1', permissionMode: null);

  testWidgets('R1: the microphone is left of Enviar, with the hint', (
    tester,
  ) async {
    await pump(tester, composer);
    final mic = key('dictation-button-session');
    expect(mic, findsOneWidget);
    expect(
      tester.getCenter(mic).dx,
      lessThan(tester.getCenter(key('composer-send')).dx),
    );
    expect(find.byTooltip(dictationHint), findsOneWidget);
    expect(dictationHint, 'Ditar por voz (Ctrl+Shift+M)');
  });

  testWidgets('R1: the answer of a question has it once "Outro" is open', (
    tester,
  ) async {
    await pump(
      tester,
      QuestionCard(
        questions: parseAskQuestions({
          'questions': [
            {
              'question': 'Qual canal?',
              'options': [
                {'label': 'E-mail'},
              ],
            },
          ],
        })!,
        onSubmit: (_) {},
        onDecline: () {},
      ),
    );
    expect(key('dictation-button-question-0'), findsNothing);
    await tester.tap(key('question-0-other'));
    await settle(tester);
    expect(key('dictation-button-question-0'), findsOneWidget);
  });

  testWidgets('R1: a field outside the list has no microphone', (tester) async {
    await pump(tester, const TextField());
    expect(find.byType(DictationButton), findsNothing);
  });

  testWidgets('R8: without the whisper-cli the button does not appear', (
    tester,
  ) async {
    await pump(tester, composer, available: false);
    expect(key('composer-send'), findsOneWidget);
    expect(key('dictation-button-session'), findsNothing);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('R9: the composer fits 1100×700 recording, transcribing and '
      'with an error, and Tab reaches the microphone', (tester) async {
    await pump(tester, composer);
    await tester.tap(key('dictation-button-session'));
    await settle(
      tester,
      until: () => key('dictation-recording').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    expect(key('dictation-stop'), findsOneWidget);

    transcriber.error = const TranscribeFailure('falhou');
    await tester.tap(key('dictation-stop'));
    await settle(
      tester,
      until: () => key('dictation-issue').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    expect(key('composer-send'), findsOneWidget);
    expect(key('dictation-retry'), findsOneWidget);
    expect(find.text('Não foi possível transcrever'), findsOneWidget);

    unawaited(c.read(dictationProvider.notifier).discardAudio());
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
  });
}
