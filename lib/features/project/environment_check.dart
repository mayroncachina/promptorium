import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_image.dart';
import '../../core/fs/project_paths.dart';
import '../../core/git/git_root.dart' show InvalidWorkspaceFolder, expandHome;
import '../../core/git/repo_setup.dart';
import '../../core/process/process_runner.dart';
import '../../core/providers/provider_availability.dart';
import '../review/review_host.dart';
import '../review/review_service.dart' show commandRunnerProvider;
import 'project_config.dart';
import 'project_service.dart' show projectNamePattern;

/// "Ambiente" of the Começar screen (SPEC-072 R1–R4, R20–R22): what is
/// checked before "Criar" — git, Claude Code, the hosting CLI and the
/// folder — each with a mark and, when red or amber, what fixes it.

/// The items of the panel, in display order. [clipboard] is optional: it
/// never blocks (SPEC-083 R2).
enum EnvKind { git, claude, host, folder, clipboard }

/// The mark of an item. Red blocks, amber only warns (R1, R15).
enum EnvState {
  checking('verificando…'),
  ok('ok'),
  blocked('bloqueia'),
  warning('aviso');

  const EnvState(this.word);

  /// The word shown next to the mark: never color alone (R15).
  final String word;
}

/// What is wrong with an item; picks the fix shown next to it (R3).
enum EnvProblem {
  gitMissing,
  gitIdentity,
  claudeMissing,
  claudeLogin,
  claudeIncompatible,
  hostMissing,
  hostLogin,
  hostOther,
  folderMissing,
  folderNotWritable,
  folderBusy,
  folderBadName,

  /// No `wl-paste` / `xclip`: images cannot be pasted (SPEC-083 R2).
  clipboardMissing,
  timeout,
}

/// Where the code will be hosted, from the "Repositório remoto" radio and
/// URL (R20). The indicator only shows it; it is never clicked.
enum Hosting {
  github('GitHub'),
  gitlab('GitLab'),
  local('Local'),

  /// "Conectar a" with a host that is neither GitHub nor GitLab.
  unknown('não reconhecida'),

  /// "Conectar a" still without a URL.
  pending('—');

  const Hosting(this.label);
  final String label;

  /// Hostings whose CLI is checked (`gh`, `glab`).
  bool get hasCli => this == github || this == gitlab;
}

/// [Hosting] of the radio ([withRemote]) and [url]. A self-hosted GitLab is
/// only known through `hospedagem:` of [config] (R21, P11).
Hosting detectHosting({
  required bool withRemote,
  required String url,
  ProjectConfig config = const ProjectConfig(),
}) {
  if (!withRemote) return Hosting.local;
  final u = url.trim();
  if (u.isEmpty) return Hosting.pending;
  return switch (detectReviewHost(u, config)) {
    'github' => Hosting.github,
    'gitlab' => Hosting.gitlab,
    _ => Hosting.unknown,
  };
}

/// One line of the panel.
@immutable
class EnvItem {
  const EnvItem(
    this.kind,
    this.state, {
    required this.title,
    this.line = '',
    this.problem,
    this.command,
    this.installUrl,
    this.note,
    this.subscriptionType,
  });

  /// Placeholder while the check runs.
  factory EnvItem.checking(EnvKind kind, String title) =>
      EnvItem(kind, EnvState.checking, title: title, line: 'verificando…');

  final EnvKind kind;
  final EnvState state;
  final String title;

  /// What was found ("Ana Lima · ana@exemplo.com").
  final String line;
  final EnvProblem? problem;

  /// Command the fix opens in a terminal (`claude auth login`).
  final String? command;

  /// Install page of the missing CLI.
  final String? installUrl;

  /// Extra line ("MR pelo app ainda não disponível (DT-55)").
  final String? note;

  /// Claude's plan (`max`, `pro`), null with an API key (R8, P6).
  final String? subscriptionType;

  bool get blocks => state == EnvState.blocked;

  /// What a screen reader hears (R15).
  String get semantics => '$title: ${state.word}. $line';

  @override
  bool operator ==(Object other) =>
      other is EnvItem &&
      other.kind == kind &&
      other.state == state &&
      other.title == title &&
      other.line == line &&
      other.problem == problem &&
      other.command == command &&
      other.note == note &&
      other.subscriptionType == subscriptionType;

  @override
  int get hashCode => Object.hash(kind, state, title, line, problem, command);
}

