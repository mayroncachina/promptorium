import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/agent_trailer.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/project/widgets/agent_trailer_dialog.dart';
import 'package:promptorium/features/project/widgets/project_config_view.dart';
import 'package:promptorium/features/sessions/agent_names.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart'
    show AmberButton;
import 'package:promptorium/features/sessions/session_manager.dart'
    show markedSessionsProvider;
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';

/// SPEC-048 R1, R6, R7: the Git group of Configuração do projeto, the ⓘ
/// tooltip and the confirmation of turning the marking on.
void main() {
  late Directory tmp;
  late Workspace ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-config-view-');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> insertWorkspace(WidgetTester tester) async {
    final db = memoryDatabase();
    ws = (await tester.runAsync(
      () => db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'promptorium'),
          ),
    ))!;
    await tester.runAsync(db.close);
  }

  /// Real file IO inside a tap: alternate real time and the fake clock.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (done()) return;
    }
    fail('condição não atingida');
  }

  List<Override> overrides({
    GitVersion? git = const GitVersion(2, 43),
    DateTime? since,
    int count = 0,
  }) => [
    agentListProvider.overrideWith((ref, path) async => const []),
    gitVersionProvider.overrideWith((ref) async => git),
    agentMarkInfoProvider.overrideWith(
      (ref, path) async => (since: since, count: count),
    ),
  ];

  Future<ProviderContainer> pumpView(
    WidgetTester tester, {
    List<Override> extra = const [],
    GitVersion? git = const GitVersion(2, 43),
    DateTime? since,
    int count = 0,
  }) async {
    await insertWorkspace(tester);
    await tester.binding.setSurfaceSize(const Size(1000, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        ...overrides(git: git, since: since, count: count),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: ProjectConfigView(workspace: ws)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  String status(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('config-mark-agents-status')))
      .data!;

  testWidgets('Git group: off by default; checking it and saving writes '
      'git: marcar-commits-de-agente (R1)', (tester) async {
    File('${tmp.path}/${ProjectConfig.filePath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('specs: docs/specs\ntestes: make test\n');
    await pumpView(tester);
    expect(find.byKey(const ValueKey('config-git-group')), findsOneWidget);
    expect(find.text('Marcar commits feitos por agentes'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('config-mark-agents')))
          .value,
      isFalse,
    );
    expect(status(tester), 'Desligado');
    expect(
      find.byKey(const ValueKey('config-mark-agents-info')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('config-mark-agents')),
    );
    await tester.tap(find.byKey(const ValueKey('config-mark-agents')));
    await tester.pump();
    expect(status(tester), 'Liga nas próximas sessões, depois de salvar');

    await tester.ensureVisible(find.byKey(const ValueKey('config-save')));
    await tester.tap(find.byKey(const ValueKey('config-save')));
    await pumpUntil(
      tester,
      () =>
          ProjectConfig.loadSync(tmp.path).git.markAgentCommits &&
          status(tester) == 'Ligado · nenhum commit marcado ainda',
    );
    final saved = ProjectConfig.loadSync(tmp.path);
    expect(saved.specsDir, 'docs/specs');
    expect(saved.testCommand, 'make test');
    expect(
      File('${tmp.path}/${ProjectConfig.filePath}').readAsStringSync(),
      contains('git:\n  marcar-commits-de-agente: true\n'),
    );
  });

  testWidgets('Servidor de desenvolvimento: the fields write dev: in the '
      'short and the long form (SPEC-051 R1)', (tester) async {
    File('${tmp.path}/${ProjectConfig.filePath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('specs: docs/specs\n');
    await pumpView(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('config-dev-path')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('config-dev')), 'vite');
    await tester.enterText(
      find.byKey(const ValueKey('config-dev-path')),
      'login',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('config-save')));
    await tester.tap(find.byKey(const ValueKey('config-save')));
    await pumpUntil(tester, () => ProjectConfig.loadSync(tmp.path).dev != null);
    final dev = ProjectConfig.loadSync(tmp.path).dev!;
    expect(dev.command, 'vite');
    expect(dev.readyText, isNull);
    expect(dev.path, '/login');
    expect(ProjectConfig.loadSync(tmp.path).specsDir, 'docs/specs');
  });

  testWidgets('status: since and count of marked commits (R1, R5)', (
    tester,
  ) async {
    await tester.runAsync(
      () => ProjectConfig.save(
        tmp.path,
        const ProjectConfig(git: GitConfig(markAgentCommits: true)),
      ),
    );
    await pumpView(tester, since: DateTime(2026, 11, 8, 10), count: 37);
    expect(status(tester), 'Ligado desde 8 nov · 37 commits marcados');
  });

  testWidgets('status: git older than 2.32 asks for a newer one (R1)', (
    tester,
  ) async {
    await pumpView(tester, git: const GitVersion(2, 30));
    expect(status(tester), 'Precisa do git 2.32 ou mais novo');
  });

  testWidgets('status: off with a live marked session → "Desliga nas '
      'próximas sessões" (R8)', (tester) async {
    final c = await pumpView(tester);
    c.read(markedSessionsProvider.notifier).add('s1', tmp.path);
    await tester.pump();
    expect(status(tester), 'Desliga nas próximas sessões');
    c.read(markedSessionsProvider.notifier).remove('s1');
    await tester.pump();
    expect(status(tester), 'Desligado');
  });

  testWidgets('the ⓘ opens with keyboard focus and shows the example '
      'commit; Esc closes; the pointer opens it too (R1, R7)', (tester) async {
    await pumpView(tester);
    final info = find.byKey(const ValueKey('config-mark-agents-info'));
    await tester.ensureVisible(info);
    await tester.pump();
    expect(find.byKey(const ValueKey('info-tip-card')), findsNothing);

    // Keyboard: focus the checkbox, Tab moves to the ⓘ.
    final box = find.byKey(const ValueKey('config-mark-agents'));
    Focus.of(
      tester.element(
        find.descendant(of: box, matching: find.byType(CustomPaint)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byKey(const ValueKey('info-tip-card')), findsOneWidget);
    expect(find.text('O que muda nos commits'), findsOneWidget);
    expect(find.text(agentTrailerExampleSubject), findsOneWidget);
    expect(
      find.text('Promptorium-Agente: sonnet · SPEC-042 R2'),
      findsOneWidget,
    );
    final line = tester.widget<Text>(
      find.text('Promptorium-Agente: sonnet · SPEC-042 R2'),
    );
    expect(line.style!.color, AppColors.amber);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('info-tip-card')), findsNothing);
    // Enter reopens it while focused.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey('info-tip-card')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));

    // Pointer: rests on the icon, then leaves.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(info));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('info-tip-card')), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('info-tip-card')), findsNothing);
  });

  testWidgets('R6 dialog: explains what changes; "Agora não" keeps the file, '
      '"Ligar marcação" writes it and keeps the other keys', (tester) async {
    await insertWorkspace(tester);
    File('${tmp.path}/${ProjectConfig.filePath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('specs: docs/specs\n');
    bool? result;
    // The dialog's height follows MediaQuery (the view, not the surface).
    tester.view
      ..physicalSize = const Size(1200, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showAgentTrailerDialog(
                  context,
                  workspace: ws,
                ),
                child: const Text('ligar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ligar'));
    await tester.pumpAndSettle();
    expect(find.text('Marcar os commits dos agentes?'), findsOneWidget);
    expect(
      find.text('Vale para promptorium, a partir das próximas sessões.'),
      findsOneWidget,
    );
    expect(
      find.text('Promptorium-Agente: sonnet · SPEC-042 R2'),
      findsOneWidget,
    );
    String all() => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join('\n');
    expect(
      all(),
      contains(
        '.promptorium/config.yml ganha git: '
        'marcar-commits-de-agente: true e entra no próximo commit',
      ),
    );
    expect(all(), contains('Quem clonar com o Promptorium herda a marcação.'));
    expect(all(), contains('Commits antigos não mudam.'));
    expect(all(), contains('nada é instalado em .git/hooks'));

    await tester.tap(find.byKey(const ValueKey('agent-trailer-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(ProjectConfig.loadSync(tmp.path).git.markAgentCommits, isFalse);

    await tester.tap(find.text('ligar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-trailer-enable')));
    await pumpUntil(tester, () => result == true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-trailer-dialog')), findsNothing);
    final saved = ProjectConfig.loadSync(tmp.path);
    expect(saved.git.markAgentCommits, isTrue);
    expect(saved.specsDir, 'docs/specs');
  });

  testWidgets('R6 dialog with an old git: the button is off and says why', (
    tester,
  ) async {
    await insertWorkspace(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(git: const GitVersion(2, 25)),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: AgentTrailerDialog(workspace: ws)),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Precisa do git 2.32 ou mais novo (este é o 2.25.0).'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AmberButton>(
            find.byKey(const ValueKey('agent-trailer-enable')),
          )
          .onTap,
      isNull,
    );
  });

  test('agentMarkStatus covers every state', () {
    expect(
      agentMarkStatus(
        saved: true,
        edited: true,
        gitOk: true,
        count: 1,
        since: DateTime(2026, 1, 3),
      ).text,
      'Ligado desde 3 jan · 1 commit marcado',
    );
    expect(
      agentMarkStatus(saved: true, edited: false, gitOk: true).text,
      'Desliga nas próximas sessões, depois de salvar',
    );
    expect(
      agentMarkStatus(saved: false, edited: false, gitOk: true).text,
      'Desligado',
    );
  });
}
