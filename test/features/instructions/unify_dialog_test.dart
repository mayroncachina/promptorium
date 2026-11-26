import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/instructions_files.dart';
import 'package:promptorium/features/instructions/unify_dialog.dart';
import 'package:promptorium/features/instructions/unify_service.dart';

import 'unify_service_test.dart' show vitrineAgents, vitrineClaude;

/// Fails the `rename` of the CLAUDE.md: the second file of the Unificar.
class _FailClaude extends InstructionsFs {
  const _FailClaude();

  @override
  Future<void> replace(File tmp, String target) async {
    if (target.endsWith('/CLAUDE.md')) {
      throw const FileSystemException('disco cheio');
    }
    return super.replace(tmp, target);
  }
}

void main() {
  late Directory dir;
  late File claude;
  late File agents;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('promptorium-unify-dialog-');
    claude = File('${dir.path}/CLAUDE.md')..writeAsStringSync(vitrineClaude);
    agents = File('${dir.path}/AGENTS.md')..writeAsStringSync(vitrineAgents);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Real file IO completes outside the fake clock: lets it run, in small
  /// real steps, until [done] (up to 20 s).
  Future<void> io(WidgetTester tester, bool Function() done) async {
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (!done() && DateTime.now().isBefore(until)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool shown(Finder f) => f.evaluate().isNotEmpty;
  final dialog = find.byKey(const ValueKey('unify-dialog'));
  final error = find.byKey(const ValueKey('unify-error'));

  Future<void> open(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showUnifyDialog(context, ref, workspacePath: dir.path),
                child: const Text('Unificar instruções'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Unificar instruções'));
    await io(tester, () => shown(dialog) || shown(find.byType(SnackBar)));
  }

  Finder inPreview(String key, String text) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));

  const printLine = '- Nunca use `print`; use o logger.';
  const testerLine =
      '- Use o subagente `tester` depois de mudar `packages/api`.';

  testWidgets('shows both files before writing; the choices change the '
      'result; confirm writes both and Desfazer puts them back', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const ValueKey('unify-dialog')), findsOneWidget);
    expect(find.text('DIFERENÇAS · 3'), findsOneWidget);
    // The result is on screen and nothing was written yet (R4).
    expect(inPreview('unify-agents-preview', printLine), findsOneWidget);
    expect(inPreview('unify-claude-preview', '@AGENTS.md'), findsOneWidget);
    expect(inPreview('unify-claude-preview', testerLine), findsOneWidget);
    expect(claude.readAsStringSync(), vitrineClaude);
    expect(agents.readAsStringSync(), vitrineAgents);

    // "Nunca use print" stays in the CLAUDE.md instead.
    await tester.tap(find.byKey(const ValueKey('unify-target-d2-claudeOnly')));
    await tester.pump();
    expect(inPreview('unify-agents-preview', printLine), findsNothing);
    expect(inPreview('unify-claude-preview', printLine), findsOneWidget);
    // The AGENTS.md version of the test command.
    await tester.tap(
      find.byKey(const ValueKey('unify-target-d1-agentsVersion')),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('unify-confirm')));
    await io(tester, () => !shown(dialog));
    expect(find.byKey(const ValueKey('unify-dialog')), findsNothing);
    final writtenAgents = agents.readAsStringSync();
    expect(writtenAgents, contains('- Testes: `flutter test`.'));
    expect(writtenAgents, isNot(contains('print')));
    final writtenClaude = claude.readAsStringSync();
    expect(writtenClaude, startsWith('@AGENTS.md\n'));
    expect(writtenClaude, contains(printLine));
    expect(writtenClaude, contains(testerLine));

    expect(find.byKey(const ValueKey('unify-toast')), findsOneWidget);
    await tester.tap(find.text('Desfazer'));
    await io(tester, () => shown(find.textContaining('Unificação desfeita')));
    expect(claude.readAsStringSync(), vitrineClaude);
    expect(agents.readAsStringSync(), vitrineAgents);
    expect(find.textContaining('Unificação desfeita'), findsOneWidget);
  });

  testWidgets('a failure in the second file puts the first back (R5)', (
    tester,
  ) async {
    await open(
      tester,
      overrides: [
        unifyWriterProvider.overrideWithValue(
          (writes) => writeInstructionFiles(writes, fs: const _FailClaude()),
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('unify-confirm')));
    await io(tester, () => shown(error));
    expect(find.byKey(const ValueKey('unify-dialog')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('unify-error'))).data,
      contains('CLAUDE.md'),
    );
    expect(agents.readAsStringSync(), vitrineAgents);
    expect(claude.readAsStringSync(), vitrineClaude);
    expect(dir.listSync(), hasLength(2), reason: 'no temporary file left');
  });

  testWidgets('a file changed on disk after the reading is not written', (
    tester,
  ) async {
    await open(tester);
    claude.writeAsStringSync('# mudou fora\n');
    await tester.tap(find.byKey(const ValueKey('unify-confirm')));
    await io(tester, () => shown(error));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('unify-error'))).data,
      contains('mudou no disco'),
    );
    expect(agents.readAsStringSync(), vitrineAgents);
    expect(claude.readAsStringSync(), '# mudou fora\n');
  });

  testWidgets('Pedir ajuda da IA suggests without deciding', (tester) async {
    var asked = 0;
    await open(
      tester,
      overrides: [
        unifySuggesterProvider.overrideWithValue((plan, {required cwd}) async {
          asked++;
          expect(cwd, dir.path);
          return {
            'd2': const UnifySuggestion(
              target: UnifyTarget.claudeOnly,
              reason: 'regra do Claude',
            ),
          };
        }),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('unify-ai')));
    await tester.pump();
    await tester.pump();
    expect(asked, 1);
    expect(find.byKey(const ValueKey('unify-suggestion-d2')), findsOneWidget);
    expect(find.textContaining('regra do Claude'), findsOneWidget);
    // Not applied by itself.
    expect(inPreview('unify-agents-preview', printLine), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('unify-use-d2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('unify-use-d2')));
    await tester.pump();
    expect(inPreview('unify-agents-preview', printLine), findsNothing);
    expect(inPreview('unify-claude-preview', printLine), findsOneWidget);
    expect(claude.readAsStringSync(), vitrineClaude);
  });

  testWidgets('already unified: says so and opens nothing (R3)', (
    tester,
  ) async {
    claude.writeAsStringSync('@AGENTS.md\n');
    await open(tester);
    expect(find.byKey(const ValueKey('unify-dialog')), findsNothing);
    expect(find.text('As instruções já estão unificadas.'), findsOneWidget);
    expect(claude.readAsStringSync(), '@AGENTS.md\n');
  });
}
