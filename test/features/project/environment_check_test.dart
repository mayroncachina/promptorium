import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/repo_setup.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/features/project/environment_check.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/review/review_host.dart';

import '../../core/git/repo_setup_test.dart' show gitRun;

/// A probe whose answers the test sets; each call waits on [gate] when set.
class FakeProbe implements EnvironmentProbe {
  final calls = <String>[];
  EnvItem gitItem = const EnvItem(
    EnvKind.git,
    EnvState.ok,
    title: 'Git',
    line: 'Ana Lima · ana@exemplo.com',
  );
  EnvItem claudeItem = const EnvItem(
    EnvKind.claude,
    EnvState.ok,
    title: 'Claude Code',
    line: '2.1.300 · logado · plano Max',
    subscriptionType: 'max',
  );
  EnvItem Function(Hosting, String) hostItem = (h, host) => EnvItem(
    EnvKind.host,
    EnvState.ok,
    title: envTitle(EnvKind.host, h),
    line: 'logado em $host',
  );
  EnvItem Function(String, String) folderItem = (p, n) => const EnvItem(
    EnvKind.folder,
    EnvState.ok,
    title: 'Pasta',
    line: '~/workspace é gravável',
  );
  Completer<void>? gate;
  final identities = <(String, String)>[];

  Future<T> _wait<T>(T Function() f) async {
    if (gate case final g?) await g.future;
    return f();
  }

  @override
  Future<EnvItem> git(String folder) {
    calls.add('git');
    return _wait(() => gitItem);
  }

  @override
  Future<EnvItem> claude({bool refresh = false}) {
    calls.add(refresh ? 'claude!' : 'claude');
    return _wait(() => claudeItem);
  }

  @override
  Future<EnvItem> host(Hosting hosting, String hostname, String cwd) {
    calls.add('host ${hosting.name} $hostname');
    return _wait(() => hostItem(hosting, hostname));
  }

  @override
  Future<EnvItem> folder(String parent, String name) {
    calls.add('folder $parent $name');
    return _wait(() => folderItem(parent, name));
  }

  @override
  Future<void> setGlobalIdentity(String name, String email) async {
    identities.add((name, email));
    gitItem = EnvItem(
      EnvKind.git,
      EnvState.ok,
      title: 'Git',
      line: '$name · $email',
    );
  }

  @override
  Future<String?> branchError(String name) async {
    calls.add('branch $name');
    return name.contains(' ')
        ? '"$name" não é um nome de branch válido.'
        : null;
  }

  EnvItem clipboardItem = const EnvItem(
    EnvKind.clipboard,
    EnvState.ok,
    title: 'Colar imagens (opcional)',
    line: 'xclip encontrado',
  );

  @override
  Future<EnvItem> clipboard() => _wait(() => clipboardItem);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-env-'));
  tearDown(() {
    // Undo a chmod of the "no permission" case.
    Process.runSync('chmod', ['-R', 'u+w', tmp.path]);
    tmp.deleteSync(recursive: true);
  });

  test('hosting follows the radio and the URL (R20, R21)', () {
    expect(detectHosting(withRemote: false, url: 'x'), Hosting.local);
    expect(detectHosting(withRemote: true, url: ' '), Hosting.pending);
    expect(
      detectHosting(withRemote: true, url: 'git@github.com:a/b.git'),
      Hosting.github,
    );
    expect(
      detectHosting(withRemote: true, url: 'https://gitlab.com/a/b'),
      Hosting.gitlab,
    );
    expect(
      detectHosting(withRemote: true, url: 'git@git.empresa.com:a/b.git'),
      Hosting.unknown,
    );
    // Only a hospedagem: makes a self-hosted GitLab known (P11).
    expect(
      detectHosting(
        withRemote: true,
        url: 'git@git.empresa.com:a/b.git',
        config: const ProjectConfig(
          host: 'git.empresa.com',
          hostType: 'gitlab',
        ),
      ),
      Hosting.gitlab,
    );
    expect(Hosting.github.hasCli && Hosting.gitlab.hasCli, isTrue);
    expect(Hosting.local.hasCli || Hosting.unknown.hasCli, isFalse);
  });

  EnvItem item(EnvKind k, EnvState s) => EnvItem(k, s, title: k.name);

