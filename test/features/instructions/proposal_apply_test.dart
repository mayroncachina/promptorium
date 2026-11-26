import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/providers/instructions_files.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/features/instructions/interview_data.dart';
import 'package:promptorium/features/instructions/proposal_apply.dart';

const agents =
    '# vitrine\n\n'
    '## Comandos\n'
    '- Testes: `flutter test`.\n'
    '- Analisar: `flutter analyze`.\n\n'
    '## Regras\n'
    '- Textos em português do Brasil.\n';

const claude = '@AGENTS.md\n\n- Responda curto.\n';

InstructionProposalHunk hunk(
  String section,
  String oldText,
  String newText, {
  String file = 'AGENTS.md',
  List<String> questions = const ['Q1'],
}) => InstructionProposalHunk(
  file: file,
  section: section,
  oldText: oldText,
  newText: newText,
  questions: questions,
);

/// A real temporary repository: `main` with the two files and a README.
Future<String> repo(Directory tmp) async {
  final root = tmp.path;
  Future<void> git(List<String> args) async {
    final r = await Process.run('git', ['-C', root, ...args]);
    if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
  }

  await git(['init', '-q', '-b', 'main']);
  await git(['config', 'user.email', 'teste@example.com']);
  await git(['config', 'user.name', 'Teste']);
  await git(['config', 'commit.gpgsign', 'false']);
  await git(['config', 'core.hooksPath', '.git/hooks']);
  File('$root/AGENTS.md').writeAsStringSync(agents);
  File('$root/CLAUDE.md').writeAsStringSync(claude);
  File('$root/README.md').writeAsStringSync('# r\n');
  await git(['add', '-A']);
  await git(['commit', '-q', '-m', 'inicial']);
  return root;
}

Future<String> gitOut(String root, List<String> args) async =>
    '${(await Process.run('git', ['-C', root, ...args])).stdout}'.trim();

