import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/ai_memory_cli.dart';
import 'package:promptorium/core/memory/ai_memory_state.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/widgets/ai_memory_view.dart';
import 'package:promptorium/features/project/widgets/project_memory_view.dart';
import 'package:promptorium/features/settings/ai_memory_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/memory/fake_ai_memory.dart';
import '../../helpers/test_db.dart';

/// SPEC-098 T4: the ai-memory section of Projeto → Memória (R8–R14), with
/// the JSON of ai-memory 3.5.1 answered by a fake CLI runner.
void main() {
  const ws = '/repo/promptorium-wt/spec-parser';
  const connected = AiMemoryDetection(
    status: AiMemoryStatus.connected,
    executable: '/home/u/.local/bin/ai-memory',
    version: '3.5.1',
  );

  late List<List<String>> calls;
  late List<String> opened;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    AiMemoryDetection detection = connected,
    String Function()? handoffs,
    Object? Function(List<String> args)? fail,
    int? webStatus = 200,
    Map<String, String> extra = const {},
    HandoffContinueAction? continueAction,
    bool openPanel = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    calls = [];
    opened = [];
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        aiMemoryDetectionProvider.overrideWith((ref) async => detection),
        aiMemoryCliProvider.overrideWith(
          (ref) async => AiMemoryCli(
            executable: 'ai-memory',
            log: (_) {},
            run: (exe, args, {workingDirectory, required timeout}) async {
              calls.add(args);
              if (fail?.call(args) case final e?) throw e;
              final key = args.take(2).join(' ');
              final out = switch (key) {
                'call memory_handoff_list' =>
                  handoffs?.call() ?? handoffListJson(),
                'call memory_briefing' => briefingJson(),
                'call memory_handoff_cancel' => jsonEncode({
                  'handoff_id': 'x',
                  'cancelled': true,
                  'state': 'expired',
                }),
                'status --json' => jsonEncode({'data_dir': '/data/aim'}),
                _ => extra[key],
              };
              return ProcessResult(0, out == null ? 2 : 0, out ?? '', '');
            },
          ),
        ),
        aiMemoryHttpProbeProvider.overrideWithValue(
          (url, timeout) async => webStatus,
        ),
        aiMemoryOpenerProvider.overrideWithValue((t) async => opened.add(t)),
        // SPEC-099 fills the action; these tests set theirs (or none).
        handoffContinueActionProvider.overrideWithValue(continueAction),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    if (openPanel) {
      await c.read(appSettingsProvider.notifier).set(aiMemoryPanelOpenKey, '1');
    }
    final w = await c.read(workspacesRepoProvider).add(path: ws, name: 'p');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: ProjectMemoryView(workspace: w)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  int reads() => calls.where((a) => a[1] == 'memory_handoff_list').length;

  testWidgets('R2: without ai-memory the tab has no selector and is the same '
      'as before', (tester) async {
    await pump(tester, detection: AiMemoryDetection.notInstalled);
    expect(
      find.byKey(const ValueKey('memory-selector-ai-memory')),
      findsNothing,
    );
    expect(find.text('Memória do projeto'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('R8 + R9: selector, status line, open handoffs with agent, '
      'time, owner, origin, directory and the "será entregue" badge', (
    tester,
  ) async {
    await pump(tester, openPanel: false);
    // Facts first, by default.
    expect(find.text('Memória do projeto'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('memory-selector-ai-memory')));
    await tester.pumpAndSettle();
    final status = tester
        .widget<Text>(find.byKey(const ValueKey('ai-memory-status-line')))
        .textSpan!
        .toPlainText();
    expect(status, contains('ai-memory 3.5.1 conectado'));
    expect(status, contains('127.0.0.1:49374'));
    expect(status, contains('projeto default/promptorium'));
    expect(status, contains('última captura'));
    expect(find.text('PASSAGENS PENDENTES · 2'), findsOneWidget);
    const auto = '01JDX4AUTO0000000000000000';
    final meta = tester
        .widget<Text>(
          find.byKey(const ValueKey('ai-memory-handoff-meta-$auto')),
        )
        .textSpan!
        .toPlainText();
    expect(meta, contains('automática · fim da sessão'));
    expect(meta, contains('dono: você'));
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('worktree: review-021'), findsOneWidget);
    // The badge sits on the handoff of this directory.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai-memory-handoff-$auto')),
        matching: find.byKey(const ValueKey('ai-memory-next-badge')),
      ),
      findsOneWidget,
    );
    // Expanded: summary, questions, next steps, files.
    await tester.tap(
      find.byKey(const ValueKey('ai-memory-handoff-toggle-$auto')),
    );
    await tester.pumpAndSettle();
    expect(find.text('PERGUNTAS ABERTAS'), findsOneWidget);
    expect(
      find.text('•  Escrever test/spec_parser_bom_test.dart'),
      findsOneWidget,
    );
    expect(find.text('lib/core/spec_parser.dart'), findsOneWidget);
    expect(find.text('Copiar id 01JDX4…'), findsOneWidget);
    // R11: the panel never accepts; "Continuar em…" only with an action.
    expect(find.textContaining('Aceitar'), findsNothing);
    expect(find.textContaining('Continuar'), findsNothing);
    // Read without claiming (memory_handoff_list), in the workspace.
    expect(calls.first.take(2), ['call', 'memory_handoff_list']);
  });

  testWidgets('R9: the history shows who accepted and when', (tester) async {
    await pump(tester, handoffs: () => handoffListJson(history: true));
    expect(find.text('Uma passagem antiga.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-memory-history')));
    await tester.pumpAndSettle();
    expect(find.text('Uma passagem antiga.'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('ai-memory-accepted-01JDX1OLD00000000000000000'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('aceita por Claude Code'), findsOneWidget);
  });

  testWidgets('R9: without history from the server the filter says so', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('ai-memory-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-memory-no-history')), findsOneWidget);
  });

  testWidgets('R10: a session cut off without a handoff becomes a warning', (
    tester,
  ) async {
    await pump(tester, handoffs: () => handoffListJson(unended: true));
    expect(find.byKey(const ValueKey('ai-memory-unended')), findsOneWidget);
    expect(find.text('Sessão do Codex terminou sem passagem'), findsOneWidget);
    expect(find.textContaining('id 019a3f2c'), findsOneWidget);
    expect(find.textContaining('vai ler direto'), findsOneWidget);
  });

  testWidgets('R11 + P6: Descartar asks first (it cannot be undone), then '
      'calls memory_handoff_cancel and reads again', (tester) async {
    await pump(tester);
    const auto = '01JDX4AUTO0000000000000000';
    await tester.tap(
      find.byKey(const ValueKey('ai-memory-handoff-toggle-$auto')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-memory-discard-$auto')));
    await tester.pumpAndSettle();
    expect(find.textContaining('A ação não se desfaz'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-memory-discard-cancel')));
    await tester.pumpAndSettle();
    expect(calls.where((a) => a[1] == 'memory_handoff_cancel'), isEmpty);

    final before = reads();
    await tester.tap(find.byKey(const ValueKey('ai-memory-discard-$auto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-memory-discard-confirm')));
    await tester.pumpAndSettle();
    final cancel = calls.singleWhere((a) => a[1] == 'memory_handoff_cancel');
    expect(jsonDecode(cancel[2]), {'handoff_id': auto});
    expect(reads(), before + 1);
  });

  testWidgets('P6: on a team server, a shared handoff has no Descartar; '
      'the own one has', (tester) async {
    await pump(
      tester,
      handoffs: () => jsonEncode({
        'handoffs': [
          {
            'id': 'mine',
            'from_session_id': 's1',
            'from_agent': 'codex',
            'owner_user': 'alice',
            'cwd': ws,
            'summary': 'minha',
            'state': 'open',
            'created_at': '2026-11-20T10:00:00Z',
          },
          {
            'id': 'shared',
            'from_agent': 'claude-code',
            'owner_user': null,
            'summary': 'do time',
            'state': 'open',
            'created_at': '2026-11-20T09:00:00Z',
          },
        ],
      }),
    );
    for (final id in ['mine', 'shared']) {
      await tester.tap(find.byKey(ValueKey('ai-memory-handoff-toggle-$id')));
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const ValueKey('ai-memory-discard-mine')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-memory-discard-shared')),
      findsNothing,
    );
    expect(find.textContaining('dono: compartilhada'), findsOneWidget);
  });

  testWidgets('R11: "Continuar em…" appears when SPEC-099 provides it', (
    tester,
  ) async {
    final continued = <String>[];
    await pump(
      tester,
      continueAction: HandoffContinueAction(
        label: (h) => 'Continuar no Codex',
        run: (context, h) async => continued.add(h.id),
      ),
    );
    const auto = '01JDX4AUTO0000000000000000';
    await tester.tap(
      find.byKey(const ValueKey('ai-memory-handoff-toggle-$auto')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-memory-continue-$auto')));
    expect(continued, [auto]);
  });

  testWidgets('R12: Abrir wiki opens the web UI page when it answers', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('4.198'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-memory-open-wiki')));
    await tester.pumpAndSettle();
    expect(opened, ['http://127.0.0.1:49374/web/w/default/promptorium']);
    await tester.tap(
      find.byKey(
        const ValueKey('ai-memory-page-decisions/parser-por-linhas.md'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      opened.last,
      'http://127.0.0.1:49374/web/w/default/promptorium/p/'
      'decisions/parser-por-linhas.md',
    );
  });

  testWidgets('R12: without the web UI it opens the project folder in the '
      'wiki', (tester) async {
    await pump(tester, webStatus: 404);
    await tester.tap(find.byKey(const ValueKey('ai-memory-open-wiki')));
    await tester.pumpAndSettle();
    expect(opened, ['/data/aim/wiki/default/promptorium']);
    expect(calls.any((a) => a.first == 'status'), isTrue);
  });

  testWidgets('R13: markdown, links and <script> in a handoff are plain text', (
    tester,
  ) async {
    const evil =
        '**negrito** [clique](http://evil.example) <script>alert(1)</script>';
    await pump(
      tester,
      handoffs: () => jsonEncode({
        'handoffs': [
          {
            'id': 'h1',
            'from_session_id': 's1',
            'from_agent': 'claude-code',
            'cwd': ws,
            'summary': evil,
            'next_steps': ['<img src=x onerror=alert(1)>'],
            'state': 'open',
            'created_at': '2026-11-20T10:00:00Z',
          },
        ],
      }),
    );
    await tester.tap(find.byKey(const ValueKey('ai-memory-handoff-toggle-h1')));
    await tester.pumpAndSettle();
    final summary = tester.widget<Text>(
      find.byKey(const ValueKey('ai-memory-summary-h1')),
    );
    expect(summary.data, evil);
    expect(summary.textSpan, isNull);
    expect(find.text('•  <img src=x onerror=alert(1)>'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-memory-summary-h1')));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets('R14: a slow call becomes a status line with "Tentar de novo", '
      'the tab keeps working', (tester) async {
    var slow = true;
    await pump(
      tester,
      fail: (args) => slow && args.first == 'call'
          ? TimeoutException('lento', aiMemoryCallTimeout)
          : null,
    );
    expect(find.byKey(const ValueKey('ai-memory-read-error')), findsOneWidget);
    expect(find.textContaining('tempo esgotado em 5 s'), findsOneWidget);
    expect(find.textContaining('Os fatos do projeto não'), findsOneWidget);
    slow = false;
    await tester.tap(find.byKey(const ValueKey('ai-memory-retry')));
    await tester.pumpAndSettle();
    expect(find.text('PASSAGENS PENDENTES · 2'), findsOneWidget);
    // The facts are still one tap away.
    await tester.tap(find.byKey(const ValueKey('memory-selector-facts')));
    await tester.pumpAndSettle();
    expect(find.text('Memória do projeto'), findsOneWidget);
  });

  testWidgets('R14: server stopped = a status line, no call at all', (
    tester,
  ) async {
    await pump(
      tester,
      detection: const AiMemoryDetection(
        status: AiMemoryStatus.serverDown,
        executable: '/usr/bin/ai-memory',
        version: '3.5.1',
      ),
    );
    expect(find.byKey(const ValueKey('ai-memory-panel-down')), findsOneWidget);
    expect(find.text(aiMemoryStartCommand), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('R14: reads on "Atualizar" and when a session of the project '
      'ends, never on a timer', (tester) async {
    final c = await pump(tester);
    expect(reads(), 1);
    await tester.pump(const Duration(minutes: 10));
    expect(reads(), 1);
    await tester.tap(find.byKey(const ValueKey('ai-memory-refresh')));
    await tester.pumpAndSettle();
    expect(reads(), 2);

    final w = (await c.read(workspacesRepoProvider).getByPath(ws))!;
    final repo = c.read(sessionsRepoProvider);
    await tester.runAsync(
      () => repo.insert(
        id: 's1',
        workspaceId: w.id,
        worktreePath: ws,
        branch: 'main',
        model: 'sonnet',
      ),
    );
    await tester.pumpAndSettle();
    expect(reads(), 2);
    await tester.runAsync(() => repo.setStatus('s1', SessionStatus.completed));
    await tester.pumpAndSettle();
    expect(reads(), 3);
  });

  testWidgets('copies the id', (tester) async {
    await pump(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    const auto = '01JDX4AUTO0000000000000000';
    await tester.tap(
      find.byKey(const ValueKey('ai-memory-handoff-toggle-$auto')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-memory-copy-$auto')));
    await tester.pump();
    expect(copied, auto);
  });
}
