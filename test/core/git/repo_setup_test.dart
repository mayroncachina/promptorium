import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_root.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/git/repo_setup.dart';

import 'git_test_utils.dart';

/// Real git with a fixed identity and no signing (independent of the
/// machine's global config).
Future<ProcessResult> gitRun(String exe, List<String> args) => Process.run(
  exe,
  args,
  environment: const {
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_AUTHOR_NAME': 'Teste',
    'GIT_AUTHOR_EMAIL': 'teste@example.com',
    'GIT_COMMITTER_NAME': 'Teste',
    'GIT_COMMITTER_EMAIL': 'teste@example.com',
    'GIT_CONFIG_COUNT': '1',
    'GIT_CONFIG_KEY_0': 'commit.gpgsign',
    'GIT_CONFIG_VALUE_0': 'false',
  },
);

void main() {
  late Directory tmp;
  final setup = RepoSetup(run: gitRun);

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-setup-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory folderWithFile(String name) {
    final dir = Directory('${tmp.path}/$name')..createSync();
    File('${dir.path}/notas.txt').writeAsStringSync('oi\n');
    return dir;
  }

  test(
    'init commits the folder files, so worktrees can start from HEAD',
    () async {
      final dir = folderWithFile('proj');
      await setup.init(dir.path);

      expect(await gitIn(dir.path, ['ls-files']), 'notas.txt\n');
      expect(await gitIn(dir.path, ['log', '--format=%s']), 'Commit inicial\n');
      expect(await gitIn(dir.path, ['remote']), '');
      expect(await resolveGitRoot(dir.path, run: gitRun), isNotEmpty);
    },
  );

  test('init starts on branch main, also on a git without -b (SPEC-071 '
      'R25)', () async {
    final dir = folderWithFile('proj');
    await setup.init(dir.path);
    expect(await gitIn(dir.path, ['branch', '--show-current']), 'main\n');

    // git < 2.28: `init -b` is an unknown switch.
    final calls = <List<String>>[];
    final old = RepoSetup(
      run: (exe, args) async {
        calls.add(args);
        if (args.contains('-b')) {
          return ProcessResult(0, 129, '', "error: unknown switch `b'\n");
        }
        return gitRun(exe, args);
      },
    );
    final legacy = folderWithFile('antigo');
    await old.init(legacy.path);
    expect(calls.any((a) => a.contains('symbolic-ref')), isTrue);
    expect(await gitIn(legacy.path, ['branch', '--show-current']), 'main\n');
  });

  test('init starts on the chosen branch, also on a git without -b '
      '(SPEC-072 R6)', () async {
    final dir = folderWithFile('trunk');
    await setup.init(dir.path, branch: 'trunk');
    expect(await gitIn(dir.path, ['branch', '--show-current']), 'trunk\n');

    final old = RepoSetup(
      run: (exe, args) async {
        if (args.contains('-b')) {
          return ProcessResult(0, 129, '', "error: unknown switch `b'\n");
        }
        return gitRun(exe, args);
      },
    );
    final legacy = folderWithFile('antigo-dev');
    await old.init(legacy.path, branch: 'dev');
    expect(await gitIn(legacy.path, ['branch', '--show-current']), 'dev\n');
  });

  test(
    'checkBranchName uses git check-ref-format --branch (SPEC-072 R5)',
    () async {
      expect(await setup.checkBranchName('main'), isNull);
      expect(await setup.checkBranchName('feat/novo'), isNull);
      expect(await setup.checkBranchName(''), contains('Informe'));
      expect(await setup.checkBranchName('com espaço'), contains('não é'));
      expect(await setup.checkBranchName('a..b'), contains('não é'));
      expect(await setup.checkBranchName('-x'), contains('"-"'));
    },
  );

  test(
    'identity reads the name and e-mail git commits with; '
    'setGlobalIdentity writes them with --global (SPEC-072 R1, R3)',
    () async {
      // An isolated global config: never the machine's.
      final home = Directory('${tmp.path}/home')..createSync();
      final global = '${home.path}/gitconfig';
      Future<ProcessResult> isolated(String exe, List<String> args) =>
          Process.run(
            exe,
            args,
            includeParentEnvironment: false,
            environment: {
              'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
              'HOME': home.path,
              'XDG_CONFIG_HOME': home.path,
              'GIT_CONFIG_GLOBAL': global,
              'GIT_CONFIG_NOSYSTEM': '1',
              'GIT_CONFIG_COUNT': '1',
              'GIT_CONFIG_KEY_0': 'user.useConfigOnly',
              'GIT_CONFIG_VALUE_0': 'true',
            },
          );
      final s = RepoSetup(run: isolated);
      await expectLater(
        s.identity(home.path),
        throwsA(
          isA<InvalidWorkspaceFolder>().having(
            (e) => e.message,
            'message',
            missingGitIdentity,
          ),
        ),
      );
      await expectLater(
        s.setGlobalIdentity(' ', 'a@b'),
        throwsA(isA<InvalidWorkspaceFolder>()),
      );
      await s.setGlobalIdentity(' Ana Lima ', 'ana@exemplo.com');
      expect(File(global).readAsStringSync(), contains('Ana Lima'));
      final id = await s.identity(home.path);
      expect(id.name, 'Ana Lima');
      expect(id.email, 'ana@exemplo.com');

      // No git on the PATH.
      final none = RepoSetup(
        run: (exe, args) => throw const ProcessException('git', []),
      );
      await expectLater(
        none.identity(home.path),
        throwsA(
          isA<InvalidWorkspaceFolder>().having(
            (e) => e.message,
            'message',
            gitNotFound,
          ),
        ),
      );
      expect(await none.checkBranchName('main'), isNull);
    },
  );

  test('init without the files makes an empty first commit', () async {
    final dir = folderWithFile('proj');
    await setup.init(dir.path, commitFiles: false);

    expect(await gitIn(dir.path, ['ls-files']), '');
    expect(await gitIn(dir.path, ['rev-list', '--count', 'HEAD']), '1\n');
    expect(await gitIn(dir.path, ['status', '--porcelain']), '?? notas.txt\n');
  });

  test('init sets origin, and a retry updates it instead of failing', () async {
    final dir = folderWithFile('proj');
    await setup.init(dir.path, remoteUrl: 'git@example.com:org/a.git');
    await setup.init(dir.path, remoteUrl: ' https://example.com/org/b.git ');

    expect(
      await gitIn(dir.path, ['remote', 'get-url', 'origin']),
      'https://example.com/org/b.git\n',
    );
  });

  test('clone goes into an empty folder, or a subfolder otherwise', () async {
    final origin = await createRepo(tmp, name: 'origin-app');

    final empty = Directory('${tmp.path}/vazia')..createSync();
    expect(await setup.clone(empty.path, origin), empty.path);
    expect(File('${empty.path}/a.txt').existsSync(), isTrue);

    final busy = folderWithFile('cheia');
    final dest = await setup.clone(busy.path, origin);
    expect(dest, '${busy.path}/origin-app');
    expect(File('$dest/a.txt').existsSync(), isTrue);

    // Same subfolder again: refused before running git.
    await expectLater(
      setup.clone(busy.path, origin),
      throwsA(isA<InvalidWorkspaceFolder>()),
    );
  });

  test('clone failures and bad URLs are reported', () async {
    final dir = Directory('${tmp.path}/vazia')..createSync();
    await expectLater(
      setup.clone(dir.path, '${tmp.path}/nao-existe'),
      throwsA(isA<GitException>()),
    );
    await expectLater(
      setup.clone(dir.path, '  '),
      throwsA(isA<InvalidWorkspaceFolder>()),
    );
    await expectLater(
      setup.init(dir.path, remoteUrl: '--upload-pack=x'),
      throwsA(isA<InvalidWorkspaceFolder>()),
    );
    expect(Directory('${dir.path}/.git').existsSync(), isFalse);
  });

  test('repo name and clone destination from the URL', () {
    expect(RepoSetup.repoNameFromUrl('git@github.com:org/app.git'), 'app');
    expect(RepoSetup.repoNameFromUrl('https://host/org/app/'), 'app');
    expect(RepoSetup.repoNameFromUrl('/srv/git/app.git'), 'app');
    expect(RepoSetup.repoNameFromUrl('host:app'), 'app');
    expect(RepoSetup.repoNameFromUrl('https://host/.git'), 'repo');
    expect(
      RepoSetup.cloneDestination('/w/x/', 'u/app.git', folderEmpty: false),
      '/w/x/app',
    );
    expect(
      RepoSetup.cloneDestination('/w/x', 'u/app.git', folderEmpty: true),
      '/w/x',
    );
  });

  test('git errors become short messages', () {
    expect(
      repoSetupError(
        const GitException(
          'git commit falhou',
          stderr: '*** Please tell me who you are.\n\nRun\n',
        ),
      ),
      contains('git config --global'),
    );
    expect(
      repoSetupError(
        const GitException(
          'git clone falhou',
          stderr: "Cloning into 'x'...\nfatal: repository 'u' not found\n",
        ),
      ),
      "fatal: repository 'u' not found",
    );
    expect(
      repoSetupError(const InvalidWorkspaceFolder('Informe a URL.')),
      'Informe a URL.',
    );
  });
}
