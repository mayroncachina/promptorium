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
