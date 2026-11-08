import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Marking of the commits made by the app's agent sessions (SPEC-048).
///
/// With `git: marcar-commits-de-agente` on, every agent session the app
/// opens gets in its environment the model, the origin and a
/// `core.hooksPath` (through `GIT_CONFIG_COUNT`, so it is valid only inside
/// the session) pointing to [AgentGitHooks.dir]. Its `prepare-commit-msg`
/// appends `Promptorium-Agente: <modelo> · <origem>`; every other hook
/// passes through to the repository's own hook. Nothing is written in the
/// repository or in `.git/hooks`.

/// Key of the trailer.
const agentTrailerKey = 'Promptorium-Agente';

/// Model of the commits the app itself makes ("Commitar o que sobrou", R4).
const appTrailerModel = 'app';

/// Origin of a Prompt conversation (end of a plan).
const promptOrigin = 'Prompt';

/// Oldest git that does everything the marking needs: `GIT_CONFIG_COUNT`
/// (2.31) and `git commit --trailer` (2.32).
const agentTrailerMinGit = GitVersion(2, 32);

/// `sonnet · SPEC-042 R2` (no origin = only the model).
String agentTrailerValue(String model, String origin) =>
    origin.trim().isEmpty ? model : '$model · ${origin.trim()}';

/// `Promptorium-Agente: sonnet · SPEC-042 R2`.
String agentTrailerLine(String model, String origin) =>
    '$agentTrailerKey: ${agentTrailerValue(model, origin)}';

/// Origin of a spec step: `SPEC-042 R2`, `SPEC-042 R1, R2`.
String stepOrigin(String specCode, Iterable<String> steps) {
  final s = steps.where((e) => e.trim().isNotEmpty).join(', ');
  return s.isEmpty ? specCode : '$specCode $s';
}

/// Origin of a conflict resolution: `SPEC-043 conflito`.
String conflictOrigin(String label) => '$label conflito';

/// Origin of a redone base (restack conflict): `SPEC-042 base`.
String restackOrigin(String label) => '$label base';

/// Origin of a free session: `sessão <nome>`.
String sessionOrigin(String title) => 'sessão ${title.trim()}';

/// Model written in the trailer: the session's model, or the provider when
/// the session uses the provider default (`inherit`).
String agentModelLabel(String? model, String provider) {
  final m = model?.trim() ?? '';
  return m.isEmpty || m == 'inherit' || m == 'default' ? provider : m;
}

/// `git --version` as numbers.
@immutable
class GitVersion implements Comparable<GitVersion> {
  const GitVersion(this.major, this.minor, [this.patch = 0]);

  final int major, minor, patch;

  /// `git version 2.43.0` / `git version 2.39.2.windows.1` → version.
  static GitVersion? parse(String text) {
    final m = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(text);
    if (m == null) return null;
    return GitVersion(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.tryParse(m[3] ?? '') ?? 0,
    );
  }

  @override
  int compareTo(GitVersion o) => major != o.major
      ? major.compareTo(o.major)
      : minor != o.minor
      ? minor.compareTo(o.minor)
      : patch.compareTo(o.patch);

