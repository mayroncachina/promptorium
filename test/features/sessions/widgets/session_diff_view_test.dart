import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/sessions/session_changes.dart';
import 'package:promptorium/features/sessions/widgets/diff_raw_views.dart';

import '../../../core/git/git_test_utils.dart';

/// SPEC-111: the Diff tab of a session whose work was committed shows the
/// lines of the turn (and the loose ones), and names the measure.
void main() {
  Future<void> pump(WidgetTester tester, SessionChanges changes) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionChangesProvider.overrideWith((ref, id) async => changes),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SessionDiffView(sessionId: 's1')),
          ),
        ),
      );

  testWidgets('a committed turn plus a loose file: the Diff lists both, '
      'with the lines, measured from the base branch', (tester) async {
    final changes = await tester.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('diff-111-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = await createRepo(tmp);
      final wt = '${tmp.path}/wt';
      await gitIn(root, ['worktree', 'add', '-q', wt, '-b', 'sessao']);
      File('$wt/ledger.txt').writeAsStringSync('linha commitada\n');
      await gitIn(wt, ['add', '-A']);
      await gitIn(wt, ['commit', '-q', '-m', 'turno']);
      File('$wt/a.txt')
          .writeAsStringSync('linha solta\n', mode: FileMode.append);
      File('$wt/novo.txt').writeAsStringSync('x\n');
      return loadSessionChanges(GitService(wt), baseBranch: 'main');
    });
    await pump(tester, changes!);
    await tester.pumpAndSettle();
    expect(find.text('3 arquivo(s) alterado(s) · desde main'), findsOneWidget);
    expect(find.text('+ linha commitada'), findsOneWidget);
    expect(find.text('+ linha solta'), findsOneWidget);
    expect(find.text('novo.txt  (novo, não rastreado)'), findsOneWidget);
    expect(find.text('Nenhuma alteração no worktree.'), findsNothing);
  });

  testWidgets('a session in the project root keeps "git diff HEAD"', (
    tester,
  ) async {
    final changes = await tester.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('diff-111-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = await createRepo(tmp);
      File('$root/a.txt').writeAsStringSync('solta\n', mode: FileMode.append);
      return loadSessionChanges(GitService(root));
    });
    await pump(tester, changes!);
    await tester.pumpAndSettle();
    expect(
      find.text('1 arquivo(s) alterado(s) · git diff HEAD'),
      findsOneWidget,
    );
  });
}