void main() {
  group('applyHunkText', () {
    test('replaces the old text inside its section', () {
      final out = applyHunkText(
        agents,
        hunk(
          'Comandos',
          '- Testes: `flutter test`.',
          '- Testes: `flutter test test/<area>`; a suíte inteira só no CI.',
        ),
      );
      expect(
        out,
        contains(
          '## Comandos\n- Testes: `flutter test test/<area>`; a suíte '
          'inteira só no CI.\n- Analisar',
        ),
      );
    });

    test('an insertion goes to the end of its section', () {
      final out = applyHunkText(
        agents,
        hunk('Comandos', '', '- Antes de commitar: `flutter analyze`.'),
      )!;
      expect(
        out,
        contains(
          '- Analisar: `flutter analyze`.\n'
          '- Antes de commitar: `flutter analyze`.\n\n## Regras',
        ),
      );
    });

    test('a new section goes to the end of the file, with its heading', () {
      final h = hunk('Não mexer', '', '- Não edite `lib/x.g.dart`.');
      expect(isNewSection(agents, h), isTrue);
      final out = applyHunkText(agents, h)!;
      expect(
        out,
        endsWith(
          '- Textos em português do Brasil.\n\n'
          '## Não mexer\n- Não edite `lib/x.g.dart`.\n',
        ),
      );
      // The new text brings its own heading: no second one.
      final own = applyHunkText(
        agents,
        hunk('Não mexer', '', '## Não mexer\n- Nada.'),
      )!;
      expect('## Não mexer'.allMatches(own), hasLength(1));
    });

    test('an old text no longer in the file is a conflict', () {
      expect(
        applyHunkText(agents, hunk('Comandos', '- Testes: `npm test`.', 'x')),
        isNull,
      );
      expect(applyHunkText(null, hunk('Comandos', 'a', 'b')), isNull);
    });
  });

  group('planProposal (R19)', () {
    test('the CLAUDE.md keeps its @AGENTS.md line', () {
      final plan = planProposal(
        {'AGENTS.md': agents, 'CLAUDE.md': claude},
        [
          hunk(
            'Só para o Claude Code',
            '',
            '- Em mudança de banco, comece no modo plan.',
            file: 'CLAUDE.md',
          ),
        ],
      );
      expect(plan.changed, ['CLAUDE.md']);
      final out = plan.after['CLAUDE.md']!;
      expect(out, startsWith('@AGENTS.md\n\n'));
      expect(hasAgentsImport(out), isTrue);
      expect(
        out,
        '@AGENTS.md\n\n- Responda curto.\n'
        '- Em mudança de banco, comece no modo plan.\n',
      );
    });

    test('a trecho of another file is never applied', () {
      final plan = planProposal(
        {'AGENTS.md': agents},
        [hunk('x', '', 'y', file: 'lib/main.dart')],
      );
      expect(plan.conflicts, {0: ProposalConflictKind.otherFile});
      expect(plan.changed, isEmpty);
    });
  });

  test('lineDelta counts added and removed lines', () {
    expect(lineDelta('a\nb\nc\n', 'a\nB\nc\nd\n'), (added: 2, removed: 1));
    expect(lineDelta(null, 'a\n'), (added: 1, removed: 0));
    expect(lineDelta('a\n', 'a\n'), (added: 0, removed: 0));
  });

  group('R20 · citedPaths', () {
    test('only inline code with a folder or an extension', () {
      expect(
        citedPaths([
          '- Não edite `lib/data/db/*.g.dart` nem `packages/legado/`.\n'
              '- Rode `flutter test test/<area>` e `flutter analyze`; veja '
              '`ci.yml`, `0.28.0`, `https://x.dev/a` e `./AGENTS.md`.',
        ]),
        ['lib/data/db/*.g.dart', 'packages/legado', 'ci.yml', 'AGENTS.md'],
      );
    });

    test('checks files, folders, globs and bare names', () async {
      final tmp = Directory.systemTemp.createTempSync('cited-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      Directory('${tmp.path}/lib/data/db').createSync(recursive: true);
      File('${tmp.path}/lib/data/db/app.g.dart').writeAsStringSync('');
      Directory('${tmp.path}/.github/workflows').createSync(recursive: true);
      File('${tmp.path}/.github/workflows/ci.yml').writeAsStringSync('');
      Directory('${tmp.path}/packages/legado').createSync(recursive: true);
      final checked = await checkCitedPaths(tmp.path, [
        hunk(
          'Regras',
          '',
          '- `lib/data/db/*.g.dart`, `packages/legado`, `ci.yml`, '
              '`lib/nao/existe.dart`, `lib/*/nada.dart`.',
        ),
      ]);
      expect(
        {for (final c in checked) c.path: c.exists},
        {
          'lib/data/db/*.g.dart': true,
          'packages/legado': true,
          'ci.yml': true,
          'lib/nao/existe.dart': false,
          'lib/*/nada.dart': false,
        },
      );
    });
  });

  group('applyInstructionProposal (R19, R21)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('proposal-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writes only the accepted trechos; a conflict is not written, and '
        '"Desfazer" puts the files back', () async {
      final root = await repo(tmp);
      final result = await applyInstructionProposal(
        root: root,
        hunks: [
          hunk('Regras', '', '- Tela nova leva teste de widget.'),
          hunk('Comandos', '- Testes: `npm test`.', '- Testes: `x`.'),
        ],
      );
      expect(result.conflicts, {1: ProposalConflictKind.notFound});
      expect(result.changed, ['AGENTS.md']);
      final now = File('$root/AGENTS.md').readAsStringSync();
      expect(now, contains('- Tela nova leva teste de widget.'));
      expect(now, isNot(contains('`x`')));
      expect(File('$root/CLAUDE.md').readAsStringSync(), claude);
      expect(result.commitSha, isNull);
      // No commit unless asked.
      expect(await gitOut(root, ['rev-list', '--count', 'HEAD']), '1');

      await undoInstructionWrite(result.write!);
      expect(File('$root/AGENTS.md').readAsStringSync(), agents);
    });

    test('only conflicts: nothing is written', () async {
      final root = await repo(tmp);
      final result = await applyInstructionProposal(
        root: root,
        hunks: [hunk('Comandos', 'nada disso', 'x')],
      );
      expect(result.wrote, isFalse);
      expect(result.conflicts.keys, [0]);
      expect(File('$root/AGENTS.md').readAsStringSync(), agents);
    });

    test('R21: commits only the instruction files on the current branch, '
        'without switching branch; other dirty files stay out', () async {
      final root = await repo(tmp);
      await gitOut(root, ['checkout', '-q', '-b', 'ajuste-carrinho']);
      // Other changes: one staged, one only in the tree, one untracked.
      File('$root/README.md').writeAsStringSync('# mudou\n');
      await gitOut(root, ['add', 'README.md']);
      File('$root/novo.txt').writeAsStringSync('x\n');
      final git = GitService(root);
      final result = await applyInstructionProposal(
        root: root,
        hunks: [
          hunk('Regras', '', '- Tela nova leva teste de widget.'),
          hunk(
            'Só para o Claude Code',
            '',
            '- Modo plan em banco.',
            file: 'CLAUDE.md',
          ),
        ],
        commit: true,
        git: git,
      );
      expect(result.commitError, isNull);
      expect(result.commitSha, isNotNull);
      expect(result.branch, 'ajuste-carrinho');
      expect(await git.currentBranch(), 'ajuste-carrinho');
      expect(
        await gitOut(root, ['log', '-1', '--format=%s']),
        'docs: instruções dos agentes',
      );
      final files = await gitOut(root, [
        'show',
        '--name-only',
        '--format=',
        'HEAD',
      ]);
      expect(files.split('\n')..sort(), ['AGENTS.md', 'CLAUDE.md']);
      // main did not move.
      expect(await gitOut(root, ['rev-list', '--count', 'main']), '1');
      // The other changes are where they were.
      final status = await gitOut(root, ['status', '--porcelain']);
      expect(status, contains('M  README.md'));
      expect(status, contains('?? novo.txt'));
      expect(status, isNot(contains('AGENTS.md')));
      expect(status, isNot(contains('CLAUDE.md')));
      // No remote, no push.
      expect(await gitOut(root, ['remote']), isEmpty);
    });

    test('R21: a new AGENTS.md (untracked) goes into the commit', () async {
      final root = await repo(tmp);
      await gitOut(root, ['rm', '-q', 'AGENTS.md']);
      await gitOut(root, ['commit', '-q', '-m', 'sem agents']);
      final result = await applyInstructionProposal(
        root: root,
        hunks: [hunk('Regras', '', '- Uma regra.')],
        commit: true,
        git: GitService(root),
      );
      expect(result.commitSha, isNotNull);
      expect(
        await gitOut(root, ['show', '--name-only', '--format=', 'HEAD']),
        'AGENTS.md',
      );
    });

    test('R21: HEAD solto refuses the commit before writing', () async {
      final root = await repo(tmp);
      await gitOut(root, ['checkout', '-q', '--detach']);
      await expectLater(
        applyInstructionProposal(
          root: root,
          hunks: [hunk('Regras', '', '- Uma regra.')],
          commit: true,
          git: GitService(root),
        ),
        throwsA(isA<InstructionsException>()),
      );
      expect(File('$root/AGENTS.md').readAsStringSync(), agents);
    });
  });

  group('readCommitTarget (R21)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('target-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('on the base: no warning', () async {
      final root = await repo(tmp);
      final t = await readCommitTarget(root, GitService(root));
      expect(t.isRepo, isTrue);
      expect(t.branch, 'main');
      expect(t.base, 'main');
      expect(t.canCommit, isTrue);
      expect(t.offBase, isFalse);
    });

    test('off the base (the configured branch-base wins)', () async {
      final root = await repo(tmp);
      await gitOut(root, ['checkout', '-q', '-b', 'ajuste-carrinho']);
      var t = await readCommitTarget(root, GitService(root));
      expect(t.offBase, isTrue);
      expect(t.base, 'main');
      Directory('$root/.promptorium').createSync();
      File('$root/.promptorium/config.yml')
          .writeAsStringSync('branch-base: ajuste-carrinho\n');
      t = await readCommitTarget(root, GitService(root));
      expect(t.base, 'ajuste-carrinho');
      expect(t.offBase, isFalse);
    });

    test(
      'HEAD solto and no repository: the box is off, with the reason',
      () async {
        final root = await repo(tmp);
        await gitOut(root, ['checkout', '-q', '--detach']);
        final t = await readCommitTarget(root, GitService(root));
        expect(t.canCommit, isFalse);
        expect(t.disabledReason, startsWith('HEAD solto'));

        final plain = Directory.systemTemp.createTempSync('norepo-');
        addTearDown(() => plain.deleteSync(recursive: true));
        final n = await readCommitTarget(plain.path, GitService(plain.path));
        expect(n.isRepo, isFalse);
        expect(n.disabledReason, 'O projeto não é um repositório git.');
      },
    );
  });
}