/// Title of each item ([hosting] names the CLI).
String envTitle(EnvKind kind, [Hosting hosting = Hosting.github]) =>
    switch (kind) {
      EnvKind.git => 'Git',
      EnvKind.claude => 'Claude Code',
      EnvKind.host =>
        hosting == Hosting.gitlab ? 'GitLab (glab)' : 'GitHub (gh)',
      EnvKind.folder => 'Pasta',
      EnvKind.clipboard => 'Colar imagens (opcional)',
    };

/// Where the Claude Code installation is explained (R3).
const claudeInstallUrl = 'https://docs.claude.com/en/docs/claude-code/setup';

/// Line of the DT-55 limitation on GitLab (R20).
const gitlabMrNote = 'MR pelo app ainda não disponível (DT-55).';

/// "Max", "Pro" for `subscriptionType`.
String planLabel(String type) =>
    type.isEmpty ? type : type[0].toUpperCase() + type.substring(1);

/// Whether "Criar" can run, given the items (R4).
@immutable
class EnvGate {
  const EnvGate({
    required this.canCreate,
    required this.canPlan,
    required this.blockers,
    this.reason,
    this.planReason,
  });

  /// Both buttons ("Criar sem planejar" included).
  final bool canCreate;

  /// "Criar e planejar com o planner" (also needs Claude).
  final bool canPlan;

  /// Red items (and an invalid branch).
  final int blockers;

  /// Shown under the buttons and read for "Criar sem planejar".
  final String? reason;

  /// Read for "Criar e planejar com o planner".
  final String? planReason;
}

/// Git or Pasta red (or an invalid branch) disable both buttons; Claude red
/// only "Criar e planejar"; the hosting CLI never blocks (R4, R5, P2, P3).
EnvGate envGate(Iterable<EnvItem> items, {String? branchError}) {
  final red = items.where((i) => i.blocks).toList();
  final hard =
      red.any((i) => i.kind == EnvKind.git || i.kind == EnvKind.folder) ||
      branchError != null;
  final claude = red.any((i) => i.kind == EnvKind.claude);
  final n = red.length + (branchError == null ? 0 : 1);
  final fix = n == 1
      ? 'Corrija 1 item do ambiente para criar.'
      : 'Corrija $n itens do ambiente para criar.';
  if (hard) {
    return EnvGate(
      canCreate: false,
      canPlan: false,
      blockers: n,
      reason: fix,
      planReason: fix,
    );
  }
  if (claude) {
    return EnvGate(
      canCreate: true,
      canPlan: false,
      blockers: n,
      reason:
          'Entre no Claude Code para planejar. "Criar sem planejar" segue '
          'livre.',
      planReason: 'Entre no Claude Code para planejar.',
    );
  }
  return const EnvGate(canCreate: true, canPlan: true, blockers: 0);
}

/// The checks, one function per item (tests fake it).
abstract class EnvironmentProbe {
  /// Git installed and with a name and e-mail (`git var`, like
  /// `RepoSetup.checkIdentity`).
  Future<EnvItem> git(String folder);

  /// Claude Code installed, compatible and logged in; [refresh] asks again
  /// instead of reusing the startup check.
  Future<EnvItem> claude({bool refresh = false});

  /// The hosting CLI (`gh` / `glab auth status --hostname`).
  Future<EnvItem> host(Hosting hosting, String hostname, String cwd);

  /// "Criar dentro de" exists and is writable; the destination does not
  /// exist or is a leftover of a failed creation.
  Future<EnvItem> folder(String parent, String name);

  /// "Gravar no git" (`git config --global`, P4).
  Future<void> setGlobalIdentity(String name, String email);

  /// Why [name] is not a valid branch, or null.
  Future<String?> branchError(String name);

  /// `wl-paste` (Wayland) or `xclip` (X11), to paste images in "Nova
  /// spec" (SPEC-083 R2). Optional: amber at most.
  Future<EnvItem> clipboard();
}

/// The real probe: git through [RepoSetup], Claude through
/// [providerAvailabilityProvider], the hosting through the Review's
/// [CliReviewHost] (no duplicated probing).
class SystemEnvironmentProbe implements EnvironmentProbe {
  SystemEnvironmentProbe(this._ref);

  final Ref _ref;

  RepoSetup get _setup => _ref.read(repoSetupProvider);

  @override
  Future<EnvItem> git(String folder) => checkGit(_setup, folder);

  @override
  Future<EnvItem> claude({bool refresh = false}) async {
    final p = providerAvailabilityProvider('claude');
    if (refresh) _ref.invalidate(p);
    return claudeItem(await _ref.read(p.future));
  }

  @override
  Future<EnvItem> host(Hosting hosting, String hostname, String cwd) {
    final run = _ref.read(commandRunnerProvider);
    final cli = hosting == Hosting.gitlab ? GitlabHost(run) : GithubHost(run);
    return checkHost(cli, hosting, hostname, cwd);
  }

