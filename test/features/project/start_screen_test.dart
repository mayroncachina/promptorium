import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/core/system/worktree_launcher.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/custom_stack.dart';
import 'package:promptorium/features/project/environment_check.dart';
import 'package:promptorium/features/project/project_service.dart';
import 'package:promptorium/features/project/project_templates.dart';
import 'package:promptorium/features/project/widgets/start_screen.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import 'custom_stack_test.dart' show FakeCustomRun, goFiber;
import 'environment_check_test.dart' show FakeProbe;

/// Records "Criar" instead of creating.
class _FakeService extends ProjectService {
  _FakeService(super.ref, this.created);

  final List<String> created;

  @override
  Future<Workspace> createProject({
    required String parent,
    required String name,
    String? remoteUrl,
    ProjectTemplate? template,
    bool plan = true,
    String branch = 'main',
    int customStackCalls = 0,
  }) async {
    created.add(
      '$parent/$name plan=$plan branch=$branch remote=$remoteUrl'
      '${template != null && template.isCustom ? ' stack=${template.label} calls=$customStackCalls' : ''}',
    );
    throw const ProjectException('fake');
  }
}

class StartHarness {
  StartHarness(this.probe);

  final FakeProbe probe;
  final starts = <List<String>>[];
  final opened = <String>[];
  final created = <String>[];
}