  test('git or folder red block both buttons; Claude red only "Criar e '
      'planejar"; the hosting CLI never blocks (R4)', () {
    final ok = [for (final k in EnvKind.values) item(k, EnvState.ok)];
    final all = envGate(ok);
    expect((all.canCreate, all.canPlan, all.reason), (true, true, null));

    final git = envGate([
      item(EnvKind.git, EnvState.blocked),
      item(EnvKind.folder, EnvState.ok),
    ]);
    expect((git.canCreate, git.canPlan), (false, false));
    expect(git.reason, 'Corrija 1 item do ambiente para criar.');

    final two = envGate([
      item(EnvKind.folder, EnvState.blocked),
      item(EnvKind.claude, EnvState.blocked),
    ]);
    expect((two.canCreate, two.blockers), (false, 2));
    expect(two.reason, 'Corrija 2 itens do ambiente para criar.');

    final claude = envGate([item(EnvKind.claude, EnvState.blocked)]);
    expect((claude.canCreate, claude.canPlan), (true, false));
    expect(claude.planReason, contains('Claude Code'));

    final host = envGate([
      item(EnvKind.host, EnvState.warning),
      item(EnvKind.claude, EnvState.warning),
      item(EnvKind.git, EnvState.checking),
    ]);
    expect((host.canCreate, host.canPlan), (true, true));

    // An invalid branch blocks like the folder (R5).
    final branch = envGate(ok, branchError: 'inválida');
    expect(
      (branch.canCreate, branch.canPlan, branch.blockers),
      (false, false, 1),
    );
  });

  test('marks have words, not only color (R15)', () {
    expect(EnvState.values.map((s) => s.word), [
      'verificando…',
      'ok',
      'bloqueia',
      'aviso',
    ]);
    const i = EnvItem(
      EnvKind.git,
      EnvState.blocked,
      title: 'Git: nome e e-mail',
      line: 'O primeiro commit precisa de nome e e-mail.',
    );
    expect(i.semantics, contains('bloqueia'));
  });

  test(
    'Git item: name and e-mail, missing identity, missing git (R1)',
    () async {
      Future<EnvItem> withRunner(
        Future<ProcessResult> Function(String, List<String>) run,
      ) => checkGit(RepoSetup(run: run), tmp.path);

      final ok = await withRunner(
        (exe, args) async => ProcessResult(
          0,
          0,
          'Ana Lima <ana@exemplo.com> 1700000000 -0300\n',
          '',
        ),
      );
      expect(ok.state, EnvState.ok);
      expect(ok.line, 'Ana Lima · ana@exemplo.com');

      final none = await withRunner(
        (exe, args) async => ProcessResult(
          0,
          128,
          '',
          'fatal: no email was given and auto-detection is disabled',
        ),
      );
      expect(none.state, EnvState.blocked);
      expect(none.problem, EnvProblem.gitIdentity);
      expect(none.title, 'Git: nome e e-mail');

      final missing = await withRunner(
        (exe, args) => throw const ProcessException('git', []),
      );
      expect(missing.problem, EnvProblem.gitMissing);
      expect(missing.state, EnvState.blocked);
    },
  );

  test('Claude item: version and plan, login, missing (R1, R3, R8)', () async {
    Future<ProviderAvailability> claude(String auth, {int version = 0}) =>
        inspectProvider(ClaudeCodeProvider(), (exe, args) async {
          if (args.first == '--version') {
            return ProcessResult(1, version, '2.1.300 (Claude Code)', '');
          }
          if (args.first == '--help') {
            return ProcessResult(1, 0, '--input-format --output-format', '');
          }
          return ProcessResult(1, 0, auth, '');
        });

    final max = claudeItem(
      await claude('{"loggedIn":true,"subscriptionType":"max"}'),
    );
    expect(max.state, EnvState.ok);
    expect(max.line, '2.1.300 · logado · plano Max');
    expect(max.subscriptionType, 'max');

    // An older CLI / an API key: no subscriptionType (P6).
    final api = claudeItem(await claude('{"loggedIn":true}'));
    expect(api.line, '2.1.300 · logado · chave de API');
    expect(api.subscriptionType, isNull);

    final login = claudeItem(await claude('{"loggedIn":false}'));
    expect(login.state, EnvState.blocked);
    expect(login.problem, EnvProblem.claudeLogin);
    expect(login.command, 'claude auth login');

    final missing = claudeItem(await claude('', version: 127));
    expect(missing.problem, EnvProblem.claudeMissing);
    expect(missing.installUrl, claudeInstallUrl);

    final unknown = claudeItem(
      const ProviderAvailability(ProviderStatus.unknown, 'falhou'),
    );
    expect(unknown.state, EnvState.warning);
  });