  @override
  Future<EnvItem> folder(String parent, String name) =>
      checkFolder(_setup, parent, name, run: _ref.read(processRunnerProvider));

  @override
  Future<void> setGlobalIdentity(String name, String email) =>
      _setup.setGlobalIdentity(name, email);

  @override
  Future<String?> branchError(String name) => _setup.checkBranchName(name);

  @override
  Future<EnvItem> clipboard() =>
      checkClipboard(_ref.read(clipboardImageReaderProvider));
}

/// The optional clipboard item (SPEC-083 R2).
Future<EnvItem> checkClipboard(ClipboardImageReader reader) async {
  const title = 'Colar imagens (opcional)';
  final missing = await reader.missingTool();
  if (missing == null) {
    return EnvItem(
      EnvKind.clipboard,
      EnvState.ok,
      title: title,
      line: '${reader.executable} encontrado',
    );
  }
  return EnvItem(
    EnvKind.clipboard,
    EnvState.warning,
    title: title,
    line: 'Sem ${missing.tool}: o Ctrl V da Nova spec não cola imagens.',
    problem: EnvProblem.clipboardMissing,
    command: missing.command,
  );
}

final environmentProbeProvider = Provider<EnvironmentProbe>(
  SystemEnvironmentProbe.new,
);

/// Folder git runs in: [parent] when it exists, else the home folder.
String gitCwd(String parent) {
  final p = expandHome(parent.trim());
  if (p.isNotEmpty && Directory(p).isAbsolute && Directory(p).existsSync()) {
    return p;
  }
  return Platform.environment['HOME'] ?? Directory.systemTemp.path;
}

/// The Git item (R1, R3).
Future<EnvItem> checkGit(RepoSetup setup, String folder) async {
  try {
    final id = await setup.identity(gitCwd(folder));
    return EnvItem(
      EnvKind.git,
      EnvState.ok,
      title: 'Git',
      line: [id.name, id.email].where((x) => x.isNotEmpty).join(' · '),
    );
  } on InvalidWorkspaceFolder catch (e) {
    if (e.message == gitNotFound) {
      return const EnvItem(
        EnvKind.git,
        EnvState.blocked,
        title: 'Git',
        line: 'O git não foi encontrado.',
        problem: EnvProblem.gitMissing,
      );
    }
    return const EnvItem(
      EnvKind.git,
      EnvState.blocked,
      title: 'Git: nome e e-mail',
      line: 'O primeiro commit precisa de nome e e-mail.',
      problem: EnvProblem.gitIdentity,
    );
  }
}

/// The Claude Code item from the provider check (R1, R3, R8).
EnvItem claudeItem(ProviderAvailability a) {
  const title = 'Claude Code';
  switch (a.status) {
    case ProviderStatus.ready:
      final plan = a.subscriptionType;
      return EnvItem(
        EnvKind.claude,
        EnvState.ok,
        title: title,
        line: [
          ?a.version,
          'logado',
          plan == null ? 'chave de API' : 'plano ${planLabel(plan)}',
        ].join(' · '),
        subscriptionType: plan,
      );
    case ProviderStatus.missing:
      return const EnvItem(
        EnvKind.claude,
        EnvState.blocked,
        title: title,
        line: 'O Claude Code não foi encontrado.',
        problem: EnvProblem.claudeMissing,
        installUrl: claudeInstallUrl,
      );
    case ProviderStatus.loginRequired:
      return EnvItem(
        EnvKind.claude,
        EnvState.blocked,
        title: title,
        line: [?a.version, 'sem login'].join(' · '),
        problem: EnvProblem.claudeLogin,
        command: 'claude auth login',
      );
    case ProviderStatus.incompatible:
      return EnvItem(
        EnvKind.claude,
        EnvState.blocked,
        title: title,
        line: a.message,
        problem: EnvProblem.claudeIncompatible,
        installUrl: claudeInstallUrl,
      );
    case ProviderStatus.unknown:
      return EnvItem(
        EnvKind.claude,
        EnvState.warning,
        title: title,
        line: a.message,
        problem: EnvProblem.timeout,
      );
  }
}

