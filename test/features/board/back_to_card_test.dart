import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../prompt/back_to_spec_test.dart' show MemorySpecService;
import '../sessions/session_test_utils.dart';
import 'board_screen_test.dart' show pumpFor;

/// Prompt or Quadro, following the navigation (as the app shell does).
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(navigationProvider) == AppSection.tasks
      ? const BoardScreen()
      : const PromptScreen();
}

void main() {
  testWidgets('"Voltar à spec" from a card suggestion: back to the Quadro '
      '(columns) with the card open and in view, re-read from disk; spec '
      'and suggestion states unchanged (R4, R10)', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final ws = await db
        .into(db.workspaces)
        .insertReturning(
          WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
        );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.activeWorkspace,
            value: '${ws.id}',
          ),
        );
    // Enough cards in the backlog column for the target to start off-screen.
    Spec? target;
    for (var i = 1; i <= 14; i++) {
      final code = 'SPEC-${i.toString().padLeft(3, '0')}';
      final s = await db
          .into(db.specs)
          .insertReturning(
            SpecsCompanion.insert(
              workspaceId: ws.id,
              code: code,
              title: 'Spec $i',
              path: 'specs/$code.md',
              status: const Value(SpecStatus.approved),
              requirements: const Value([(id: 'R1', text: 'Req 1')]),
            ),
          );
      if (i == 14) target = s;
    }
    final spec = target!;
    await db
        .into(db.specSuggestions)
        .insert(
          SpecSuggestionsCompanion.insert(
            specId: spec.id,
            body: 'dividir R1',
            state: const Value('aplicada'),
          ),
        );
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            workspaceId: ws.id,
            title: 'Aplicar sugestão',
            model: 'sonnet',
            mode: const Value('refine'),
            refineSpecCode: Value(spec.code),
            refineOrigin: const Value('board'),
            updatedAt: Value(DateTime.now()),
          ),
        );
    late MemorySpecService specs;
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
        workspaceFilesProvider.overrideWith((ref, root) async => const []),
        specServiceProvider.overrideWith(
          (ref) => specs = MemorySpecService(
            ref.watch(specsRepoProvider),
            {spec.path: '# Refinada\n'},
            // The agent's edit, as the real sync would read it.
            onSync: () async =>
                (db.update(db.specs)..where((t) => t.id.equals(spec.id))).write(
                  const SpecsCompanion(title: Value('Refinada')),
                ),
          ),
        ),
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
    c.read(navigationProvider.notifier).go(AppSection.prompt);
    c.read(boardGraphViewProvider.notifier).set(true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: _Host()),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(Duration.zero);
    });
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('conversation-1')));
    await pumpFor(tester);

    await tester.tap(find.byKey(const ValueKey('prompt-back-to-spec')));
    await pumpFor(tester, 30);

    expect(specs.syncs, greaterThanOrEqualTo(1));
    expect(c.read(navigationProvider), AppSection.tasks);
    expect(c.read(boardGraphViewProvider), isFalse);
    expect(c.read(boardSelectedSpecProvider), spec.id);
    expect(c.read(boardFocusSpecProvider), isNull); // consumed by the card
    expect(find.byKey(const ValueKey('board-side-panel')), findsOneWidget);
    // In view, with the content read again.
    final card = find.byKey(ValueKey('board-card-${spec.code}'));
    expect(card, findsOneWidget);
    final rect = tester.getRect(card);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(900));
    expect(
      find.descendant(of: card, matching: find.text('Refinada')),
      findsOneWidget,
    );
    // R10: only navigation.
    final after = await c.read(specsRepoProvider).getByCode(ws.id, spec.code);
    expect(after!.status, SpecStatus.approved);
    expect(after.stage, spec.stage);
    final sugg = await db.select(db.specSuggestions).getSingle();
    expect(sugg.state, 'aplicada');
    expect(tester.takeException(), isNull);
  });
}
