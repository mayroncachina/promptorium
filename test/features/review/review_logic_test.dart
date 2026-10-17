import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart' show GitLogEntry;
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
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

  test('splitPairs: context on both sides, removed next to added', () {
    final f = DiffParser.parse(
      'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,4 +1,4 @@\n'
      ' a\n-b\n-c\n+B\n d\n+e\n',
    ).single;
    final pairs = splitPairs(f.hunks.single);
    String side((int, DiffLine)? l) => l?.$2.text ?? '·';
    expect(
      [for (final (l, r) in pairs) '${side(l)}|${side(r)}'],
      ['a|a', 'b|B', 'c|·', 'd|d', '·|e'],
    );
  });

  test('commitsByStep and gh pr checks', () {
    GitLogEntry e(String s) => GitLogEntry(
      sha: s,
      shortSha: s,
      author: '',
      date: DateTime(2026),
      subject: s,
    );
    final m = commitsByStep('SPEC-003', [
      e('SPEC-003 R1: a'),
      e('SPEC-003 R2, R3: b'),
      e('outra coisa R1'),
      e('SPEC-003 REV1: c'),
      e('SPEC-003: spec concluída R9'),
    ]);
    expect(m.keys, ['R1', 'R2', 'R3', 'REV1']);
    expect(m['R2']!.single.subject, 'SPEC-003 R2, R3: b');
    expect(parsePrChecks('a\tpass\t1s\n\nb\tpending\n'), [
      ('a', 'pass'),
      ('b', 'pending'),
    ]);
  });

  test('gh pr view --json: comments and review bodies in time order, '
      'checks, summary', () {
    final st = parsePrView('''
{"state":"OPEN","mergeable":"MERGEABLE","reviewDecision":"APPROVED",
 "comments":[{"author":{"login":"b"},"body":"depois","createdAt":"2026-10-17T10:05:00Z"}],
 "reviews":[{"author":{"login":"a"},"body":"antes","state":"COMMENTED","submittedAt":"2026-10-17T10:00:00Z"},
            {"author":{"login":"c"},"body":"","state":"APPROVED","submittedAt":"2026-10-17T10:06:00Z"}],
 "statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"},{"context":"lint","state":"PENDING"}]}
''')!;
    expect(st.comments.map((c) => c.author), ['a', 'b']);
    expect(st.comments.first.kind, 'review: COMMENTED');
    expect(st.checks, [('ci', 'SUCCESS'), ('lint', 'PENDING')]);
    expect(
      st.summary,
      'aberto · 1 check(s) rodando · aprovado · 2 comentário(s)',
    );
    expect(parsePrView('não é json'), isNull);
    expect(
      prCommentsMessage(st.comments),
      contains('@b (comentário):\ndepois'),
    );
  });
}
