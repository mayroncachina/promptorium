import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/dictation/dictation_controller.dart';
import 'package:promptorium/features/dictation/dictation_widgets.dart';
import 'package:promptorium/features/dictation/voice_model.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../dictation/dictation_test_utils.dart';

void main() {
  late Directory tmp;
  late FakeStore store;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-voice-ui-');
    store = FakeStore(Directory('${tmp.path}/models'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        ...dictationOverrides(
          store: store,
          recorder: FakeRecorder(),
          transcriber: FakeTranscriber(),
        ),
      ],
    );
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(child: DictationSettingsCard()),
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

  String status(WidgetTester tester) =>
      tester.widget<Text>(key('voice-status')).data!;

  String? setting(String k) => c.read(appSettingsProvider.notifier).get(k);

  test('R7: the section is found by voice words and marks a change', () {
    expect(filterSections('microfone'), [SettingsSection.dictation]);
    expect(sectionChanged(SettingsSection.dictation, const {}, null), isFalse);
    expect(
      sectionChanged(SettingsSection.dictation, {
        AppSettingKeys.voiceModel: 'fast',
      }, null),
      isTrue,
    );
  });

  testWidgets('R7: the model not yet downloaded says so; the current one '
      'stays in use; Baixar modelo offers only Fechar at the end', (
    tester,
  ) async {
    store.install(VoiceModel.quality);
    await pump(tester);
    expect(status(tester), 'Instalado · 190 MB');
    expect(key('voice-remove'), findsOneWidget);

    await tester.tap(key('voice-model-fast'));
    await settle(tester);
    expect(setting(AppSettingKeys.voiceModel), 'fast');
    expect(
      status(tester),
      'Não instalado · em uso até baixar: Melhor qualidade',
    );
    expect(key('voice-remove'), findsNothing);

    await tester.tap(key('voice-settings-download'));
    await settle(tester, until: () => store.progress != null);
    store.finish();
    await settle(
      tester,
      until: () => find.text('Modelo pronto').evaluate().isNotEmpty,
    );
    expect(key('voice-talk'), findsNothing);
    await tester.tap(key('voice-close'));
    await settle(tester);
    expect(status(tester), 'Instalado · 60 MB');
    expect(store.installed, {VoiceModel.fast});
  });

  testWidgets('R7: language and microphone are saved', (tester) async {
    store.install(VoiceModel.quality);
    await pump(tester);
    await tester.tap(key('voice-language'));
    await settle(tester);
    await tester.tap(find.text('Detectar automaticamente').last);
    await settle(tester);
    expect(setting(AppSettingKeys.voiceLanguage), 'auto');

    await tester.tap(key('voice-mic'));
    await settle(tester);
    await tester.tap(find.text('Microfone interno').last);
    await settle(tester);
    expect(setting(AppSettingKeys.voiceDevice), 'plughw:0,0');

    await tester.tap(key('voice-mic'));
    await settle(tester);
    await tester.tap(find.text('Padrão do sistema').last);
    await settle(tester);
    expect(setting(AppSettingKeys.voiceDevice), isNull);
  });

  testWidgets('R7: Remover modelo asks, with the focus on Manter modelo; Esc '
      'keeps', (tester) async {
    store.install(VoiceModel.quality);
    await pump(tester);
    await tester.tap(key('voice-remove'));
    await settle(tester);
    expect(find.text('Remover o modelo de voz?'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(key('voice-remove-keep')).autofocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(store.isInstalled(VoiceModel.quality), isTrue);

    await tester.tap(key('voice-remove'));
    await settle(tester);
    await tester.tap(key('voice-remove-confirm'));
    await settle(tester, until: () => !store.isInstalled(VoiceModel.quality));
    expect(status(tester), 'Não instalado');
    expect(key('voice-settings-download'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('R10: during a download it shows the percentage and Ver '
      'progresso', (tester) async {
    await pump(tester);
    unawaited(c.read(voiceModelsProvider.notifier).start(background: true));
    await settle(tester, until: () => store.progress != null);
    store.progress!(47, 100);
    await settle(tester);
    expect(status(tester), 'Baixando · 47%');
    expect(key('voice-see-progress'), findsOneWidget);
    await tester.tap(key('voice-see-progress'));
    await settle(tester);
    expect(find.text('Baixando o modelo de voz'), findsOneWidget);
    store.token!.cancel();
    await settle(tester);
  });
}
