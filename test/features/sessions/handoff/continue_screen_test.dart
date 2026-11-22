
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/capabilities.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/handoff/continue_controller.dart';
import 'package:promptorium/features/sessions/handoff/continue_link.dart';
import 'package:promptorium/features/sessions/handoff/continue_widgets.dart';
import 'package:promptorium/features/sessions/handoff/handoff_card.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../sessions_screen_test.dart' show pumpScreen, pumpFor;

class _Controller extends ContinueController {
  _Controller(super.ref);

  @override
  Future<List<String>> uncommitted(String worktree) async =>
      const ['a.dart', 'b.dart', 'c.dart', 'd.dart', 'e.dart'];
}

final _ready = providerAvailabilityProvider.overrideWith(
  (ref, id) async => const ProviderAvailability(ProviderStatus.ready, 'ok'),
);

/// The header uses the CLI probes only once they exist (under test).
Future<void> _probe(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(const ValueKey('session-header-title'))),
  );
  for (final id in ['claude', 'codex']) {
    container.listen(providerAvailabilityProvider(id), (_, _) {});
  }
  await pumpFor(tester);
  // Rebuilds the header (it watches the flows).
  container.invalidate(providerFlowsProvider);
  await pumpFor(tester);
}

Future<void> _set(
  WidgetTester tester,
  AppDatabase db,
  SessionsCompanion c,
) => tester.runAsync(
  () => (db.update(db.sessions)..where((s) => s.id.equals('s1'))).write(c),
);

/// SPEC-099 on the Sessões screen: the button (R1), the dialog (R3) and the
/// link in both directions (R8, R9).
void main() {
  testWidgets('R1: "Continuar no Codex" beside Fork, disabled with the reason '
      'when the Codex is off in Sessões, (P4, hidden in step sessions, is in the controller test)', (
    tester,
  ) async {
    var flows = ProviderFlows.defaults;
    final (db, _) = await pumpScreen(
      tester,
      overrides: [
        _ready,
        providerFlowsProvider.overrideWith((ref) => flows),
      ],
    );
    await _probe(tester);
    await _set(
      tester,
      db,
      const SessionsCompanion(status: Value(SessionStatus.completed)),
    );
    await pumpFor(tester);
    final button = find.byKey(const ValueKey('session-continue'));
    expect(button, findsOneWidget);
    expect(find.text('Continuar no Codex'), findsOneWidget);
    // Off in Sessões: disabled with the reason.
    flows = ProviderFlows.defaults.turnOff('codex');
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('session-header-title'))),
    );
    container.invalidate(providerFlowsProvider);
    await pumpFor(tester);
    final tip = tester.widget<Tooltip>(
      find.byKey(const ValueKey('session-continue-reason')),
    );
    expect(tip.message, 'Codex não está ligado nas Sessões');
    flows = ProviderFlows.defaults;
    container.invalidate(providerFlowsProvider);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('session-continue-reason')), findsNothing);
  });

  testWidgets('R3: the dialog shows origin and target, worktree, branch, '
      'uncommitted files, model, converted access, what stays behind and '
      'the app summary in the message field', (tester) async {
    final (db, _) = await pumpScreen(
      tester,
      overrides: [
        _ready,
        continueControllerProvider.overrideWith(_Controller.new),
      ],
    );
    await _probe(tester);
    await _set(
      tester,
      db,
      const SessionsCompanion(
        agentName: Value('revisor'),
        permissionMode: Value('acceptEdits'),
        status: Value(SessionStatus.completed),
      ),
    );
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('session-continue')));
    await pumpFor(tester, 5);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await pumpFor(tester, 10);
    expect(find.byKey(const ValueKey('continue-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('continue-dialog-title')), findsOneWidget);
    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('continue-title')),
    );
    expect(title.controller!.text, 'Shell da IDE (Codex)');
    expect(find.text('repo-wt · pr/shell-ide'), findsOneWidget);
    expect(find.text('5 arquivos, ficam no worktree'), findsOneWidget);
    expect(find.text('padrão do Codex'), findsOneWidget);
    expect(find.text('Editar · escreve com confirmação'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('continue-behind-agente')),
      findsOneWidget,
    );
    expect(find.text('Só Claude Code'), findsOneWidget);
    // Without ai-memory: the app summary is the only path, with the line
    // that points to Configurações → Memória.
    expect(find.byKey(const ValueKey('continue-path-resumo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('continue-no-ai-memory')),
      findsOneWidget,
    );
    final message = tester.widget<TextField>(
      find.byKey(const ValueKey('continue-message')),
    );
    expect(
      message.controller!.text,
      startsWith('Continuação da sessão "Shell da IDE" (Claude Code).'),
    );
    expect(message.controller!.text, contains('Não commitados: 5 arquivos.'));
    await tester.tap(find.byKey(const ValueKey('continue-cancel')));
    await pumpFor(tester, 20);
    expect(find.byKey(const ValueKey('continue-dialog')), findsNothing);
  });

  testWidgets('R8, R9: the new session says where it came from with the '
      'card; the origin says where it went; each end opens the other', (
    tester,
  ) async {
    final record = ContinuationRecord(
      fromId: 's1',
      fromTitle: 'Shell da IDE',
      fromProvider: 'claude',
      toProvider: 'codex',
      path: ContinuePath.summary,
      at: DateTime(2026, 11, 20, 11, 41),
      text: 'Continuação da sessão "Shell da IDE" (Claude Code).',
    );
    Session session(String id, String provider, String title) => Session(
      id: id,
      workspaceId: 1,
      provider: provider,
      title: title,
      worktreePath: '/work/repo-wt',
      branch: 'pr/shell-ide',
      status: SessionStatus.completed,
      model: 'inherit',
      costUsd: 0,
      tokensIn: 0,
      tokensOut: 0,
      startedAt: DateTime(2026, 11, 20, 11),
      parentSessionId: id == 's2' ? 's1' : null,
    );
    final s1 = session('s1', 'claude', 'Shell da IDE');
    final s2 = session('s2', 'codex', 'Shell da IDE (Codex)');
    final container = ProviderContainer(
      overrides: [
        sessionsProvider(1).overrideWith((ref) => Stream.value([s2, s1])),
        continuationLinksProvider(1).overrideWith(
          (ref) => Stream.value(ContinuationLinks({'s2': record})),
        ),
      ],
    );
    addTearDown(container.dispose);
    final item = HandoffItem(
      record.toJson(),
      handoffNotice(record.toJson(), record.at),
      at: record.at,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: [
                ContinueLinkLine(session: s2),
                ContinueLinkLine(session: s1),
                HandoffCard(item: item),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('continuada de'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-continued-from')), findsOneWidget);
    expect(find.text('Continuada no Codex →'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-continued-into')), findsOneWidget);
    expect(find.byKey(const ValueKey('handoff-card')), findsOneWidget);
    expect(find.text('Resumo do app'), findsOneWidget);
    expect(
      find.text('Continuada de "Shell da IDE" · Claude Code · 11:41 · mesmo worktree'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('handoff-card-text')), findsOneWidget);
    // Each end opens the other.
    await tester.tap(find.byKey(const ValueKey('session-continued-from')));
    expect(container.read(selectedSessionProvider), 's1');
    await tester.tap(find.byKey(const ValueKey('session-continued-into')));
    expect(container.read(selectedSessionProvider), 's2');
  });
}