Future<StartHarness> pumpStart(
  WidgetTester tester,
  FakeProbe probe, {
  FakeCustomRun? custom,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = StartHarness(probe);
  final db = memoryDatabase();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseOverride(db),
        environmentProbeProvider.overrideWithValue(probe),
        worktreeLauncherProvider.overrideWithValue(
          WorktreeLauncher(
            start: (exe, args, cwd) async => h.starts.add([exe, ...args]),
            which: (exe) async => exe == 'xterm',
          ),
        ),
        processRunnerProvider.overrideWithValue((exe, args) async {
          if (exe == 'xdg-open') h.opened.add(args.single);
          return ProcessResult(0, 0, '', '');
        }),
        directoryPickerProvider.overrideWithValue(
          ({String? initialDirectory}) async => '/srv/outra',
        ),
        customStackRunProvider.overrideWithValue(
          (custom ?? FakeCustomRun([])).call,
        ),
        projectServiceProvider.overrideWith(
          (ref) => _FakeService(ref, h.created),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: StartScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  return h;
}

Future<void> unmountStart(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

Finder key(String k) => find.byKey(ValueKey(k));

String? stateOf(WidgetTester tester, EnvKind kind) =>
    tester.widget<Text>(key('env-${kind.name}-state')).data;

VoidCallback? amberTap(WidgetTester tester) =>
    tester.widget<AmberButton>(key('start-create-plan')).onTap;

VoidCallback? smallTap(WidgetTester tester) =>
    tester.widget<SmallButton>(key('start-create')).onTap;

String? hint(WidgetTester tester, String k) =>
    tester.widget<Semantics>(key(k)).properties.hint;

Future<void> typeName(WidgetTester tester, String name) async {
  await tester.enterText(key('start-name'), name);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('git without a name blocks both buttons with the reason; '
      '"Gravar no git" fixes it (R1, R3, R4, R15)', (tester) async {
    final probe = FakeProbe()
      ..gitItem = const EnvItem(
        EnvKind.git,
        EnvState.blocked,
        title: 'Git: nome e e-mail',
        line: 'O primeiro commit precisa de nome e e-mail.',
        problem: EnvProblem.gitIdentity,
      );
    final h = await pumpStart(tester, probe);
    expect(key('env-panel'), findsOneWidget);
    expect(stateOf(tester, EnvKind.git), 'BLOQUEIA');
    expect(stateOf(tester, EnvKind.claude), 'OK');
    expect(stateOf(tester, EnvKind.folder), 'OK');
    // "Só local": Local, without a hosting item (R20).
    expect(key('env-host'), findsNothing);
    expect(
      tester.widget<Semantics>(key('env-hosting')).properties.label,
      'Hospedagem detectada pelo remoto: Local',
    );

    await typeName(tester, 'loja-da-ana');
    expect(amberTap(tester), isNull);
    expect(smallTap(tester), isNull);
    expect(find.text('Corrija 1 item do ambiente para criar.'), findsOneWidget);
    expect(
      hint(tester, 'start-create-plan-semantics'),
      'Corrija 1 item do ambiente para criar.',
    );
    expect(
      hint(tester, 'start-create-semantics'),
      'Corrija 1 item do ambiente para criar.',
    );
    // The item's semantics carry the word (R15).
    expect(
      tester.widget<Semantics>(key('env-git')).properties.label,
      contains('bloqueia'),
    );
    expect(
      tester.widget<Semantics>(key('env-git')).properties.liveRegion,
      isTrue,
    );

    // Enter in the name does not create either.
    await tester.showKeyboard(key('start-name'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(h.created, isEmpty);

    // The fix: name, e-mail and the commands written below.
    expect(tester.widget<SmallButton>(key('env-git-save')).onTap, isNull);
    await tester.enterText(key('env-git-name'), 'Ana Lima');
    await tester.enterText(key('env-git-email'), 'ana@exemplo.com');
    await tester.pump();
    expect(
      find.textContaining('git config --global user.name "Ana Lima"'),
      findsOneWidget,
    );
    await tester.tap(key('env-git-save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(probe.identities, [('Ana Lima', 'ana@exemplo.com')]);
    expect(stateOf(tester, EnvKind.git), 'OK');
    expect(find.text('Ana Lima · ana@exemplo.com'), findsOneWidget);
    expect(amberTap(tester), isNotNull);
    expect(smallTap(tester), isNotNull);
    expect(hint(tester, 'start-create-plan-semantics'), isNull);
    await unmountStart(tester);
  });

  testWidgets('the starting-point chips and "Gravar no git" keep their '
      'own width, side by side (R1, R16)', (tester) async {
    final probe = FakeProbe()
      ..gitItem = const EnvItem(
        EnvKind.git,
        EnvState.blocked,
        title: 'Git: nome e e-mail',
        line: 'O primeiro commit precisa de nome e e-mail.',
        problem: EnvProblem.gitIdentity,
      );
    await pumpStart(tester, probe);
    final empty = tester.getRect(
      key('start-template-${projectTemplates.first.id}'),
    );
    final flutter = tester.getRect(
      key('start-template-${projectTemplates[1].id}'),
    );
    final other = tester.getRect(key('start-template-custom'));
    expect(empty.width, lessThan(200));
    expect(other.width, lessThan(200));
    // The chips sit next to each other, not one under the other.
    expect(flutter.top, empty.top);
    final save = tester.getRect(key('env-git-save'));
    final terminal = tester.getRect(find.text('ou, no terminal:'));
    expect(save.width, lessThan(200));
    expect(terminal.left, greaterThan(save.right));
    await unmountStart(tester);
  });

  testWidgets('Claude logged out blocks only "Criar e planejar"; the '
      'terminal button runs claude auth login and the item is checked again '
      'when the window comes back (R3, R4)', (tester) async {
    final probe = FakeProbe()
      ..claudeItem = const EnvItem(
        EnvKind.claude,
        EnvState.blocked,
        title: 'Claude Code',
        line: '2.1.300 · sem login',
        problem: EnvProblem.claudeLogin,
        command: 'claude auth login',
      );
    final h = await pumpStart(tester, probe);
    await typeName(tester, 'loja');
    expect(amberTap(tester), isNull);
    expect(smallTap(tester), isNotNull);
    expect(
      hint(tester, 'start-create-plan-semantics'),
      'Entre no Claude Code para planejar.',
    );
    expect(hint(tester, 'start-create-semantics'), isNull);

    await tester.tap(key('env-claude-terminal'));
    await tester.pump();
    expect(find.text('Abrir terminal com claude auth login'), findsOneWidget);
    expect(h.starts.single, [
      'xterm',
      '-e',
      'bash',
      '-lc',
      'claude auth login; exec bash',
    ]);

    probe
      ..calls.clear()
      ..claudeItem = const EnvItem(
        EnvKind.claude,
        EnvState.ok,
        title: 'Claude Code',
        line: '2.1.300 · logado · plano Max',
      );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(probe.calls, ['claude!']);
    expect(stateOf(tester, EnvKind.claude), 'OK');
    expect(amberTap(tester), isNotNull);

    // "Criar sem planejar" with Claude red still creates.
    await tester.tap(key('start-create'));
    await tester.pump();
    expect(h.created.single, contains('plan=false'));
    await unmountStart(tester);
  });

  testWidgets('the hosting indicator follows the radio and the URL; the CLI '
      'is a warning, never a block (R20, R21, R4)', (tester) async {
    final probe = FakeProbe()
      ..hostItem = (hosting, host) => hosting == Hosting.gitlab
          ? EnvItem(
              EnvKind.host,
              EnvState.warning,
              title: 'GitLab (glab)',
              line: 'O glab não está logado em $host.',
              problem: EnvProblem.hostLogin,
              command: 'glab auth login --hostname $host',
              note: gitlabMrNote,
            )
          : EnvItem(
              EnvKind.host,
              EnvState.ok,
              title: 'GitHub (gh)',
              line: 'logado em $host',
            );
    final h = await pumpStart(tester, probe);
    await typeName(tester, 'loja');
    String? hosting() =>
        tester.widget<Semantics>(key('env-hosting')).properties.label;

    // "Conectar a" with github.com: GitHub and the gh check.
    await tester.tap(find.byType(Radio<bool>).last);
    await tester.pump();
    expect(
      hosting(),
      'Hospedagem detectada pelo remoto: aguardando a URL do remoto',
    );
    await tester.enterText(key('start-remote'), 'git@github.com:ana/loja.git');
    await tester.pump();
    expect(hosting(), 'Hospedagem detectada pelo remoto: GitHub');
    expect(stateOf(tester, EnvKind.host), 'VERIFICANDO…');
    await tester.pump(const Duration(milliseconds: 350));
    expect(probe.calls, contains('host github github.com'));
    expect(stateOf(tester, EnvKind.host), 'OK');
    expect(find.text('GitHub (gh)'), findsOneWidget);

    // gitlab.com: GitLab, glab logged out is amber with the terminal fix.
    await tester.enterText(
      key('start-remote'),
      'https://gitlab.com/ana/loja.git',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(hosting(), 'Hospedagem detectada pelo remoto: GitLab');
    expect(stateOf(tester, EnvKind.host), 'AVISO');
    expect(find.text('Abrir terminal com glab auth login'), findsOneWidget);
    expect(find.text(gitlabMrNote), findsOneWidget);
    expect(amberTap(tester), isNotNull);
    expect(smallTap(tester), isNotNull);
    await tester.tap(key('env-host-terminal'));
    await tester.pump();
    expect(
      h.starts.single.last,
      'glab auth login --hostname gitlab.com; exec bash',
    );

    // Another host: only git, with the "não reconhecida" line.
    await tester.enterText(key('start-remote'), 'git@git.empresa.com:a/b.git');
    await tester.pump(const Duration(milliseconds: 350));
    expect(hosting(), 'Hospedagem detectada pelo remoto: não reconhecida');
    expect(key('env-host'), findsNothing);
    expect(key('env-hosting-unknown'), findsOneWidget);

    // Back to "Só local".
    await tester.tap(find.byType(Radio<bool>).first);
    await tester.pump();
    expect(hosting(), 'Hospedagem detectada pelo remoto: Local');
    await unmountStart(tester);
  });

  testWidgets('"Branch inicial": the target line uses it, an invalid name '
      'blocks, and "Criar" passes it on (R5, R6)', (tester) async {
    final probe = FakeProbe();
    final h = await pumpStart(tester, probe);
    await tester.enterText(key('start-parent'), '/srv');
    await typeName(tester, 'loja');
    expect(
      find.text('Será criada: /srv/loja · branch main · commit inicial'),
      findsOneWidget,
    );
    await tester.enterText(key('start-branch'), 'com espaço');
    await tester.pump(const Duration(milliseconds: 350));
    expect(key('start-branch-error'), findsOneWidget);
    expect(amberTap(tester), isNull);
    expect(smallTap(tester), isNull);
    expect(find.text('Corrija 1 item do ambiente para criar.'), findsOneWidget);

    await tester.enterText(key('start-branch'), 'trunk');
    await tester.pump(const Duration(milliseconds: 350));
    expect(key('start-branch-error'), findsNothing);
    expect(
      find.text('Será criada: /srv/loja · branch trunk · commit inicial'),
      findsOneWidget,
    );
    await tester.tap(key('start-create-plan'));
    await tester.pump();
    expect(h.created.single, '/srv/loja plan=true branch=trunk remote=null');
    await unmountStart(tester);
  });

  testWidgets('a red folder offers "Procurar…", and "Verificar de novo" runs '
      'every item again (R2, R3)', (tester) async {
    final probe = FakeProbe()
      ..folderItem = (parent, name) => parent == '/srv/outra'
          ? const EnvItem(
              EnvKind.folder,
              EnvState.ok,
              title: 'Pasta',
              line: '/srv/outra é gravável',
            )
          : const EnvItem(
              EnvKind.folder,
              EnvState.blocked,
              title: 'Pasta',
              line: 'Sem permissão de escrita em ~/workspace.',
              problem: EnvProblem.folderNotWritable,
            );
    await pumpStart(tester, probe);
    expect(stateOf(tester, EnvKind.folder), 'BLOQUEIA');
    expect(
      find.text('Sem permissão de escrita em ~/workspace.'),
      findsOneWidget,
    );
    await tester.tap(key('env-folder-browse'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(stateOf(tester, EnvKind.folder), 'OK');

    probe.calls.clear();
    await tester.tap(key('env-recheck'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(probe.calls, containsAll(['git', 'claude!', 'folder /srv/outra ']));
    await unmountStart(tester);
  });

  testWidgets('"O que acontece" has calls and the queue; "Uso" shows the '
      'quota of the plan once Claude answered (SPEC-072 R7, R8)', (
    tester,
  ) async {
    await pumpStart(tester, FakeProbe());
    expect(
      tester.widget<Text>(key('start-step-1')).data,
      '1. Pasta, git init e commit inicial · segundos',
    );
    expect(find.textContaining('1 s'), findsNothing);
    expect(find.textContaining('0,30'), findsNothing);
    expect(
      tester.widget<Text>(key('start-step-3')).data,
      '3. Fila de refino: 1 rodada por spec · 1–3 min cada',
    );
    expect(find.text('USO · PLANO MAX'), findsOneWidget);
    expect(find.text('O uso aparece depois da primeira chamada.'), findsOne);
    await unmountStart(tester);

    // Claude logged out: no "Uso".
    await pumpStart(
      tester,
      FakeProbe()
        ..claudeItem = const EnvItem(
          EnvKind.claude,
          EnvState.blocked,
          title: 'Claude Code',
          problem: EnvProblem.claudeLogin,
          command: 'claude auth login',
        ),
    );
    expect(find.byKey(const ValueKey('usage-block')), findsNothing);
    await unmountStart(tester);
  });

  testWidgets('"Outro…" opens the modal; the stack chosen there becomes the '
      'starting point, with the pencil, and its calls count (SPEC-072 '
      'R16–R19)', (tester) async {
    final run = FakeCustomRun([goFiber(), goFiber(migrations: 'goose')]);
    final h = await pumpStart(tester, FakeProbe(), custom: run);
    await tester.enterText(key('start-parent'), '/srv');
    await typeName(tester, 'loja');
    expect(find.text('Outro…'), findsOneWidget);
    await tester.tap(key('start-template-custom'));
    await tester.pumpAndSettle();
    expect(key('custom-stack-dialog'), findsOneWidget);
    expect(find.text('Definir a stack com o Claude'), findsOneWidget);

    // Closing without using changes nothing.
    await tester.tap(key('custom-stack-close'));
    await tester.pumpAndSettle();
    expect(find.text('Outro…'), findsOneWidget);
    expect(run.calls, isEmpty);

    await tester.tap(key('start-template-custom'));
    await tester.pumpAndSettle();
    expect(tester.widget<AmberButton>(key('custom-stack-use')).onTap, isNull);
    await tester.enterText(
      key('custom-stack-text'),
      'API em Go com Fiber e Postgres, testes com go test',
    );
    await tester.pump();
    await tester.tap(key('custom-stack-send'));
    await tester.pumpAndSettle();
    expect(key('custom-stack-preview'), findsOneWidget);
    expect(find.text('Go · Fiber'), findsOneWidget);
    expect(find.text('Fiber v2'), findsOneWidget);
    expect(find.textContaining('go mod init loja'), findsOneWidget);
    expect(find.text('1 chamada · plano Max'), findsOneWidget);

    // An adjustment in the same conversation.
    await tester.enterText(key('custom-stack-text'), 'migrations com goose');
    await tester.pump();
    await tester.tap(key('custom-stack-send'));
    await tester.pumpAndSettle();
    expect(run.calls.last.resumeId, run.calls.first.sessionId);
    expect(find.text('Ajuste: migrations com goose'), findsOneWidget);
    expect(find.text('goose'), findsOneWidget);
    await tester.tap(key('custom-stack-use'));
    await tester.pumpAndSettle();
    expect(key('custom-stack-dialog'), findsNothing);

    // The chip shows the stack, with the pencil; the summary line and the
    // cost change.
    expect(find.text('Go · Fiber'), findsOneWidget);
    expect(key('start-template-custom-edit'), findsOneWidget);
    expect(
      tester.widget<Text>(key('start-template-summary')).data,
      'Definida com o Claude: Go 1.23 · Fiber v2 · goose · testes: '
      'go test ./... · CLAUDE.md base; o planner só ajusta.',
    );
    expect(
      tester.widget<Text>(key('start-step-2')).data,
      contains('+2 chamadas (a stack do Outro…)'),
    );

    // Another chip keeps the stack; the pencil reopens the conversation.
    await tester.tap(key('start-template-flutter'));
    await tester.pump();
    expect(find.text('Go · Fiber'), findsOneWidget);
    await tester.tap(key('start-template-custom'));
    await tester.pump();
    await tester.tap(key('start-template-custom-edit'));
    await tester.pumpAndSettle();
    expect(find.text('Ajuste: migrations com goose'), findsOneWidget);
    await tester.tap(key('custom-stack-close'));
    await tester.pumpAndSettle();

    await tester.tap(key('start-create-plan'));
    await tester.pump();
    expect(h.created.single, endsWith('stack=Go · Fiber calls=2'));
    await unmountStart(tester);
  });

  testWidgets('with Claude red, "Outro…" is off and says why (R16)', (
    tester,
  ) async {
    await pumpStart(
      tester,
      FakeProbe()
        ..claudeItem = const EnvItem(
          EnvKind.claude,
          EnvState.blocked,
          title: 'Claude Code',
          problem: EnvProblem.claudeLogin,
          command: 'claude auth login',
        ),
    );
    expect(
      tester
          .widget<Semantics>(key('start-template-custom-semantics'))
          .properties
          .hint,
      'Entre no Claude Code para definir outra stack',
    );
    await tester.tap(key('start-template-custom'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(key('custom-stack-dialog'), findsNothing);
    await unmountStart(tester);
  });
}
