import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/update/installer.dart';
import 'package:promptorium/core/update/update_check.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/splash/splash_painter.dart';
import 'package:promptorium/features/splash/splash_stage.dart';
import 'package:promptorium/ui/shell/about_dialog.dart';
import 'package:promptorium/ui/shell/about_update_card.dart';
import 'package:promptorium/ui/shell/shortcut_sheet.dart';
import 'package:promptorium/ui/shell/update_flow.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';

import '../helpers/test_db.dart';
import 'app_shell_test.dart' show pumpShell;

const _about = ValueKey('about-dialog');
const _card = ValueKey('about-update-card');
const _checkNow = ValueKey('about-check-now');
const _updateNow = ValueKey('about-update-now');
const _close = ValueKey('about-close');
const _closeConfirm = ValueKey('about-close-confirm');
const _progress = ValueKey('about-download-progress');
const _upToDate = 'Você está na versão mais recente';
const _noResponse = 'Não foi possível verificar atualizações';

const _changelog = '''
# Changelog

## [0.8.0] - 2026-11-03

### Funcionalidades

- **specs:** Cabeçalho da spec com ações por estado (058194b)

### Correções

- **shell:** Conserta o foco (2480123)

### Documentação

- **specs:** Documentação da spec (20c0dfa)

## [0.7.0] - 2026-10-20

### Correções

- Da versão anterior (b5750b3)

## [0.6.0] - 2026-10-01

### Testes

- Só testes (d353a10)
''';

final _update = AvailableUpdate(
  version: '9.0.0',
  url: 'https://x/r',
  notes:
      '## [9.0.0] - 2026-11-05\n\n### Correções\n\n'
      '- **ui:** Corrige o bug X (abcdef0)\n\n### Testes\n\n- Fora (1234567)\n',
  publishedAt: DateTime(2026, 11, 5, 12),
  assets: const [
    ReleaseAsset(
      name: 'p.tar.gz',
      url: 'https://github.com/a/p.tar.gz',
      size: 40000000,
    ),
    ReleaseAsset(
      name: 'p.deb',
      url: 'https://github.com/a/p.deb',
      size: 38000000,
    ),
  ],
);

/// Reads the asset outside the fake clock so the dialog finds it cached.
Future<void> _preloadChangelog(WidgetTester tester) async {
  await tester.runAsync(() => rootBundle.loadString('CHANGELOG.md'));
}

/// The real asset, through the app shell.
Future<void> _expectAbout(WidgetTester tester) async {
  // The provider's future resolves outside the fake clock: wait for it.
  for (
    var i = 0;
    i < 100 && find.byType(MarkdownBody).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(find.byKey(_about), findsOneWidget);
  expect(find.byKey(const ValueKey('about-version')), findsOneWidget);
  expect(find.byKey(const ValueKey('about-repo')), findsOneWidget);
  expect(find.textContaining(RegExp(r'^Novidades da ')), findsOneWidget);
  final md = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
  expect(md.data, isNot(contains('Todas as mudanças relevantes')));
}

Future<void> _f1(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.f1);
  await tester.pumpAndSettle();
}