/// The hosting CLI item: always amber when something is missing, never red
/// (R4, P3). On GitLab the `unsupported` of [CliReviewHost.availability]
/// (DT-55) is green with a note (R20).
Future<EnvItem> checkHost(
  CliReviewHost cli,
  Hosting hosting,
  String hostname,
  String cwd,
) async {
  final title = envTitle(EnvKind.host, hosting);
  final note = hosting == Hosting.gitlab ? gitlabMrNote : null;
  final a = await cli.availability(cwd, hostname);
  if (a.available || a.problem == HostProblem.unsupported) {
    return EnvItem(
      EnvKind.host,
      EnvState.ok,
      title: title,
      line: 'logado em $hostname',
      note: note,
    );
  }
  return switch (a.problem) {
    HostProblem.missing => EnvItem(
      EnvKind.host,
      EnvState.warning,
      title: title,
      line: 'O ${cli.cli} não foi encontrado. Instale o ${cli.cli}.',
      problem: EnvProblem.hostMissing,
      installUrl: a.installUrl ?? cli.installUrl,
      note: note,
    ),
    HostProblem.authentication => EnvItem(
      EnvKind.host,
      EnvState.warning,
      title: title,
      line: 'O ${cli.cli} não está logado em $hostname.',
      problem: EnvProblem.hostLogin,
      command: '${cli.cli} auth login --hostname $hostname',
      note: note,
    ),
    _ => EnvItem(
      EnvKind.host,
      EnvState.warning,
      title: title,
      line: (a.reason ?? 'Não deu para verificar o ${cli.cli}.')
          .split('\n')
          .first,
      problem: EnvProblem.hostOther,
      installUrl: a.problem == HostProblem.incompatible
          ? (a.installUrl ?? cli.installUrl)
          : null,
      note: note,
    ),
  };
}

/// The Pasta item (R1, R3).
Future<EnvItem> checkFolder(
  RepoSetup setup,
  String parent,
  String name, {
  ProcessRunner run = defaultProcessRunner,
}) async {
  EnvItem red(String line, EnvProblem p) => EnvItem(
    EnvKind.folder,
    EnvState.blocked,
    title: 'Pasta',
    line: line,
    problem: p,
  );
  final base = expandHome(parent.trim()).replaceAll(RegExp(r'(?<=.)/+$'), '');
  if (base.isEmpty || !Directory(base).isAbsolute) {
    return red('Escolha onde criar a pasta.', EnvProblem.folderMissing);
  }
  final shown = tildePath(base);
  if (!await Directory(base).exists()) {
    return red('$shown não existe.', EnvProblem.folderMissing);
  }
  // `test -w` (access(2)): nothing is written to check it.
  var writable = false;
  try {
    writable = (await run('test', ['-w', base])).exitCode == 0;
  } on ProcessException {
    writable = false;
  }
  if (!writable) {
    return red(
      'Sem permissão de escrita em $shown.',
      EnvProblem.folderNotWritable,
    );
  }
  final n = name.trim();
  if (n.isEmpty) {
    return EnvItem(
      EnvKind.folder,
      EnvState.ok,
      title: 'Pasta',
      line: '$shown é gravável',
    );
  }
  if (!projectNamePattern.hasMatch(n)) {
    return red(
      'Use só letras, números, ponto, hífen e sublinhado no nome.',
      EnvProblem.folderBadName,
    );
  }
  final path = base == '/' ? '/$n' : '$base/$n';
  final kind = await FileSystemEntity.type(path);
  if (kind == FileSystemEntityType.notFound) {
    return EnvItem(
      EnvKind.folder,
      EnvState.ok,
      title: 'Pasta',
      line: '$shown é gravável · $n ainda não existe',
    );
  }
  if (kind != FileSystemEntityType.directory) {
    return red('Já existe um arquivo $n em $shown.', EnvProblem.folderBusy);
  }
  if (await setup.isCreationLeftover(path)) {
    return EnvItem(
      EnvKind.folder,
      EnvState.ok,
      title: 'Pasta',
      line: '$shown é gravável · $n será reaproveitada',
    );
  }
  return red('$n já existe e tem arquivos.', EnvProblem.folderBusy);
}

/// What the panel checks: the form's folder, name and remote.
@immutable
class EnvInput {
  const EnvInput({
    required this.parent,
    required this.name,
    required this.hosting,
    this.hostname,
  });

  final String parent;
  final String name;
  final Hosting hosting;

  /// Host of the remote URL (`github.com`).
  final String? hostname;

  @override
  bool operator ==(Object other) =>
      other is EnvInput &&
      other.parent == parent &&
      other.name == name &&
      other.hosting == hosting &&
      other.hostname == hostname;

  @override
  int get hashCode => Object.hash(parent, name, hosting, hostname);
}