  bool operator >=(GitVersion o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is GitVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Whether [version] runs the marking (null = git missing).
bool gitSupportsAgentTrailer(GitVersion? version) =>
    version != null && version >= agentTrailerMinGit;

/// Version of the `git` on the PATH; null when it does not run.
Future<GitVersion?> readGitVersion({String executable = 'git'}) async {
  try {
    final r = await Process.run(executable, ['--version']);
    return r.exitCode == 0 ? GitVersion.parse('${r.stdout}') : null;
  } catch (_) {
    return null;
  }
}

/// The app's git hooks folder (`~/.promptorium/git-hooks/`): written by
/// [ensure], which rewrites it when [version] changes (app update).
class AgentGitHooks {
  AgentGitHooks(this.dir);

  final String dir;

  /// Bump when any script below changes.
  static const version = 1;

  /// The hooks git knows (githooks(5)); each one passes through to the
  /// repository's own, `prepare-commit-msg` also marks the message.
  static const standardHooks = [
    'applypatch-msg',
    'pre-applypatch',
    'post-applypatch',
    'pre-commit',
    'pre-merge-commit',
    'prepare-commit-msg',
    'commit-msg',
    'post-commit',
    'pre-rebase',
    'post-checkout',
    'post-merge',
    'pre-push',
    'pre-receive',
    'update',
    'proc-receive',
    'post-receive',
    'post-update',
    'reference-transaction',
    'push-to-checkout',
    'pre-auto-gc',
    'post-rewrite',
    'sendemail-validate',
    'fsmonitor-watchman',
    'p4-changelist',
    'p4-prepare-changelist',
    'p4-post-changelist',
    'p4-pre-submit',
    'post-index-change',
  ];

  /// Shared shell functions (sourced by every hook).
  static const libName = 'promptorium-repasse.sh';
  static const versionFile = '.versao';

  /// Per-session origin, updated while the process lives (the next step of
  /// the same session, a conflict to resolve).
  String get originsDir => '$dir/origens';
  String originFile(String sessionId) => '$originsDir/$sessionId';

  Future<void>? _ensuring;

  /// Writes the folder when it is missing or from another [version].
  Future<void> ensure() => _ensuring ??= _ensure().whenComplete(() {
    _ensuring = null;
  });

  Future<void> _ensure() async {
    final v = File('$dir/$versionFile');
    if (await v.exists() &&
        (await v.readAsString()).trim() == '$version' &&
        await File('$dir/prepare-commit-msg').exists()) {
      return;
    }
    await Directory(dir).create(recursive: true);
    Future<void> write(String name, String text) async {
      final tmp = File('$dir/$name.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/$name');
    }

    await write(libName, libScript);
    final names = <String>[];
    for (final h in standardHooks) {
      await write(h, h == 'prepare-commit-msg' ? markScript : passScript);
      names.add('$dir/$h');
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', ...names]);
    }
    await write(versionFile, '$version\n');
  }

  /// Origin of a live session (the hook prefers it to the environment).
  Future<void> setOrigin(String sessionId, String origin) async {
    try {
      await Directory(originsDir).create(recursive: true);
      await File(originFile(sessionId)).writeAsString('$origin\n');
    } catch (e) {
      debugPrint('origem de $sessionId não gravada: $e');
    }
  }

  Future<void> clearOrigin(String sessionId) async {
    try {
      final f = File(originFile(sessionId));
      if (await f.exists()) await f.delete();
    } catch (_) {
      // best effort
    }
  }

  /// Variables of an agent session: model, origin and `core.hooksPath`
  /// appended after the `GIT_CONFIG_*` the app itself inherited.
  Map<String, String> environment({
    required String model,
    required String origin,
    String? sessionId,
    Map<String, String>? inherited,
  }) {
    final base = int.tryParse(
      (inherited ?? Platform.environment)['GIT_CONFIG_COUNT'] ?? '',
    );
    final n = base == null || base < 0 ? 0 : base;
    return {
      'PROMPTORIUM_AGENTE': model,
      'PROMPTORIUM_ORIGEM': origin,
      if (sessionId != null)
        'PROMPTORIUM_ORIGEM_ARQUIVO': originFile(sessionId),
      'PROMPTORIUM_GIT_CONFIG_BASE': '$n',
      'GIT_CONFIG_COUNT': '${n + 1}',
      'GIT_CONFIG_KEY_$n': 'core.hooksPath',
      'GIT_CONFIG_VALUE_$n': dir,
    };
  }

  /// Functions shared by the hooks. The repository's hooks run with the
  /// `GIT_CONFIG_*` of before the app (so `core.hooksPath` is theirs again).
  static const libScript = r'''
# Gerado pelo Promptorium. Não edite: o app reescreve esta pasta.

# Volta o GIT_CONFIG_* ao que era antes do app (sem o core.hooksPath dele).
promptorium_restaurar() {
  base="${PROMPTORIUM_GIT_CONFIG_BASE:-0}"
  unset "GIT_CONFIG_KEY_$base" "GIT_CONFIG_VALUE_$base"
  if [ "$base" = 0 ]; then
    unset GIT_CONFIG_COUNT
  else
    GIT_CONFIG_COUNT="$base"
    export GIT_CONFIG_COUNT
  fi
}

# Caminho do hook $1 do repositório (core.hooksPath dele ou .git/hooks),
# vazio quando não existe ou não é executável.
promptorium_original() {
  dir=$(promptorium_restaurar; git config --path --get core.hooksPath 2>/dev/null)
  [ -n "$dir" ] || dir="$(promptorium_restaurar; git rev-parse --git-common-dir 2>/dev/null)/hooks"
  case "$dir" in
    /*|[A-Za-z]:*) ;;
    *) dir="$PWD/$dir" ;;
  esac
  [ -d "$dir" ] || return 0
  aqui=$(cd "$(dirname "$0")" && pwd -P)
  la=$(cd "$dir" && pwd -P)
  [ "$aqui" = "$la" ] && return 0
  [ -f "$dir/$1" ] && [ -x "$dir/$1" ] && printf '%s\n' "$dir/$1"
  return 0
}
''';

  /// Every hook but `prepare-commit-msg`: same arguments, same stdin.
  static const passScript = r'''#!/bin/sh
# Gerado pelo Promptorium. Não edite: o app reescreve esta pasta.
# Repassa para o hook do repositório com os mesmos argumentos e stdin.
. "$(dirname "$0")/promptorium-repasse.sh"
hook=$(promptorium_original "$(basename "$0")")
[ -n "$hook" ] || exit 0
promptorium_restaurar
exec "$hook" "$@"
''';

  /// `prepare-commit-msg`: the repository's first, then the line (replaced
  /// when it is already there: amend, rebase).
  static const markScript = r'''#!/bin/sh
# Gerado pelo Promptorium. Não edite: o app reescreve esta pasta.
# Chama o prepare-commit-msg do repositório e acrescenta a linha
# Promptorium-Agente ao fim da mensagem.
. "$(dirname "$0")/promptorium-repasse.sh"
hook=$(promptorium_original prepare-commit-msg)
if [ -n "$hook" ]; then
  (promptorium_restaurar; "$hook" "$@") || exit $?
fi
[ -n "$PROMPTORIUM_AGENTE" ] || exit 0
origem="$PROMPTORIUM_ORIGEM"
if [ -n "$PROMPTORIUM_ORIGEM_ARQUIVO" ] && [ -s "$PROMPTORIUM_ORIGEM_ARQUIVO" ]; then
  origem=$(head -n 1 "$PROMPTORIUM_ORIGEM_ARQUIVO")
fi
linha="$PROMPTORIUM_AGENTE"
[ -n "$origem" ] && linha="$linha · $origem"
git interpret-trailers --in-place --if-exists replace \
  --trailer "Promptorium-Agente: $linha" "$1"
''';
}

/// The app's hooks folder; null in tests (override with a temporary dir).
final agentGitHooksProvider = Provider<AgentGitHooks?>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return AgentGitHooks('$home/.promptorium/git-hooks');
});

/// `git --version` (read once per app run).
final gitVersionProvider = FutureProvider<GitVersion?>(
  (ref) => readGitVersion(),
);

/// Environment of one agent session: empty when the option is off, the
/// hooks are unavailable or git is too old (R2, R8).
Future<Map<String, String>> agentCommitEnv({
  required bool enabled,
  required AgentGitHooks? hooks,
  required GitVersion? git,
  required String model,
  required String origin,
  String? sessionId,
  Map<String, String>? inherited,
}) async {
  if (!enabled || hooks == null || !gitSupportsAgentTrailer(git)) {
    return const {};
  }
  try {
    await hooks.ensure();
  } catch (e) {
    debugPrint('hooks de git do app não gravados: $e');
    return const {};
  }
  if (sessionId != null) await hooks.setOrigin(sessionId, origin);
  return hooks.environment(
    model: model,
    origin: origin,
    sessionId: sessionId,
    inherited: inherited,
  );
}