Future<void> _esc(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void _size(WidgetTester tester, [Size size = const Size(1440, 900)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens Sobre on a real route with [overrides], with the fixture [changelog]
/// of version 0.8.0 (null when they bring their own).
Future<void> _open(
  WidgetTester tester, {
  List<Override> overrides = const [],
  String? changelog = _changelog,
  String version = '0.8.0',
  ThemeData? theme,
  Size size = const Size(1440, 900),
}) async {
  _size(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (changelog != null)
          changelogProvider.overrideWith((ref) async => changelog),
        appVersionProvider.overrideWith((ref) async => version),
        ...overrides,
      ],
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => showAboutPromptorium(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

Override _withUpdate([AvailableUpdate? update]) =>
    updateCheckerProvider.overrideWith(() => _FixedChecker(update ?? _update));

Override _withResult(UpdateCheckOutcome outcome, [DateTime? at]) =>
    lastCheckProvider.overrideWithValue(
      UpdateCheckResult(outcome, at ?? DateTime.now()),
    );

Override _withState(UpdateFlowState state) =>
    updateFlowProvider.overrideWith(() => _FixedFlow(state));

Override _withSessions(int alive, {int dead = 0}) =>
    sessionManagerProvider.overrideWith(() => _FakeSessions(alive, dead));

String _newsMarkdown(WidgetTester tester) =>
    tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data;

Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  group('opening', () {
    testWidgets('F1 opens the dialog with version, repository and the last '
        'news, and F1 closes it', (tester) async {
      await pumpShell(tester);
      await _preloadChangelog(tester);
      await _f1(tester);
      await _expectAbout(tester);
      await _f1(tester);
      expect(find.byKey(_about), findsNothing);
    });

    testWidgets('the palette item "Sobre" opens the dialog', (tester) async {
      await pumpShell(tester);
      await _preloadChangelog(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sobre');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sobre'));
      await tester.pumpAndSettle();
      await _expectAbout(tester);
    });

    testWidgets('the "Sobre" button of Configurações opens the dialog', (
      tester,
    ) async {
      await pumpShell(tester);
      await _preloadChangelog(tester);
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atualizações').first);
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('open-about'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await _expectAbout(tester);
    });

    test('the shortcut sheet lists Sobre with F1', () {
      final entries = [for (final g in shortcutGroups) ...g.entries];
      expect(entries.any((e) => e.label == 'Sobre' && e.keys == 'F1'), isTrue);
    });

    testWidgets('F1 opens the dialog while a text field has focus', (
      tester,
    ) async {
      await pumpShell(tester);
      await _preloadChangelog(tester);
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('settings-search'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );
      await _f1(tester);
      await _expectAbout(tester);
    });

    testWidgets('F1 with the dialog open closes it and never stacks a second '
        'one', (tester) async {
      await pumpShell(tester);
      await _preloadChangelog(tester);
      await _f1(tester);
      await _expectAbout(tester);
      expect(find.byType(Dialog), findsOneWidget);
      await _f1(tester);
      expect(find.byKey(_about), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      // Closed for real: the next F1 opens exactly one dialog again.
      await _f1(tester);
      expect(find.byKey(_about), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      await _f1(tester);
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('R1, R4 · layout and identity', () {
    testWidgets('two columns in one 820×560 window, the close button at the '
        'top right', (tester) async {
      await _open(tester);
      final window = tester.getRect(
        find
            .descendant(of: find.byKey(_about), matching: find.byType(Stack))
            .first,
      );
      expect(window.size, const Size(820, 560));
      final identity = tester.getRect(
        find.byKey(const ValueKey('about-identity')),
      );
      expect(identity.width, 300);
      expect(identity.left, window.left);
      expect(
        tester.getRect(find.byKey(_card)).left,
        greaterThan(identity.right),
      );
      final close = tester.getRect(find.byKey(_close));
      expect(close.right, greaterThan(window.right - 40));
      expect(close.top, lessThan(window.top + 30));
    });

    testWidgets('name, phrase, version with platform and the links', (
      tester,
    ) async {
      final fake = _FakeInstaller(Future.value());
      await _open(
        tester,
        overrides: [updateInstallerProvider.overrideWithValue(fake)],
      );
      expect(find.text('Promptorium'), findsOneWidget);
      expect(
        find.text('o laboratório de onde operam seus agentes'),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('about-version'))).data,
        'v0.8.0 · Linux',
      );
      await tester.tap(find.byKey(const ValueKey('about-repo')));
      await tester.tap(find.byKey(const ValueKey('about-history')));
      expect(fake.opened, [repositoryUrl, changelogUrl]);
    });
  });

  group('R2, R3 · animation', () {
    int tickers() => SchedulerBinding.instance.transientCallbackCount;

    SplashTimeline timeline(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(SplashStage),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as SplashPainter)
            .timeline();

    tearDown(() => AppMotion.enabled = false);

    testWidgets('plays the intro, the buttons answer during it, and the logo '
        'goes on in the calm rhythm (SPEC-066 R2)', (tester) async {
      AppMotion.enabled = true;
      _CheckingUpdateChecker.forces.clear();
      _size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            changelogProvider.overrideWith((ref) async => _changelog),
            updateCheckerProvider.overrideWith(_CheckingUpdateChecker.new),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AboutPromptoriumDialog()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<SplashStage>(find.byType(SplashStage)).effectiveAmbient,
        SplashAmbient.calm,
      );
      expect(tickers(), greaterThan(0));
      expect(timeline(tester).links, 0);

      await tester.tap(find.byKey(_checkNow));
      await tester.pump();
      expect(_CheckingUpdateChecker.forces, [true]);
      expect(find.text('Versão 9.1.0 disponível'), findsOneWidget);

      await tester.pump(SplashTimeline.introDuration);
      await tester.pump(const Duration(seconds: 3));
      expect(tickers(), greaterThan(0));
      final tl = timeline(tester);
      expect(tl.links, 1);
      expect(tl.bubbles(), isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tickers(), 0);
    });

    testWidgets('closing during the intro stops the ticker and each opening '
        'starts over', (tester) async {
      await _open(tester);
      AppMotion.enabled = true;
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(timeline(tester).links, 0);
      expect(tickers(), greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byType(SplashStage), findsNothing);
      expect(tickers(), 0);
    });

    testWidgets('with animations off the mark is in its final state, without '
        'bubbles, and no ticker runs', (tester) async {
      await tester.pumpWidget(const SizedBox());
      AppMotion.enabled = true;
      _size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            changelogProvider.overrideWith((ref) async => _changelog),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(1440, 900),
                disableAnimations: true,
              ),
              child: Scaffold(body: AboutPromptoriumDialog()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tickers(), 0);
      final tl = timeline(tester);
      expect(tl.stageOpacity, 1);
      expect(tl.links, 1);
      expect(tl.bubble(0).opacity, 0);
    });
  });

  group('SPEC-066 · the logo', () {
    const logo = ValueKey('about-logo');
    tearDown(() => AppMotion.enabled = false);

    SplashTimeline timeline(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(SplashStage),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as SplashPainter)
            .timeline();

    Future<void> pumpAbout(WidgetTester tester, {bool reduced = false}) async {
      AppMotion.enabled = true;
      _size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            changelogProvider.overrideWith((ref) async => _changelog),
            appVersionProvider.overrideWith((ref) async => '0.8.0'),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(1440, 900),
                disableAnimations: reduced,
              ),
              child: const Scaffold(body: AboutPromptoriumDialog()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(SplashTimeline.introDuration);
      await tester.pump();
    }

    testWidgets('R4 · the mouse over the logo agitates it, and leaving calms '
        'it down', (tester) async {
      await pumpAbout(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(logo)));
      await tester.pump();
      expect(
        tester.widget<SplashStage>(find.byType(SplashStage)).excited,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(timeline(tester).excite, 1);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(
        tester.widget<SplashStage>(find.byType(SplashStage)).excited,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R5 · a click plays the intro again', (tester) async {
      await pumpAbout(tester);
      expect(timeline(tester).outline, 1);
      await tester.tap(find.byKey(logo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(timeline(tester).outline, lessThan(1));
      expect(timeline(tester).stageOpacity, 1);
      await tester.pumpWidget(const SizedBox());
    });

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets('R5, R6 · ${key.keyLabel} with the focus on the logo plays '
          'the intro', (tester) async {
        await pumpAbout(tester);
        Focus.of(tester.element(find.byKey(const ValueKey('about-logo-ring'))))
            .requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(timeline(tester).outline, lessThan(1));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('R6 · the reader hears a button that plays the intro', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpAbout(tester);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('about-logo-ring'))),
        matchesSemantics(
          label: 'Ícone do Promptorium',
          hint: 'Tocar a abertura de novo',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });

    testWidgets('R6 · Tab reaches the logo after the card and before the '
        'links', (tester) async {
      await pumpAbout(tester);
      String? focused() {
        final focus = FocusManager.instance.primaryFocus?.context;
        String? name;
        focus?.visitAncestorElements((e) {
          final k = e.widget.key;
          if (k is ValueKey<String> && k.value.startsWith('about-')) {
            name = k.value;
            return false;
          }
          return true;
        });
        return name;
      }

      // The focus starts on the action of the card (SPEC-038 R11).
      expect(focused(), 'about-check-now');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(), 'about-logo');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(), 'about-repo');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R8 · with animations off the logo is no button', (
      tester,
    ) async {
      await pumpAbout(tester, reduced: true);
      expect(find.byKey(logo), findsNothing);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });
  });

  group('R5, R6 · news', () {
    testWidgets('without an update, the section of the installed version', (
      tester,
    ) async {
      await _open(tester, version: '0.7.0');
      expect(find.text('Novidades da 0.7.0'), findsOneWidget);
      expect(find.text('20/10/2026'), findsOneWidget);
      expect(_newsMarkdown(tester), contains('Da versão anterior'));
    });

    testWidgets('without that section, the first one of the file', (
      tester,
    ) async {
      await _open(tester, version: '0.9.9');
      expect(find.text('Novidades da 0.8.0'), findsOneWidget);
    });

    testWidgets('only what matters, without hashes and scopes', (tester) async {
      await _open(tester);
      final md = _newsMarkdown(tester);
      expect(md, contains('Funcionalidades'));
      expect(md, contains('Correções'));
      expect(md, contains('Cabeçalho da spec com ações por estado'));
      expect(md, isNot(contains('Documentação')));
      expect(md, isNot(contains('058194b')));
      expect(md, isNot(contains('**specs:**')));
    });

    testWidgets('with an update, the notes of the new version go through the '
        'same filter', (tester) async {
      await _open(tester, overrides: [_withUpdate()]);
      expect(find.text('Novidades da 9.0.0'), findsOneWidget);
      expect(find.text('05/11/2026'), findsOneWidget);
      final md = _newsMarkdown(tester);
      expect(md, contains('Corrige o bug X'));
      expect(md, isNot(contains('Fora')));
      expect(md, isNot(contains('Cabeçalho da spec')));
    });

    testWidgets('D3 · notes outside the format show whole', (tester) async {
      const update = AvailableUpdate(
        version: '9.0.0',
        url: 'https://x/r',
        notes: 'Corrige o bug X\n\n## O que mudou\n\n- Algo',
      );
      await _open(tester, overrides: [_withUpdate(update)]);
      expect(_newsMarkdown(tester), update.notes);
      expect(find.byKey(const ValueKey('about-news-date')), findsNothing);
    });

    testWidgets('a version with neither group says so and keeps the link', (
      tester,
    ) async {
      await _open(tester, version: '0.6.0');
      expect(find.text('Novidades da 0.6.0'), findsOneWidget);
      expect(
        find.text('Sem novidades para mostrar nesta versão.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('about-history')), findsOneWidget);
    });

    testWidgets('an update without notes says so too', (tester) async {
      await _open(
        tester,
        overrides: [
          _withUpdate(const AvailableUpdate(version: '9.0.0', url: 'u')),
        ],
      );
      expect(
        find.text('Sem novidades para mostrar nesta versão.'),
        findsOneWidget,
      );
    });

    testWidgets('without the changelog the screen says so', (tester) async {
      await _open(
        tester,
        changelog: null,
        overrides: [
          changelogProvider.overrideWith((ref) => Future.error('sem asset')),
        ],
      );
      await tester.pump();
      expect(find.text('Novidades indisponíveis.'), findsOneWidget);
    });

    testWidgets('a text without any version section counts as unavailable', (
      tester,
    ) async {
      await _open(tester, changelog: '# Changelog\n\nNada aqui.');
      expect(find.text('Novidades indisponíveis.'), findsOneWidget);
    });

    testWidgets('the news scroll by themselves, with the network failing, and '
        'the card stays where it is', (tester) async {
      var fetches = 0;
      final long = [
        '## [0.8.0] - 2026-11-03',
        '### Funcionalidades',
        for (var i = 0; i < 60; i++) '- Item $i (abcdef0)',
      ].join('\n\n');
      await _open(
        tester,
        changelog: long,
        overrides: [
          releaseFetcherProvider.overrideWithValue((_) async {
            fetches++;
            throw const SocketException('sem rede');
          }),
        ],
      );
      // Opening never queries by itself.
      expect(fetches, 0);
      final card = tester.getRect(find.byKey(_card));
      final scroll = find.byKey(const ValueKey('about-changelog'));
      final view = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)),
      );
      expect(view.position.maxScrollExtent, greaterThan(0));
      await tester.drag(scroll, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(view.position.pixels, greaterThan(0));
      expect(tester.getRect(find.byKey(_card)), card);
    });
  });

  group('R7 · card', () {
    final progress = const DownloadProgress(
      received: 24000000,
      total: 38000000,
    );
    final states = <String, (UpdateFlowState, List<String>, List<Key>)>{
      'Em dia': (
        UpdateUpToDate(DateTime.now().copyWith(hour: 14, minute: 32)),
        [_upToDate, 'Verificado hoje às 14:32'],
        [_checkNow],
      ),
      'Verificando': (
        const UpdateChecking(),
        ['Consultando as versões publicadas'],
        [_checkNow],
      ),
      'Disponível': (
        UpdateAvailable(_update),
        [
          'Versão 9.0.0 disponível',
          'Publicada em 05/11/2026 · 38 MB. Baixa, instala e reinicia o app.',
        ],
        [_updateNow],
      ),
      'Confirmar sessões': (
        UpdateConfirmSessions(_update, 2),
        [
          '2 sessões em execução serão encerradas',
          'O app reinicia para instalar a 9.0.0.',
        ],
        [
          const ValueKey<String>('about-update-later'),
          const ValueKey<String>('about-update-anyway'),
        ],
      ),
      'Baixando': (
        UpdateDownloading(_update, progress),
        ['Baixando a 9.0.0', '63% · 24 de 38 MB'],
        [const ValueKey<String>('about-download-cancel'), _progress],
      ),
      'Instalando': (
        UpdateInstalling(_update),
        ['Instalando e reiniciando…', 'O sistema pode pedir sua senha.'],
        [],
      ),
      'Falhou': (
        UpdateFailed(_update, 'O download parou no meio.'),
        ['Não foi possível atualizar', 'O download parou no meio.'],
        [
          const ValueKey<String>('about-open-release'),
          const ValueKey<String>('about-update-retry'),
        ],
      ),
      'Sem resposta': (
        const UpdateNoResponse(),
        [
          _noResponse,
          'O GitHub não respondeu. Veja sua conexão e tente de novo.',
        ],
        [const ValueKey<String>('about-check-retry')],
      ),
      'Nunca verificado (D7)': (
        const UpdateNeverChecked(),
        ['Ainda não verificado'],
        [_checkNow],
      ),
    };

    for (final MapEntry(key: name, value: (state, texts, keys))
        in states.entries) {
      testWidgets('$name shows its text and its actions, at the same height', (
        tester,
      ) async {
        await _open(
          tester,
          overrides: [
            _withUpdate(),
            updatePackageProvider.overrideWith(
              (ref) async => _update.assets[1],
            ),
            _withState(state),
          ],
        );
        await tester.pump();
        final card = find.byKey(_card);
        for (final t in texts) {
          expect(
            find.descendant(of: card, matching: find.text(t)),
            findsOneWidget,
          );
        }
        for (final k in keys) {
          expect(
            find.descendant(of: card, matching: find.byKey(k)),
            findsOneWidget,
          );
        }
        expect(
          find
                  .descendant(of: card, matching: find.byType(Icon))
                  .evaluate()
                  .isNotEmpty ||
              find
                  .descendant(
                    of: card,
                    matching: find.byType(ProgressIndicator),
                  )
                  .evaluate()
                  .isNotEmpty,
          isTrue,
        );
        expect(tester.getSize(card).height, updateCardHeight);
      });
    }

    testWidgets('the news do not move between states', (tester) async {
      Future<Rect> newsAt(UpdateFlowState state) async {
        await tester.pumpWidget(const SizedBox());
        await _open(tester, overrides: [_withUpdate(), _withState(state)]);
        return tester.getRect(find.byKey(const ValueKey('about-news-title')));
      }

      final at = await newsAt(UpdateAvailable(_update));
      expect(await newsAt(UpdateConfirmSessions(_update, 2)), at);
      expect(await newsAt(UpdateDownloading(_update)), at);
      expect(await newsAt(UpdateFailed(_update, 'motivo')), at);
    });

    for (final (state, actions) in [
      (
        UpdateConfirmSessions(_update, 2),
        ['about-update-later', 'about-update-anyway'],
      ),
      (
        UpdateFailed(_update, 'motivo'),
        ['about-open-release', 'about-update-retry'],
      ),
    ]) {
      testWidgets('two actions sit in a row below the text '
          '(${state.runtimeType})', (tester) async {
        await _open(tester, overrides: [_withUpdate(), _withState(state)]);
        final status = tester.getRect(
          find.byKey(const ValueKey('about-update-status')),
        );
        final a = tester.getRect(find.byKey(ValueKey(actions[0])));
        final b = tester.getRect(find.byKey(ValueKey(actions[1])));
        expect(a.top, greaterThanOrEqualTo(status.bottom));
        expect(a.top, b.top);
        expect(a.right, lessThan(b.left));
      });
    }

    testWidgets('one session in the singular', (tester) async {
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          _withState(UpdateConfirmSessions(_update, 1)),
        ],
      );
      expect(find.text('1 sessão em execução será encerrada'), findsOneWidget);
    });

    testWidgets('an unknown total shows what came and no percent', (
      tester,
    ) async {
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          _withState(
            UpdateDownloading(
              _update,
              const DownloadProgress(received: 5000000),
            ),
          ),
        ],
      );
      expect(find.text('5 MB baixados'), findsOneWidget);
    });

    testWidgets('an available update without facts keeps the hint', (
      tester,
    ) async {
      await _open(
        tester,
        overrides: [
          _withUpdate(const AvailableUpdate(version: '9.0.0', url: 'u')),
        ],
      );
      expect(find.text('Baixa, instala e reinicia o app.'), findsOneWidget);
    });

    testWidgets('"Em dia" reads the last query, with the day when it is old', (
      tester,
    ) async {
      await _open(
        tester,
        overrides: [
          _withResult(UpdateCheckOutcome.upToDate, DateTime(2026, 1, 2, 9, 5)),
        ],
      );
      expect(find.text(_upToDate), findsOneWidget);
      expect(find.text('Verificado em 02/01/2026 às 09:05'), findsOneWidget);
    });

    testWidgets('D7 · without any query on record the card claims nothing', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text(_upToDate), findsNothing);
      expect(find.text('Ainda não verificado'), findsOneWidget);
      expect(find.byKey(_checkNow), findsOneWidget);
    });

    testWidgets('D7 · a found update lost in a restart is not "em dia"', (
      tester,
    ) async {
      await _open(tester, overrides: [_withResult(UpdateCheckOutcome.found)]);
      expect(find.text(_upToDate), findsNothing);
      expect(find.text('Ainda não verificado'), findsOneWidget);
    });

    testWidgets('"Verificar agora" calls check(force: true) and the result '
        'shows up in the card', (tester) async {
      _CheckingUpdateChecker.forces.clear();
      await _open(
        tester,
        overrides: [
          updateCheckerProvider.overrideWith(_CheckingUpdateChecker.new),
        ],
      );
      expect(find.text('Atualizar agora'), findsNothing);
      await tester.tap(find.byKey(_checkNow));
      await tester.pumpAndSettle();
      expect(_CheckingUpdateChecker.forces, [true]);
      expect(find.text('Novidades da 9.1.0'), findsOneWidget);
      expect(find.text('Atualizar agora'), findsOneWidget);
    });

    testWidgets('while checking, the button is disabled', (tester) async {
      final gate = Completer<Map<String, dynamic>?>();
      await _open(
        tester,
        overrides: [
          databaseOverride(memoryDatabase()),
          releaseFetcherProvider.overrideWithValue((_) => gate.future),
        ],
      );
      await tester.tap(find.byKey(_checkNow));
      await tester.pump();
      await _settleIo(tester);
      expect(find.text('Verificando…'), findsNWidgets(2));
      gate.complete({'tag_name': 'v0.8.0'});
      await _settleIo(tester);
      expect(find.text(_upToDate), findsOneWidget);
    });
  });

  group('R8 · updating inside the card', () {
    testWidgets('"Atualizar agora" downloads in the card, with no other '
        'window, and nothing is downloaded before the click', (tester) async {
      final gate = Completer<void>();
      final fake = _FakeInstaller(gate.future);
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          updateInstallerProvider.overrideWithValue(fake),
        ],
      );
      expect(fake.downloaded, isEmpty);
      await tester.tap(find.byKey(_updateNow));
      await tester.pump();
      await tester.pump();
      expect(fake.downloaded, ['p.deb']);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(_progress), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Instalando e reiniciando…'), findsOneWidget);
      expect(fake.calls, ['install', 'closeDatabase', 'restart']);
    });

    testWidgets('with sessions running, the card asks before downloading', (
      tester,
    ) async {
      final fake = _FakeInstaller(Completer<void>().future);
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          _withSessions(2, dead: 1),
          updateInstallerProvider.overrideWithValue(fake),
        ],
      );
      // D6 · only when the click comes.
      expect(find.textContaining('sessões em execução'), findsNothing);
      await tester.tap(find.byKey(_updateNow));
      await tester.pumpAndSettle();
      expect(
        find.text('2 sessões em execução serão encerradas'),
        findsOneWidget,
      );
      expect(fake.downloaded, isEmpty);
      expect(find.byType(Dialog), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('about-update-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(_updateNow), findsOneWidget);
      expect(fake.downloaded, isEmpty);

      await tester.tap(find.byKey(_updateNow));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('about-update-anyway')));
      await tester.pump();
      await tester.pump();
      expect(fake.downloaded, ['p.deb']);
      expect(find.byKey(_progress), findsOneWidget);
    });

    testWidgets('"Cancelar" stops the download and goes back to Disponível', (
      tester,
    ) async {
      final fake = _FakeInstaller(Completer<void>().future);
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          updateInstallerProvider.overrideWithValue(fake),
        ],
      );
      await tester.tap(find.byKey(_updateNow));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('about-download-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Versão 9.0.0 disponível'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    testWidgets('without a compatible asset the card shows the error', (
      tester,
    ) async {
      final fake = _FakeInstaller(Future.value());
      await _open(
        tester,
        overrides: [
          _withUpdate(const AvailableUpdate(version: '9.0.0', url: 'u')),
          updateInstallerProvider.overrideWithValue(fake),
        ],
      );
      await tester.tap(find.byKey(_updateNow));
      await tester.pumpAndSettle();
      expect(
        find.text('Nenhum pacote compatível com o Linux.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('about-open-release')), findsOneWidget);
      expect(fake.downloaded, isEmpty);
    });

    final failures = <String, (_FakeInstaller Function(), String)>{
      'network error': (
        () =>
            _FakeInstaller(Future.value())
              ..downloadError = const SocketException('sem rede'),
        'O download parou no meio. Sua versão continua a mesma.',
      ),
      'no pkexec': (
        () => _FakeInstaller(Future.value())
          ..installError = const FileSystemException('pkexec não encontrado'),
        'pkexec não encontrado',
      ),
      'no write permission': (
        () => _FakeInstaller(
          Future.value(),
        )..installError = const FileSystemException('Sem permissão de escrita'),
        'Sem permissão de escrita',
      ),
      'password refused': (
        () => _FakeInstaller(Future.value())
          ..installError = const ProcessException('pkexec', [], 'negado', 126),
        'A instalação não terminou. Sua versão continua a mesma.',
      ),
    };
    for (final MapEntry(key: name, value: (build, reason))
        in failures.entries) {
      testWidgets('$name shows the reason, "Tentar de novo" and "Abrir página '
          'da release"', (tester) async {
        final fake = build();
        await _open(
          tester,
          overrides: [
            _withUpdate(),
            updateInstallerProvider.overrideWithValue(fake),
          ],
        );
        await tester.tap(find.byKey(_updateNow));
        await tester.pumpAndSettle();
        expect(find.text('Não foi possível atualizar'), findsOneWidget);
        expect(find.text(reason), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('about-open-release')));
        await tester.pump();
        expect(fake.opened, ['https://x/r']);
        expect(fake.calls, isNot(contains('restart')));

        fake
          ..downloadError = null
          ..installError = null;
        await tester.tap(find.byKey(const ValueKey('about-update-retry')));
        await tester.pumpAndSettle();
        expect(fake.downloaded, hasLength(2));
        expect(fake.calls, contains('restart'));
      });
    }

    testWidgets('a failure does not outlive the screen', (tester) async {
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          updateInstallerProvider.overrideWithValue(
            _FakeInstaller(Future.value())
              ..downloadError = const SocketException('sem rede'),
          ),
        ],
      );
      await tester.tap(find.byKey(_updateNow));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível atualizar'), findsOneWidget);
      await _esc(tester);
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(_updateNow), findsOneWidget);
    });
  });

  group('R9 · closing', () {
    Future<_FakeInstaller> downloading(WidgetTester tester) async {
      final fake = _FakeInstaller(Completer<void>().future);
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          updateInstallerProvider.overrideWithValue(fake),
        ],
      );
      await tester.tap(find.byKey(_updateNow));
      await tester.pump();
      await tester.pump();
      return fake;
    }

    for (final (name, close) in <(String, Future<void> Function(WidgetTester))>[
      (
        'Fechar',
        (t) async {
          await t.tap(find.byKey(_close));
          await t.pumpAndSettle();
        },
      ),
      ('Esc', _esc),
      ('F1', _f1),
    ]) {
      testWidgets('$name during the download asks before closing, in the same '
          'window', (tester) async {
        await downloading(tester);
        await close(tester);
        expect(find.byKey(_about), findsOneWidget);
        expect(find.byKey(_closeConfirm), findsOneWidget);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Continuar baixando'), findsOneWidget);
        // The main action gets the focus.
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'about-keep-downloading',
        );
      });
    }

    testWidgets('"Continuar baixando" keeps the download and the screen', (
      tester,
    ) async {
      await downloading(tester);
      await _esc(tester);
      await tester.tap(find.byKey(const ValueKey('about-close-keep')));
      await tester.pumpAndSettle();
      expect(find.byKey(_closeConfirm), findsNothing);
      expect(find.byKey(_progress), findsOneWidget);
    });

    testWidgets('Esc on the question also keeps downloading', (tester) async {
      await downloading(tester);
      await _esc(tester);
      await _esc(tester);
      expect(find.byKey(_closeConfirm), findsNothing);
      expect(find.byKey(_about), findsOneWidget);
    });

    testWidgets('"Cancelar e fechar" stops the download and closes', (
      tester,
    ) async {
      final fake = await downloading(tester);
      await _esc(tester);
      await tester.tap(find.byKey(const ValueKey('about-close-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(_about), findsNothing);
      expect(fake.calls, isEmpty);
    });

    testWidgets('the question goes away if the download ends meanwhile', (
      tester,
    ) async {
      final gate = Completer<void>();
      final fake = _FakeInstaller(gate.future);
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          updateInstallerProvider.overrideWithValue(fake),
        ],
      );
      await tester.tap(find.byKey(_updateNow));
      await tester.pump();
      await tester.pump();
      await _esc(tester);
      expect(find.byKey(_closeConfirm), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_closeConfirm), findsNothing);
      expect(find.text('Instalando e reiniciando…'), findsOneWidget);
    });

    testWidgets('while installing the screen does not close', (tester) async {
      await _open(
        tester,
        overrides: [_withUpdate(), _withState(UpdateInstalling(_update))],
      );
      final close = tester.widget<IconButton>(find.byKey(_close));
      expect(close.onPressed, isNull);
      expect(close.tooltip, 'Aguarde a instalação terminar');
      await _esc(tester);
      await _f1(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(_about), findsOneWidget);
      expect(find.byKey(_closeConfirm), findsNothing);
    });

    final others = <String, UpdateFlowState>{
      'Em dia': UpdateUpToDate(DateTime(2026)),
      'Disponível': UpdateAvailable(_update),
      'Confirmar sessões': UpdateConfirmSessions(_update, 2),
      'Falhou': UpdateFailed(_update, 'motivo'),
      'Sem resposta': const UpdateNoResponse(),
    };
    for (final MapEntry(key: name, value: state) in others.entries) {
      testWidgets('in $name the screen closes at once', (tester) async {
        await _open(tester, overrides: [_withState(state)]);
        await _esc(tester);
        expect(find.byKey(_about), findsNothing);
      });
    }

    testWidgets('SPEC-066 R7 · the logo stops while the confirmation is over '
        'the screen', (tester) async {
      await downloading(tester);
      SplashStage stage() =>
          tester.widget<SplashStage>(find.byType(SplashStage));
      expect(stage().paused, isFalse);
      await _esc(tester);
      expect(find.byKey(_closeConfirm), findsOneWidget);
      expect(stage().paused, isTrue);
      await tester.tap(find.text('Continuar baixando'));
      await tester.pumpAndSettle();
      expect(stage().paused, isFalse);
    });
  });

  group('R10 · a query that fails', () {
    Override failingThenUpToDate(List<Object> answers) {
      final queue = [...answers];
      return releaseFetcherProvider.overrideWithValue((_) async {
        final a = queue.removeAt(0);
        if (a is Exception) throw a;
        return a as Map<String, dynamic>;
      });
    }

    testWidgets('goes to Sem resposta and "Tentar de novo" asks again', (
      tester,
    ) async {
      await _open(
        tester,
        overrides: [
          databaseOverride(memoryDatabase()),
          failingThenUpToDate([
            const SocketException('sem rede'),
            {'tag_name': 'v0.8.0'},
          ]),
        ],
      );
      await tester.tap(find.byKey(_checkNow));
      await tester.pump();
      await _settleIo(tester);
      expect(find.text(_noResponse), findsOneWidget);
      expect(find.text(_upToDate), findsNothing);

      await tester.tap(find.byKey(const ValueKey('about-check-retry')));
      await tester.pump();
      await _settleIo(tester);
      expect(find.text(_upToDate), findsOneWidget);
      expect(find.textContaining('Verificado hoje às'), findsOneWidget);
    });

    testWidgets('a failure on record opens in Sem resposta', (tester) async {
      await _open(tester, overrides: [_withResult(UpdateCheckOutcome.failed)]);
      expect(find.text(_noResponse), findsOneWidget);
    });

    testWidgets('an update already found stays after a query that failed', (
      tester,
    ) async {
      await _open(
        tester,
        overrides: [_withUpdate(), _withResult(UpdateCheckOutcome.failed)],
      );
      expect(find.text('Versão 9.0.0 disponível'), findsOneWidget);
      expect(find.text(_noResponse), findsNothing);
    });
  });

  group('R11 · keyboard and screen reader', () {
    FocusNode? focused() => FocusManager.instance.primaryFocus;

    final keys = <String, (Override?, Key)>{
      'Em dia': (_withResult(UpdateCheckOutcome.upToDate), _checkNow),
      'Disponível': (_withUpdate(), _updateNow),
      'Sem resposta': (
        _withResult(UpdateCheckOutcome.failed),
        const ValueKey<String>('about-check-retry'),
      ),
    };
    for (final MapEntry(key: name, value: (override, key)) in keys.entries) {
      testWidgets('the focus starts on the main action ($name)', (
        tester,
      ) async {
        await _open(tester, overrides: [?override]);
        await tester.pump();
        expect(focused()?.debugLabel, 'about-action');
        expect(
          find.descendant(
            of: find.byKey(key),
            matching: find.byWidgetPredicate(
              (w) => w is Focus && w.focusNode == focused(),
            ),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('Enter on the focused action runs it', (tester) async {
      _CheckingUpdateChecker.forces.clear();
      await _open(
        tester,
        overrides: [
          updateCheckerProvider.overrideWith(_CheckingUpdateChecker.new),
        ],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_CheckingUpdateChecker.forces, [true]);
      // The button changed, the focus stayed on the card.
      expect(focused()?.debugLabel, 'about-action');
      expect(find.byKey(_updateNow), findsOneWidget);
    });

    testWidgets('a state without an action keeps the focus on the card, and '
        'the next one gives it back', (tester) async {
      final gate = Completer<Map<String, dynamic>?>();
      await _open(
        tester,
        overrides: [
          databaseOverride(memoryDatabase()),
          releaseFetcherProvider.overrideWithValue((_) => gate.future),
        ],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await _settleIo(tester);
      expect(focused()?.debugLabel, 'about-card');
      // Still inside the dialog: F1 and Esc keep working.
      gate.complete({'tag_name': 'v0.8.0'});
      await _settleIo(tester);
      expect(focused()?.debugLabel, 'about-action');
    });

    testWidgets('a focus elsewhere does not move when the state changes', (
      tester,
    ) async {
      final gate = Completer<Map<String, dynamic>?>();
      await _open(
        tester,
        overrides: [
          databaseOverride(memoryDatabase()),
          releaseFetcherProvider.overrideWithValue((_) => gate.future),
        ],
      );
      await tester.tap(find.byKey(_checkNow));
      await tester.pump();
      await _settleIo(tester);
      final closeNode = Focus.of(tester.element(find.byIcon(Icons.close)));
      closeNode.requestFocus();
      await tester.pump();
      gate.complete({'tag_name': 'v0.8.0'});
      await _settleIo(tester);
      expect(focused(), closeNode);
    });

    testWidgets('the state is announced in a live region, and the percent of '
        'the download is not', (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(
        tester,
        overrides: [
          _withUpdate(),
          _withState(
            UpdateDownloading(
              _update,
              const DownloadProgress(received: 50, total: 100),
            ),
          ),
        ],
      );
      final status = find.byKey(const ValueKey('about-update-status'));
      expect(
        tester.getSemantics(status),
        isSemantics(label: 'Baixando a 9.0.0', isLiveRegion: true),
      );
      semantics.dispose();
    });

    testWidgets('the live region reads the title and the detail', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, overrides: [_withResult(UpdateCheckOutcome.failed)]);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('about-update-status'))),
        isSemantics(
          label:
              '$_noResponse. O GitHub não respondeu. Veja sua conexão e tente '
              'de novo.',
          isLiveRegion: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the mark has its label', (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(tester);
      expect(find.bySemanticsLabel('Ícone do Promptorium'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('R12 · 1100×700', () {
    /// The bundled fonts: the test font makes every letter a wide square.
    Future<void> loadFonts() async {
      for (final (family, files) in [
        (
          'IBM Plex Sans',
          ['Regular', 'Medium', 'SemiBold'].map((w) => 'IBMPlexSans-$w'),
        ),
        ('JetBrains Mono', ['JetBrainsMono-Regular']),
      ]) {
        final loader = FontLoader(family);
        for (final f in files) {
          final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
        }
        await loader.load();
      }
    }

    final states = <UpdateFlowState>[
      UpdateUpToDate(DateTime(2026, 1, 2, 9, 5)),
      const UpdateChecking(),
      const UpdateNoResponse(),
      const UpdateNeverChecked(),
      UpdateAvailable(_update),
      UpdateConfirmSessions(_update, 12),
      UpdateDownloading(
        _update,
        const DownloadProgress(received: 24000000, total: 38000000),
      ),
      UpdateInstalling(_update),
      UpdateFailed(
        _update,
        'O download parou no meio. Sua versão continua a mesma.',
      ),
    ];
    for (final state in states) {
      testWidgets('${state.runtimeType} fits, with no cut label', (
        tester,
      ) async {
        await tester.runAsync(loadFonts);
        await _open(
          tester,
          size: const Size(1100, 700),
          theme: AppTheme.dark(),
          overrides: [
            _withUpdate(),
            updatePackageProvider.overrideWith(
              (ref) async => _update.assets[1],
            ),
            _withState(state),
          ],
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final window = tester.getRect(
          find
              .descendant(of: find.byKey(_about), matching: find.byType(Stack))
              .first,
        );
        expect(window.size, const Size(820, 560));
        expect(const Rect.fromLTWH(0, 0, 1100, 700).intersect(window), window);
        for (final e
            in find
                .descendant(
                  of: find.byKey(_about),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          expect(
            p.didExceedMaxLines,
            isFalse,
            reason: 'cut: ${p.text.toPlainText()}',
          );
        }
      });
    }
  });
}

class _FakeInstaller extends UpdateInstaller {
  // The copy the .deb installs: the update downloads the .deb.
  _FakeInstaller(this.gate) : super(executable: '/opt/promptorium/promptorium');

  final Future<void> gate;
  final downloaded = <String>[];
  final calls = <String>[];
  final opened = <String>[];
  Object? downloadError;
  Object? installError;

  @override
  Future<void> openReleasePage(String url) async => opened.add(url);

  @override
  Future<void> install(File file) async {
    if (installError != null) throw installError!;
    calls.add('install');
  }

  @override
  Future<void> restart() async => calls.add('restart');

  @override
  Future<void> installAndRestart(
    File file, {
    required Future<void> Function() closeDatabase,
  }) => super.installAndRestart(
    file,
    closeDatabase: () async {
      calls.add('closeDatabase');
    },
  );

  @override
  Future<bool> hasPkexec() async => true;

  @override
  Stream<DownloadProgress> download(
    ReleaseAsset asset, {
    List<ReleaseAsset> releaseAssets = const [],
  }) async* {
    downloaded.add(asset.name);
    if (downloadError != null) throw downloadError!;
    yield const DownloadProgress(received: 50, total: 100);
    await gate;
    yield DownloadProgress(received: 100, total: 100, file: File('/tmp/x'));
  }
}

class _FixedChecker extends UpdateChecker {
  _FixedChecker(this.update);

  final AvailableUpdate update;

  @override
  AvailableUpdate? build() => update;
}

class _FixedFlow extends UpdateFlow {
  _FixedFlow(this.fixed);

  final UpdateFlowState fixed;

  @override
  UpdateFlowState build() => fixed;
}

class _FakeSessions extends SessionManager {
  _FakeSessions(this.alive, this.dead);

  final int alive;
  final int dead;

  @override
  SessionManagerState build() => SessionManagerState(
    live: {
      for (var i = 0; i < alive; i++) 'a$i': const LiveSession(),
      for (var i = 0; i < dead; i++) 'd$i': const LiveSession(alive: false),
    },
  );
}

class _CheckingUpdateChecker extends UpdateChecker {
  static final forces = <bool>[];

  @override
  AvailableUpdate? build() => null;

  @override
  Future<AvailableUpdate?> check({
    bool force = false,
    DateTime? now,
    String? version,
  }) async {
    forces.add(force);
    return state = const AvailableUpdate(
      version: '9.1.0',
      url: 'https://x/r',
      notes: 'Nova',
    );
  }
}