  test('hosting item: gh / glab logged, logged out, missing — never red '
      '(R1, R3, R20)', () async {
    HostCommand fake({bool installed = true, String auth = '', int code = 0}) =>
        (exe, args, {workingDirectory}) async {
          if (exe == 'which') {
            return ProcessResult(
              0,
              installed ? 0 : 1,
              installed ? '/x' : '',
              '',
            );
          }
          return ProcessResult(0, code, '', auth);
        };

    final gh = await checkHost(
      GithubHost(fake()),
      Hosting.github,
      'github.com',
      tmp.path,
    );
    expect(
      (gh.state, gh.title, gh.line),
      (EnvState.ok, 'GitHub (gh)', 'logado em github.com'),
    );

    // glab logged in: green, the DT-55 "unsupported" is not a warning.
    final glab = await checkHost(
      GitlabHost(fake()),
      Hosting.gitlab,
      'gitlab.com',
      tmp.path,
    );
    expect(glab.state, EnvState.ok);
    expect(glab.note, gitlabMrNote);

    final out = await checkHost(
      GitlabHost(
        fake(code: 1, auth: 'You are not logged into any GitLab hosts'),
      ),
      Hosting.gitlab,
      'gitlab.com',
      tmp.path,
    );
    expect(out.state, EnvState.warning);
    expect(out.problem, EnvProblem.hostLogin);
    expect(out.command, 'glab auth login --hostname gitlab.com');
    expect(out.line, 'O glab não está logado em gitlab.com.');

    final missing = await checkHost(
      GithubHost(fake(installed: false)),
      Hosting.github,
      'github.com',
      tmp.path,
    );
    expect(missing.state, EnvState.warning);
    expect(missing.problem, EnvProblem.hostMissing);
    expect(missing.installUrl, contains('cli/cli'));
  });

  test(
    'Pasta item: writable, missing, busy, leftover, bad name (R1, R3)',
    () async {
      final setup = RepoSetup(run: gitRun);
      final ok = await checkFolder(setup, tmp.path, 'novo');
      expect(ok.state, EnvState.ok);
      expect(ok.line, endsWith('novo ainda não existe'));
      expect((await checkFolder(setup, tmp.path, '')).state, EnvState.ok);

      final missing = await checkFolder(setup, '${tmp.path}/nao', 'x');
      expect(missing.problem, EnvProblem.folderMissing);
      expect(
        (await checkFolder(setup, 'relativo', 'x')).state,
        EnvState.blocked,
      );

      File('${tmp.path}/cheia/a.txt').createSync(recursive: true);
      final busy = await checkFolder(setup, tmp.path, 'cheia');
      expect(busy.problem, EnvProblem.folderBusy);
      expect(busy.line, contains('já existe e tem arquivos'));

      final bad = await checkFolder(setup, tmp.path, 'a b');
      expect(bad.problem, EnvProblem.folderBadName);

      // What a failed creation left is accepted (SPEC-071 R21).
      Directory('${tmp.path}/sobra/.git').createSync(recursive: true);
      await Process.run('git', ['init', '-q', '${tmp.path}/sobra']);
      final left = await checkFolder(setup, tmp.path, 'sobra');
      expect(left.state, EnvState.ok);
      expect(left.line, contains('reaproveitada'));

      // No permission to write (skipped when running as root).
      final ro = Directory('${tmp.path}/ro')..createSync();
      Process.runSync('chmod', ['555', ro.path]);
      final canWrite = () {
        try {
          File('${ro.path}/t').writeAsStringSync('');
          return true;
        } catch (_) {
          return false;
        }
      }();
      if (!canWrite) {
        final denied = await checkFolder(setup, ro.path, 'x');
        expect(denied.problem, EnvProblem.folderNotWritable);
      }
    },
  );

  group('EnvironmentChecker (R2)', () {
    const input = EnvInput(
      parent: '/srv',
      name: 'loja',
      hosting: Hosting.local,
    );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 5));

