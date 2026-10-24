import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prompt_test_utils.dart';

/// [SpecService] over an in-memory map of files (no real IO under
/// FakeAsync); counts the syncs.
class MemorySpecService extends SpecService {
  MemorySpecService(super.repo, this.files, {this.onSync});

  final Map<String, String> files;

  /// Stands for what the real sync reads from disk.
  final Future<void> Function()? onSync;
  int syncs = 0;

  @override
  Future<String?> read(Workspace ws, Spec spec) async => files[spec.path];

  @override
  Future<void> sync(Workspace ws) async {
    syncs++;
    await onSync?.call();
  }
}

/// Shows the Prompt screen while it is the current section, otherwise the
/// name of the section the app went to.
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(navigationProvider);
    return s == AppSection.prompt
        ? const PromptScreen()
        : Text('section:${s.name}', key: const ValueKey('host-section'));
  }
}

typedef _Setup = ({
  AppDatabase db,
  ProviderContainer c,
  FakeCli cli,
  MemorySpecService specs,
  Spec spec,
});

Future<_Setup> _pump(
  WidgetTester tester, {
  String mode = 'refine',
  String? code = 'SPEC-002',
  String? origin = 'specs',
  bool fileExists = true,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final cli = FakeCli();
  final ws = await addWorkspace(db, '/work/repo');
  final spec = await db
      .into(db.specs)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: 'SPEC-002',
          title: 'Sessões',
          path: 'specs/SPEC-002-sessoes.md',
        ),
      );
  await db
      .into(db.conversations)
      .insert(
        ConversationsCompanion.insert(
          workspaceId: ws.id,
          title: 'Refine a spec',
          model: 'sonnet',
          mode: Value(mode),
          claudeSessionId: const Value('conv-sid'),
          refineSpecCode: Value(code),
          refineOrigin: Value(origin),
          updatedAt: Value(DateTime.now()),
        ),
      );
  late MemorySpecService specs;
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      workspaceFilesProvider.overrideWith((ref, root) async => const []),
      specServiceProvider.overrideWith((ref) {
        return specs = MemorySpecService(ref.watch(specsRepoProvider), {
          if (fileExists) 'specs/SPEC-002-sessoes.md': '# Sessões\n',
        });
      }),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  container.read(navigationProvider.notifier).go(AppSection.prompt);
  container.read(specServiceProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: _Host()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester);
  await tester.tap(find.byKey(const ValueKey('conversation-1')));
  await pumpFor(tester);
  return (db: db, c: container, cli: cli, specs: specs, spec: spec);
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

final _back = find.byKey(const ValueKey('prompt-back-to-spec'));

