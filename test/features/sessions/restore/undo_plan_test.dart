import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/sessions/restore/restore_point.dart';

/// SPEC-084 R6, R7, R12, R16: what the undo dialog shows, from the two
/// points of the turn.
void main() {
  TreeChange m(String p, {int a = 1, int r = 1}) =>
      TreeChange(path: p, kind: TreeChangeKind.modified, added: a, removed: r);
  TreeChange c(String p) => TreeChange(path: p, kind: TreeChangeKind.created);
  TreeChange d(String p) => TreeChange(path: p, kind: TreeChangeKind.deleted);
  GitLogEntry log(String sha, String subject) => GitLogEntry(
    sha: sha,
    shortSha: sha.substring(0, 7),
    author: 'agente',
    date: DateTime(2026, 11, 17),
    subject: subject,
  );

  test('the agent files come checked, created ones will be deleted and '
      'deleted ones come back', () {
    final plan = buildUndoPlan(
      turn: [
        m('src/checkout.ts', a: 12, r: 12),
        c('src/order.ts'),
        d('src/pedido.ts'),
      ],
    );
    expect(plan.restore.map((f) => f.path), [
      'src/checkout.ts',
      'src/order.ts',
      'src/pedido.ts',
    ]);
    expect(plan.restore.every((f) => f.checkedByDefault), isTrue);
    expect(plan.restore[1].kind, TreeChangeKind.created);
    expect(plan.restore[2].kind, TreeChangeKind.deleted);
    expect(plan.restore.first.added, 12);
    expect(plan.defaultSelection, hasLength(3));
    expect(plan.changedAfter, isEmpty);
  });

  test('a file the person changed after the turn comes unchecked with when; '
      'one saved through Código during the turn stays checked with its '
      'label', () {
    final at = DateTime(2026, 11, 17, 14, 9);
    final plan = buildUndoPlan(
      turn: [m('src/checkout.spec.ts'), m('src/api/rotas.ts')],
      after: [m('src/checkout.spec.ts'), m('src/so-da-pessoa.ts')],
      editedDuring: {'src/api/rotas.ts'},
      editedAt: {'src/checkout.spec.ts': at},
    );
    expect(plan.changedAfter.single.path, 'src/checkout.spec.ts');
    expect(plan.changedAfter.single.checkedByDefault, isFalse);
    expect(plan.changedAfter.single.editedAt, at);
    expect(plan.restore.single.path, 'src/api/rotas.ts');
    expect(plan.restore.single.userDuring, isTrue);
    expect(plan.defaultSelection, {'src/api/rotas.ts'});
    // A file only the person changed after the turn is never in the plan.
    expect(
      plan.allFiles.map((f) => f.path),
      isNot(contains('src/so-da-pessoa.ts')),
    );
  });

  test('a file the turn did not touch is out, even if it was dirty at the '
      'start (it stays as it is)', () {
    final plan = buildUndoPlan(
      turn: [m('src/pedido.ts')],
      kept: ['src/cupom.ts', 'src/pedido.ts'],
    );
    expect(plan.allFiles.map((f) => f.path), ['src/pedido.ts']);
    expect(plan.kept, ['src/cupom.ts']);
  });

  test('commits thrown away; pushed ones switch to files only', () {
    final local = buildUndoPlan(
      turn: [m('a')],
      commits: [log('a1b2c3d4e5', 'wip: renomeia Pedido')],
    );
    expect(local.commits.single.subject, 'wip: renomeia Pedido');
    expect(local.commits.single.shortSha, 'a1b2c3d');
    expect(local.filesOnly, isFalse);

    final sent = buildUndoPlan(
      turn: [m('a')],
      commits: [log('7c6d5e4f00', 'wip'), log('1111111aaa', 'antes')],
      pushed: {'7c6d5e4f00'},
      remotes: ['origin/feat/order'],
    );
    expect(sent.filesOnly, isTrue);
    expect(sent.pushedCommits.single.shortSha, '7c6d5e4');
    expect(sent.remotes, ['origin/feat/order']);
  });

  test('what does not come back: ignored and big files', () {
    final plan = buildUndoPlan(
      turn: [m('a')],
      ignored: ['.env'],
      large: ['dump.sql'],
    );
    expect(plan.notRestored.map((n) => '${n.path}: ${n.reason}'), [
      '.env: ignorado pelo .gitignore',
      'dump.sql: grande demais, fora do ponto',
    ]);
  });

  test('another live session in the same folder: the files both changed', () {
    final plan = buildUndoPlan(
      turn: [m('src/checkout/checkout.css'), m('src/ui/botao.css'), m('x.ts')],
      others: {
        'Ajustar CSS': {'src/checkout/checkout.css', 'src/ui/botao.css', 'z'},
      },
    );
    expect(plan.others.single.title, 'Ajustar CSS');
    expect(plan.others.single.files, [
      'src/checkout/checkout.css',
      'src/ui/botao.css',
    ]);
    expect(plan.restore.first.otherSessions, ['Ajustar CSS']);
    expect(plan.restore.last.otherSessions, isEmpty);
  });

  test('branch changed in the turn and an empty plan', () {
    final plan = buildUndoPlan(
      turn: const [],
      startBranch: 'main',
      currentBranch: 'feat/order',
    );
    expect(plan.branchChanged, isTrue);
    expect(plan.isEmpty, isTrue);
  });
}