/// Runs the checks for the Começar screen (R2): all of them when it opens
/// and in "Verificar de novo"; Pasta and the hosting 300 ms after the last
/// change of the folder, name or remote. Each item runs alone, with a 5 s
/// limit; past it the item turns amber and does not block.
class EnvironmentChecker extends ChangeNotifier {
  EnvironmentChecker(
    this.probe, {
    this.limit = const Duration(seconds: 5),
    this.debounce = const Duration(milliseconds: 300),
  });

  final EnvironmentProbe probe;
  final Duration limit;
  final Duration debounce;

  final _items = <EnvKind, EnvItem>{};
  final _runs = <EnvKind, int>{};
  EnvInput? _input;
  Timer? _timer;
  final _limits = <Timer>{};
  bool _disposed = false;

  /// The items shown, in [EnvKind] order (no hosting item for Local,
  /// unrecognized or pending hostings).
  List<EnvItem> get items => [for (final k in EnvKind.values) ?_items[k]];

  EnvItem? operator [](EnvKind kind) => _items[kind];

  EnvInput? get input => _input;

  /// Every check, now.
  void checkAll(EnvInput input, {bool refreshClaude = false}) {
    _timer?.cancel();
    _input = input;
    _run(EnvKind.git);
    _run(EnvKind.claude, refreshClaude: refreshClaude);
    _syncHost(run: true);
    _run(EnvKind.folder);
    _run(EnvKind.clipboard);
  }

  /// The form changed: Pasta and the hosting run again after [debounce].
  void inputChanged(EnvInput input) {
    final before = _input;
    if (before == input) return;
    _input = input;
    final hostChanged =
        before == null ||
        before.hosting != input.hosting ||
        before.hostname != input.hostname;
    if (hostChanged) _syncHost(run: false);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _run(EnvKind.folder);
      if (hostChanged) _syncHost(run: true);
    });
  }

  /// Checks [kinds] again (after a fix, or the window coming back).
  void recheck(Iterable<EnvKind> kinds) {
    for (final k in kinds) {
      if (k == EnvKind.host) {
        _syncHost(run: true);
      } else {
        _run(k, refreshClaude: true);
      }
    }
  }

  /// "Gravar no git": writes the identity and checks the Git item again.
  Future<void> saveIdentity(String name, String email) async {
    await probe.setGlobalIdentity(name, email);
    _run(EnvKind.git);
  }

  /// Shows (as "verificando…") or hides the hosting item.
  void _syncHost({required bool run}) {
    final i = _input;
    if (i == null || !i.hosting.hasCli || i.hostname == null) {
      _runs[EnvKind.host] = (_runs[EnvKind.host] ?? 0) + 1;
      if (_items.remove(EnvKind.host) != null) _notify();
      return;
    }
    if (run) {
      _run(EnvKind.host);
    } else {
      _runs[EnvKind.host] = (_runs[EnvKind.host] ?? 0) + 1;
      _items[EnvKind.host] = EnvItem.checking(
        EnvKind.host,
        envTitle(EnvKind.host, i.hosting),
      );
      _notify();
    }
  }

  void _run(EnvKind kind, {bool refreshClaude = false}) {
    final i = _input;
    if (i == null) return;
    final id = (_runs[kind] ?? 0) + 1;
    _runs[kind] = id;
    final title = envTitle(kind, i.hosting);
    _items[kind] = EnvItem.checking(kind, title);
    _notify();
    Future<EnvItem> job() => switch (kind) {
      EnvKind.git => probe.git(i.parent),
      EnvKind.claude => probe.claude(refresh: refreshClaude),
      EnvKind.host => probe.host(i.hosting, i.hostname!, gitCwd(i.parent)),
      EnvKind.folder => probe.folder(i.parent, i.name),
      EnvKind.clipboard => probe.clipboard(),
    };
    EnvItem unverified(String line) => EnvItem(
      kind,
      EnvState.warning,
      title: title,
      line: line,
      problem: EnvProblem.timeout,
    );
    // Our own timer (not Future.timeout): dispose cancels it.
    final done = Completer<EnvItem>();
    final timer = Timer(limit, () {
      if (!done.isCompleted) {
        done.complete(
          unverified('não deu para verificar (mais de ${limit.inSeconds} s)'),
        );
      }
    });
    _limits.add(timer);
    Future.sync(job).then(
      (item) {
        if (!done.isCompleted) done.complete(item);
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.complete(unverified('não deu para verificar: $e'));
        }
      },
    );
    done.future.then((item) {
      timer.cancel();
      _limits.remove(timer);
      if (_disposed || _runs[kind] != id) return;
      _items[kind] = item;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final t in _limits) {
      t.cancel();
    }
    _limits.clear();
    super.dispose();
  }
}