void main() {
  testWidgets('a refine conversation with an origin shows "Voltar à spec '
      '<código>" (R2)', (tester) async {
    await _pump(tester);
    expect(_back, findsOneWidget);
    expect(find.text('Voltar à spec SPEC-002'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['ask', 'plan', 'edit']) {
    testWidgets('no "Voltar à spec" in a "$mode" conversation (R2)', (
      tester,
    ) async {
      await _pump(tester, mode: mode);
      expect(_back, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a refine conversation without a stored origin shows no action '
      'and renders normally (R6)', (tester) async {
    await _pump(tester, code: null, origin: null);
    expect(_back, findsNothing);
    expect(find.byKey(const ValueKey('prompt-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-to-spec')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('origin Specs: re-reads specs/, selects the spec and opens '
      'Specs; the conversation stays and can be reopened (R3, R7)', (
    tester,
  ) async {
    final s = await _pump(tester);
    await tester.tap(_back);
    await pumpFor(tester);
    expect(s.c.read(navigationProvider), AppSection.specs);
    expect(s.c.read(selectedSpecProvider), s.spec.id);
    expect(s.specs.syncs, 1);
    expect(find.text('section:specs'), findsOneWidget);
    // R7: only navigation; the conversation is kept and still selected.
    expect(s.c.read(selectedConversationProvider), 1);
    final convs = await s.c.read(conversationsRepoProvider).getById(1);
    expect(convs, isNotNull);
    s.c.read(navigationProvider.notifier).go(AppSection.prompt);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('conversation-1')), findsOneWidget);
    expect(find.text('Refine a spec'), findsWidgets);
    expect(_back, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('origin board: list view, card selected and focused, Quadro '
      'opened (R4)', (tester) async {
    final s = await _pump(tester, origin: 'board');
    await tester.tap(_back);
    await pumpFor(tester);
    expect(s.c.read(navigationProvider), AppSection.tasks);
    expect(s.specs.syncs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removed or renamed spec: warning and the Prompt screen stays '
      '(R5)', (tester) async {
    final s = await _pump(tester, fileExists: false);
    await tester.tap(_back);
    await pumpFor(tester);
    expect(find.text('A spec SPEC-002 não foi encontrada.'), findsOneWidget);
    expect(s.c.read(navigationProvider), AppSection.prompt);
    expect(find.byType(PromptScreen), findsOneWidget);
    expect(s.specs.syncs, 0);

    // Renamed: the stored code no longer matches any spec.
    await (s.db.update(s.db.specs)..where((t) => t.id.equals(s.spec.id))).write(
      const SpecsCompanion(code: Value('SPEC-009')),
    );
    s.specs.files['specs/SPEC-002-sessoes.md'] = '# Sessões\n';
    await tester.tap(_back);
    await pumpFor(tester);
    expect(find.text('A spec SPEC-002 não foi encontrada.'), findsOneWidget);
    expect(s.c.read(navigationProvider), AppSection.prompt);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit pending approval: warns first; "Ficar na conversa" stays '
      'and "Voltar mesmo assim" navigates, the approval still pending (R8)', (
    tester,
  ) async {
    final s = await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('prompt-field')),
      'pode editar',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester);
    s.cli.last.emit(
      '{"type":"control_request","request_id":"req-edit","request":'
      '{"subtype":"can_use_tool","tool_name":"Edit","input":'
      '{"file_path":"/work/repo/specs/SPEC-002-sessoes.md",'
      '"old_string":"a","new_string":"b"}}}',
    );
    await pumpFor(tester);
    expect(s.c.read(conversationManagerProvider).approvalsOf(1), isNotEmpty);

    await tester.tap(_back);
    await pumpFor(tester);
    expect(
      find.byKey(const ValueKey('prompt-back-pending-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('prompt-back-stay')));
    await pumpFor(tester);
    expect(s.c.read(navigationProvider), AppSection.prompt);
    expect(find.byType(PromptScreen), findsOneWidget);

    await tester.tap(_back);
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('prompt-back-anyway')));
    await pumpFor(tester);
    expect(s.c.read(navigationProvider), AppSection.specs);
    // Not answered: the agent keeps waiting.
    expect(s.c.read(conversationManagerProvider).approvalsOf(1), hasLength(1));
    expect(s.c.read(conversationManagerProvider).isAlive(1), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard: Tab focuses the action, Enter and Space trigger it; '
      'it has an accessible button label (R11)', (tester) async {
    final handle = tester.ensureSemantics();
    final s = await _pump(tester, fileExists: false);
    expect(
      tester.getSemantics(_back),
      matchesSemantics(
        label: 'Voltar à spec SPEC-002',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    final focus = Focus.of(
      tester.element(
        find.descendant(
          of: _back,
          matching: find.text('Voltar à spec SPEC-002'),
        ),
      ),
    );
    var tabs = 0;
    while (!focus.hasPrimaryFocus && tabs < 40) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      tabs++;
    }
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFor(tester);
    expect(find.text('A spec SPEC-002 não foi encontrada.'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(_back)).removeCurrentSnackBar();
    await pumpFor(tester);
    expect(find.text('A spec SPEC-002 não foi encontrada.'), findsNothing);

    s.specs.files['specs/SPEC-002-sessoes.md'] = '# Sessões\n';
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpFor(tester);
    expect(s.c.read(navigationProvider), AppSection.specs);
    handle.dispose();
    expect(tester.takeException(), isNull);
  });
}
