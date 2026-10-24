import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show SilentConversationManager;
import '../sessions/session_test_utils.dart';
import 'spec_file_test.dart' show sample;
import 'specs_screen_test.dart' show QuietWorkspaceWatcher, settleIo;

/// Specs or Prompt, following the navigation (as the app shell does: each
/// visit mounts the screen again).
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(navigationProvider) == AppSection.prompt
      ? const PromptScreen()
      : const SpecsScreen();
}

void main() {
  late Directory tmp;
  File file() => File('${tmp.path}/specs/SPEC-002-sessoes.md');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-back-to-spec-');
    Directory('${tmp.path}/specs').createSync();
    file().writeAsStringSync(sample);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Specs screen with SPEC-002 synced; [draft] pre-fills the unsaved text
  /// left in the editor (R9).
  Future<(ProviderContainer, SilentConversationManager, Spec)> pump(
    WidgetTester tester, {
    String? draft,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final manager = SilentConversationManager();
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
        workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
        workspaceFilesProvider.overrideWith((ref, root) async => const []),
        conversationManagerProvider.overrideWith(() => manager),
      ],
    );
    final spec = (await tester.runAsync(() async {
      final ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'ws'),
          );
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppSettingKeys.activeWorkspace,
              value: '${ws.id}',
            ),
          );
      await c.read(appSettingsProvider.notifier).load();
      await c.read(specServiceProvider).sync(ws);
      return c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-002');
    }))!;
    c.read(navigationProvider.notifier).go(AppSection.specs);
    if (draft != null) {
      c.read(specUnsavedProvider.notifier).keep(spec.id, draft);
    }
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
    final dialog = find.byKey(const ValueKey('specs-unsaved-dialog'));
    await settleIo(
      tester,
      until: () =>
          find.byType(CodeEditor).evaluate().isNotEmpty ||
          dialog.evaluate().isNotEmpty,
    );
    return (c, manager, spec);
  }

  String editorText(WidgetTester tester) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text;

  final dialog = find.byKey(const ValueKey('specs-unsaved-dialog'));
  final back = find.byKey(const ValueKey('prompt-back-to-spec'));

  testWidgets('"Refinar com IA" → agent edits the file → "Voltar à spec": '
      'Specs opens with the spec selected and the new content; status '
      'unchanged and the conversation kept (R3, R7, R10)', (tester) async {
    final (c, manager, spec) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('spec-refine')));
    await settleIo(tester, until: () => back.evaluate().isNotEmpty);
    expect(c.read(navigationProvider), AppSection.prompt);
    final convId = manager.sent.single.$1;

    // The refine agent rewrites the file.
    final edited = sample.replaceFirst(
      '# Sessões com stream-json',
      '# Sessões refinadas pelo agente',
    );
    file().writeAsStringSync(edited);
    c.read(selectedSpecProvider.notifier).select(null);

    await tester.tap(back);
    await settleIo(
      tester,
      until: () =>
          find.byType(CodeEditor).evaluate().isNotEmpty &&
          editorText(tester) == edited,
    );
    expect(c.read(navigationProvider), AppSection.specs);
    expect(c.read(selectedSpecProvider), spec.id);
    expect(editorText(tester), edited);
    expect(find.text('Sessões refinadas pelo agente'), findsWidgets);
    expect(find.byKey(const ValueKey('spec-unsaved')), findsNothing);
    // R10: the status of the file and of the row stay as they were.
    final after = await tester.runAsync(
      () => c.read(specsRepoProvider).getByCode(spec.workspaceId, spec.code),
    );
    expect(after!.status, spec.status);
    expect(after.stage, spec.stage);
    expect(file().readAsStringSync(), contains('status: em-revisao'));
    // R7: the conversation is still there and selected.
    expect(c.read(selectedConversationProvider), convId);
    final conv = await tester.runAsync(
      () => c.read(conversationsRepoProvider).getById(convId),
    );
    expect(conv, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving Specs with unsaved changes keeps them for the next '
      'visit (R9)', (tester) async {
    final (c, _, spec) = await pump(tester);
    final draft = sample.replaceFirst('# Sessões com stream-json', '# Meu');
    tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text = draft;
    await tester.pump();
    await tester.pump();
    c.read(navigationProvider.notifier).go(AppSection.prompt);
    await tester.pump();
    await tester.pump();
    expect(c.read(specUnsavedProvider)[spec.id], draft);
    expect(file().readAsStringSync(), sample);
  });

  testWidgets('unsaved text differing from the file: the dialog shows the '
      'diff; "Manter minhas alterações" keeps it unsaved (R9)', (tester) async {
    final draft = sample.replaceFirst('# Sessões com stream-json', '# Meu');
    await pump(tester, draft: draft);
    expect(dialog, findsOneWidget);
    final diff = find.byKey(const ValueKey('specs-unsaved-diff'));
    expect(
      find.descendant(of: diff, matching: find.text('+ # Meu')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: diff,
        matching: find.text('− # Sessões com stream-json'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('specs-unsaved-keep')));
    await settleIo(
      tester,
      until: () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(editorText(tester), draft);
    expect(find.byKey(const ValueKey('spec-unsaved')), findsOneWidget);
    expect(file().readAsStringSync(), sample);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Carregar do disco" discards the unsaved text (R9)', (
    tester,
  ) async {
    final draft = sample.replaceFirst('# Sessões com stream-json', '# Meu');
    final (c, _, spec) = await pump(tester, draft: draft);
    await tester.tap(find.byKey(const ValueKey('specs-unsaved-disk')));
    await settleIo(
      tester,
      until: () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(editorText(tester), sample);
    expect(find.byKey(const ValueKey('spec-unsaved')), findsNothing);
    expect(c.read(specUnsavedProvider)[spec.id], isNull);
    expect(file().readAsStringSync(), sample);
  });

  testWidgets('closing the dialog (Esc) keeps the editor text: nothing is '
      'overwritten without confirmation (R9)', (tester) async {
    final draft = sample.replaceFirst('# Sessões com stream-json', '# Meu');
    await pump(tester, draft: draft);
    expect(dialog, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleIo(
      tester,
      until: () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(dialog, findsNothing);
    expect(editorText(tester), draft);
    expect(file().readAsStringSync(), sample);
  });

  testWidgets('a draft equal to the file asks nothing (R9)', (tester) async {
    await pump(tester, draft: sample);
    expect(dialog, findsNothing);
    expect(editorText(tester), sample);
    expect(find.byKey(const ValueKey('spec-unsaved')), findsNothing);
  });
}
