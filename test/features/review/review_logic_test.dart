import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/review/review_logic.dart';

const sampleDiff = '''
diff --git a/lib/ui/status_bar.dart b/lib/ui/status_bar.dart
index 1111111..2222222 100644
--- a/lib/ui/status_bar.dart
+++ b/lib/ui/status_bar.dart
@@ -5,4 +5,5 @@ class StatusBar extends StatelessWidget {
   final SessionStats stats;

-  static const _bg = Color(0xFF14171D);
+  @override
+  Widget build(BuildContext context) => const SizedBox();
 }
''';

Session session({
  String id = 's1',
  SessionStatus status = SessionStatus.completed,
  int? taskId,
  String worktree = '/wt',
  String? mergeCommit,
  DateTime? startedAt,
}) => Session(
  id: id,
  workspaceId: 1,
  taskId: taskId,
  agentName: 'implementer',
  title: 'Barra de status',
  worktreePath: worktree,
  branch: 'pr/status-bar',
  status: status,
  model: 'sonnet',
  costUsd: 0,
  tokensIn: 0,
  tokensOut: 0,
  startedAt: startedAt ?? DateTime(2026, 10, 15),
  baseBranch: 'main',
  mergeCommit: mergeCommit,
);

Task task({int id = 1, TaskStatus status = TaskStatus.review}) => Task(
  id: id,
  workspaceId: 1,
  code: 'TASK-011',
  title: 'Barra de status',
  status: status,
  dependsOn: const [],
  createdAt: DateTime(2026),
  requirement: 'R1',
);

void main() {
  test('isAwaitingReview', () {
    bool f(Session s, Task? t, {bool wt = true, bool changes = true}) =>
        isAwaitingReview(
          session: s,
          task: t,
          hasWorktree: wt,
          hasChanges: changes,
        );
    expect(f(session(), null), isTrue);
    expect(f(session(), null, changes: false), isFalse);
    expect(f(session(), null, wt: false), isFalse);
    expect(f(session(status: SessionStatus.running), task()), isFalse);
    // Task in Review: listed even if the session stopped / no changes.
    expect(
      f(session(status: SessionStatus.stopped), task(), changes: false),
      isTrue,
    );
    expect(f(session(status: SessionStatus.stopped), null), isFalse);
    expect(f(session(status: SessionStatus.merged), task()), isFalse);
    expect(f(session(), task(status: TaskStatus.done)), isFalse);
  });

  test('comment message: `arquivo:linha — comentário` + snippet, one '
      'message for every comment', () {
    final file = DiffParser.parse(sampleDiff).single;
    final h = file.hunks.single;
    final add = h.lines.indexWhere((l) => l.text.contains('Widget build'));
    final del = h.lines.indexWhere((l) => l.kind == DiffLineKind.del);
    final c1 = commentFor(file, h, add, '  Use o tema do app.  ');
    final c2 = commentFor(file, h, del, 'Mantenha a constante.');
    expect(c1.location, 'lib/ui/status_bar.dart:8');
    expect(c1.text, 'Use o tema do app.');
    expect(c1.snippet, [
      '-  static const _bg = Color(0xFF14171D);',
      '+  @override',
      '+  Widget build(BuildContext context) => const SizedBox();',
    ]);
    expect(c2.location, 'lib/ui/status_bar.dart:7 (linha removida)');
    final msg = adjustmentMessage([c1, c2], note: 'Rode os testes.');
    expect(
      msg,
      'Revisão do código: ajustes pedidos.\n'
      '\n'
      'Rode os testes.\n'
      '\n'
      'lib/ui/status_bar.dart:8 — Use o tema do app.\n'
      '```\n'
      '-  static const _bg = Color(0xFF14171D);\n'
      '+  @override\n'
      '+  Widget build(BuildContext context) => const SizedBox();\n'
      '```\n'
      '\n'
      'lib/ui/status_bar.dart:7 (linha removida) — Mantenha a constante.\n'
      '```\n'
      '   final SessionStats stats;\n'
      ' \n'
      '-  static const _bg = Color(0xFF14171D);\n'
      '```\n'
      '\n'
      'Faça os ajustes no worktree, rode os testes e resuma o que mudou.',
    );
  });
}
