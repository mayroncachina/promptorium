import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/code/code_panels.dart';
import 'package:promptorium/ui/shell/notification_center.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';

void main() {
  test('problems: generic file:line:col and the dart analyze format', () {
    final p = parseProblems('''
Analyzing app...
   info • Unused import • lib/a.dart:3:8 • unused_import
warning • Dead code • /r/lib/b.dart:10:1 • dead_code
src/x.py:12:5: E501 line too long
/r/src/y.ts:7: error: Cannot find name
not a problem line
3 issues found.
''', '/r');
    expect(p.map((x) => '${x.severity} ${x.path}:${x.line}'), [
      'info lib/a.dart:3',
      'aviso lib/b.dart:10',
      'erro src/x.py:12',
      'erro src/y.ts:7',
    ]);
    expect(p.first.message, 'Unused import');
    expect(p[2].column, 5);
  });

  test('search: rg --json lines and the Dart fallback', () async {
    final rg = [
      jsonEncode({'type': 'begin', 'data': {}}),
      jsonEncode({
        'type': 'match',
        'data': {
          'path': {'text': './lib/a.dart'},
          'line_number': 4,
          'lines': {'text': '  final ola = 1;\n'},
        },
      }),
    ].join('\n');
    final hits = parseRipgrepJson(rg, '/r');
    expect(hits.single.path, 'lib/a.dart');
    expect(hits.single.line, 4);
    expect(hits.single.text, '  final ola = 1;');

    final tmp = Directory.systemTemp.createTempSync('promptorium-search-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/a.txt').writeAsStringSync('um\nOla mundo\nfim\n');
    File('${tmp.path}/b.txt').writeAsStringSync('ola\n');
    final found = await searchWorktree(tmp.path, 'ola', [
      'a.txt',
      'b.txt',
    ], useRipgrep: false);
    expect(found.map((h) => '${h.path}:${h.line}'), ['a.txt:2', 'b.txt:1']);
    // Smart case: an upper-case query is exact.
    expect(
      await searchWorktree(tmp.path, 'Ola', [
        'a.txt',
        'b.txt',
      ], useRipgrep: false),
      hasLength(1),
    );
  });

  test('git panel: status, stage, unstage, commit; lint on demand', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-gitpanel-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    File('$repo/novo.txt').writeAsStringSync('x');
    File('$repo/a.txt').writeAsStringSync('mudou\n');
    c.listen(gitPanelProvider(repo), (_, _) {});
    final n = c.read(gitPanelProvider(repo).notifier);
    await n.refresh();
    var s = c.read(gitPanelProvider(repo));
    expect(s.branch, 'main');
    expect(s.entries.map((e) => '${e.x}${e.y} ${e.path}'), [
      ' M a.txt',
      '?? novo.txt',
    ]);
    await n.stage('novo.txt');
    s = c.read(gitPanelProvider(repo));
    expect(s.entries.firstWhere((e) => e.path == 'novo.txt').x, 'A');
    await n.unstage('novo.txt');
    expect(
      c
          .read(gitPanelProvider(repo))
          .entries
          .firstWhere((e) => e.path == 'novo.txt')
          .x,
      '?',
    );
    await n.stage('a.txt');
    await n.commit('só a.txt');
    s = c.read(gitPanelProvider(repo));
    expect(s.error, isNull);
    expect(s.entries.map((e) => e.path), ['novo.txt']);
    expect(
      (await gitIn(repo, ['log', '-1', '--format=%s'])).trim(),
      'só a.txt',
    );
    await n.commit('');
    expect(c.read(gitPanelProvider(repo)).error, contains('mensagem'));

    Directory('$repo/.promptorium').createSync();
    File('$repo/.promptorium/config.yml')
        .writeAsStringSync('lint: "echo lib/a.dart:2:1: erro de teste"\n');
    c.listen(problemsProvider(repo), (_, _) {});
    await c.read(problemsProvider(repo).notifier).run(repo);
    final problems = c.read(problemsProvider(repo)).problems;
    expect(problems.single.path, 'lib/a.dart');
    expect(problems.single.message, 'erro de teste');
  });

  testWidgets('notification center: unread badge, history and "Ir para"', (
    tester,
  ) async {
    final db = memoryDatabase();
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(c.dispose);
    await tester.runAsync(
      () => c
          .read(notificationsRepoProvider)
          .add(
            title: 'Sessão concluída',
            body: 'SPEC-001 · R1',
            section: 'review',
            sessionId: 's1',
          ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: Center(child: NotificationBell())),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('notifications-unread')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notifications-open')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.text('Sessão concluída'), findsOneWidget);
    await tester.tap(find.text('Ir para'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(c.read(navigationProvider), AppSection.review);
    expect(find.byKey(const ValueKey('notifications-unread')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