    test(
      'checks everything at once; the hosting item only with a CLI',
      () async {
        final probe = FakeProbe()..gate = Completer();
        final c = EnvironmentChecker(probe);
        addTearDown(c.dispose);
        c.checkAll(input);
        expect(c.items.map((i) => i.state).toSet(), {EnvState.checking});
        expect(c.items.map((i) => i.kind), [
          EnvKind.git,
          EnvKind.claude,
          EnvKind.folder,
          EnvKind.clipboard,
        ]);
        probe.gate!.complete();
        await settle();
        expect(c.items.every((i) => i.state == EnvState.ok), isTrue);

        // "Conectar a" with github.com: the gh item appears after the debounce.
        c.inputChanged(
          const EnvInput(
            parent: '/srv',
            name: 'loja',
            hosting: Hosting.github,
            hostname: 'github.com',
          ),
        );
        expect(c[EnvKind.host]?.state, EnvState.checking);
        expect(probe.calls.where((x) => x.startsWith('host')), isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(probe.calls, contains('host github github.com'));
        expect(c[EnvKind.host]?.state, EnvState.ok);

        // Back to "Só local": no hosting item.
        c.inputChanged(input);
        expect(c[EnvKind.host], isNull);
      },
    );

    test('typing re-runs Pasta once, 300 ms after the last key', () async {
      final probe = FakeProbe();
      final c = EnvironmentChecker(probe);
      addTearDown(c.dispose);
      c.checkAll(input);
      await settle();
      probe.calls.clear();
      for (final n in ['l', 'lo', 'loj']) {
        c.inputChanged(
          EnvInput(parent: '/srv', name: n, hosting: Hosting.local),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(probe.calls, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(probe.calls, ['folder /srv loj']);
    });

    test('a slow item turns amber past the limit and does not block', () async {
      final probe = FakeProbe()..gate = Completer();
      final c = EnvironmentChecker(
        probe,
        limit: const Duration(milliseconds: 30),
      );
      addTearDown(c.dispose);
      c.checkAll(input);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(c.items.every((i) => i.state == EnvState.warning), isTrue);
      expect(c[EnvKind.git]!.line, contains('não deu para verificar'));
      expect(envGate(c.items).canCreate, isTrue);
      probe.gate!.complete();
    });

    test('"Gravar no git" writes and checks the Git item again; a re-check '
        'asks Claude again', () async {
      final probe = FakeProbe()
        ..gitItem = const EnvItem(
          EnvKind.git,
          EnvState.blocked,
          title: 'Git: nome e e-mail',
          problem: EnvProblem.gitIdentity,
        );
      final c = EnvironmentChecker(probe);
      addTearDown(c.dispose);
      c.checkAll(input);
      await settle();
      expect(c[EnvKind.git]!.state, EnvState.blocked);
      await c.saveIdentity('Ana Lima', 'ana@exemplo.com');
      await settle();
      expect(probe.identities, [('Ana Lima', 'ana@exemplo.com')]);
      expect(c[EnvKind.git]!.state, EnvState.ok);
      expect(c[EnvKind.git]!.line, 'Ana Lima · ana@exemplo.com');

      c.recheck({EnvKind.claude});
      await settle();
      expect(probe.calls.last, 'claude!');
    });

    test('a stale answer does not overwrite a newer one', () async {
      final probe = FakeProbe();
      final slow = Completer<void>();
      probe.folderItem = (p, n) =>
          EnvItem(EnvKind.folder, EnvState.ok, title: 'Pasta', line: n);
      final c = EnvironmentChecker(_SlowFirst(probe, slow));
      addTearDown(c.dispose);
      c.checkAll(input);
      c.recheck({EnvKind.folder});
      await settle();
      slow.complete();
      await settle();
      expect(c[EnvKind.folder]!.line, 'loja');
    });
  });
}

/// Delays the first folder answer until [slow] completes.
class _SlowFirst implements EnvironmentProbe {
  _SlowFirst(this.inner, this.slow);
  final FakeProbe inner;
  final Completer<void> slow;
  var _folderCalls = 0;

  @override
  Future<EnvItem> folder(String parent, String name) async {
    if (++_folderCalls == 1) {
      await slow.future;
      return const EnvItem(
        EnvKind.folder,
        EnvState.blocked,
        title: 'Pasta',
        line: 'velha',
      );
    }
    return inner.folder(parent, name);
  }

  @override
  Future<EnvItem> git(String folder) => inner.git(folder);
  @override
  Future<EnvItem> claude({bool refresh = false}) =>
      inner.claude(refresh: refresh);
  @override
  Future<EnvItem> host(Hosting hosting, String hostname, String cwd) =>
      inner.host(hosting, hostname, cwd);
  @override
  Future<void> setGlobalIdentity(String name, String email) =>
      inner.setGlobalIdentity(name, email);
  @override
  Future<String?> branchError(String name) => inner.branchError(name);
  @override
  Future<EnvItem> clipboard() => inner.clipboard();
}
