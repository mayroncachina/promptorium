import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hooks the app adds to every session through a temporary `--settings`
/// file (nothing goes to the user's `~/.claude/settings.json`). The hook is
/// a small Python 3 script written next to it; it reads the event on stdin
/// and answers like a user hook. What it did goes to `hooks.log` (JSON
/// lines), read by the app after each tool result (timeline cards).
///
/// Verified on CLI 2.1.302 (docs/pesquisa/hooks-settings-stream-json.md):
/// `PreToolUse` with `permissionDecision: deny` refuses the call and the
/// reason reaches the agent; `PostToolUse` and `SessionEnd` run; the user's
/// own hooks keep running.
enum ManagedHook {
  /// `PreToolUse` on Bash: refuses dangerous commands.
  block('Bloquear comandos perigosos', 'PreToolUse'),

  /// `PostToolUse` on Edit / Write / MultiEdit: runs `formatar:`.
  format('Formatar ao editar', 'PostToolUse'),

  /// `SessionEnd`: records why the session ended.
  end('Registrar fim da sessão', 'SessionEnd');

  const ManagedHook(this.label, this.event);

  final String label;
  final String event;

  /// `app_settings` key: '0' = off (default on).
  String get settingKey => 'hooks.$name';

  String get description => switch (this) {
    block =>
      'Antes de cada comando Bash: recusa git push --force, rm -rf / ou ~, '
          'git worktree remove, git -C na raiz do repositório (sessões em '
          'worktree) e os bloquear-comandos do config.yml.',
    format =>
      'Depois de cada edição: roda o formatar: do config.yml com o arquivo '
          'editado.',
    end => 'Ao encerrar o processo: registra o motivo na timeline.',
  };
}

/// One rule of the `PreToolUse` hook: a regular expression searched in the
/// Bash command.
@immutable
class BlockRule {
  const BlockRule(this.name, this.pattern);

  final String name;
  final String pattern;

  Map<String, String> toJson() => {'nome': name, 're': pattern};
}

/// Built-in rules (see [ManagedHook.block]).
const builtinBlockRules = [
  BlockRule(
    'git push --force',
    r'\bgit\b[^;&|]*\bpush\b[^;&|]*(\s--force(?!-with-lease)\b|\s-f\b)',
  ),
  BlockRule(
    'rm -rf na raiz ou na home',
    r'\brm\s+-[A-Za-z]*\s+(/|~|\$HOME)/?\*?(\s|$|;|&)',
  ),
  BlockRule('git worktree remove', r'\bgit\b[^;&|]*\bworktree\s+remove\b'),
];

/// `bloquear-comandos:` glob → [BlockRule]: `*` is anything; the pattern
/// may appear anywhere in the command.
BlockRule globRule(String glob) {
  final re = glob.split('*').map(RegExp.escape).join('.*');
  return BlockRule(glob, re);
}

/// Every rule of a session: built-in, the project's and, for a session in a
/// worktree, `git -C <root>` / `cd <root>` (the main repository is not
/// touched from a worktree).
List<BlockRule> blockRules({
  List<String> projectGlobs = const [],
  String? root,
  String? cwd,
}) => [
  ...builtinBlockRules,
  for (final g in projectGlobs) globRule(g),
  if (root != null && cwd != null && root != cwd) ...[
    BlockRule(
      'git -C na raiz do repositório',
      '\\bgit\\s+-C\\s+[\'"]?${RegExp.escape(root)}/?[\'"]?(\\s|\$)',
    ),
    BlockRule(
      'cd para a raiz do repositório',
      '\\bcd\\s+[\'"]?${RegExp.escape(root)}/?[\'"]?(\\s|\$|;|&)',
    ),
  ],
];

/// Whether [command] is refused by [rules] (same search as the script);
/// returns the rule's name.
String? blockedBy(String command, List<BlockRule> rules) {
  for (final r in rules) {
    if (RegExp(r.pattern).hasMatch(command)) return r.name;
  }
  return null;
}

/// What a hook did (a line of `hooks.log`).
@immutable
class HookActivity {
  const HookActivity({
    required this.hook,
    required this.text,
    required this.at,
    this.error = false,
  });

  final ManagedHook hook;

  /// Timeline line ("Hook bloqueou `git push --force`").
  final String text;
  final DateTime at;
  final bool error;

  static HookActivity? fromLogLine(String line) {
    Object? j;
    try {
      j = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['em'] ?? ''}') ?? DateTime.now();
    return switch (j['evento']) {
      'bloqueio' => HookActivity(
        hook: ManagedHook.block,
        text: 'Hook bloqueou `${j['comando']}` (${j['regra']})',
        at: at,
        error: true,
      ),
      'formatado' => HookActivity(
        hook: ManagedHook.format,
        text: j['ok'] == true
            ? 'Formatado: ${j['arquivo']}'
            : 'Falha ao formatar ${j['arquivo']}: ${j['saida'] ?? ''}'.trim(),
        at: at,
        error: j['ok'] != true,
      ),
      'fim' => HookActivity(
        hook: ManagedHook.end,
        text: 'Sessão encerrada (${j['motivo'] ?? '?'})',
        at: at,
      ),
      _ => null,
    };
  }
}

/// The hook script (Python 3, standard library only).
const hookScript = r'''
import datetime, json, os, re, shlex, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    cfg = json.load(open(os.path.join(HERE, "hooks-config.json"), encoding="utf-8"))
    ev = json.load(sys.stdin)
    name = ev.get("hook_event_name")

    def log(obj):
        obj["em"] = datetime.datetime.now().isoformat()
        with open(cfg["log"], "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")

    tool_input = ev.get("tool_input") or {}
    if name == "PreToolUse" and ev.get("tool_name") == "Bash":
        cmd = tool_input.get("command") or ""
        for rule in cfg.get("bloquear", []):
            if re.search(rule["re"], cmd):
                log({"evento": "bloqueio", "comando": cmd, "regra": rule["nome"]})
                print(json.dumps({"hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason":
                        "Promptorium: comando bloqueado (%s). Não tente contornar; "
                        "se for necessário, peça ao usuário." % rule["nome"],
                }}))
                return
    elif name == "PostToolUse" and cfg.get("formatar") and \
            ev.get("tool_name") in ("Edit", "Write", "MultiEdit"):
        path = tool_input.get("file_path")
        if not path:
            return
        cmd = cfg["formatar"].replace("{arquivo}", shlex.quote(path))
        try:
            r = subprocess.run(cmd, shell=True, cwd=ev.get("cwd") or None,
                               capture_output=True, text=True, timeout=60)
            ok, out = r.returncode == 0, (r.stdout + r.stderr)[-2000:]
        except subprocess.TimeoutExpired:
            ok, out = False, "tempo esgotado (60 s)"
        rel = os.path.relpath(path, ev.get("cwd") or HERE)
        log({"evento": "formatado", "arquivo": rel, "ok": ok, "saida": out.strip()})
    elif name == "SessionEnd":
        log({"evento": "fim", "motivo": ev.get("reason")})


try:
    main()
except Exception:
    # A broken hook must never stop the agent.
    pass
''';

/// Writes and removes the per-session hook files under [runBase]
/// (`~/.promptorium/run/<session>/`).
class ManagedHooks {
  ManagedHooks({required this.runBase, this.python = 'python3'});

  final String runBase;
  final String python;

  String dirOf(String sessionId) => '$runBase/$sessionId';
  String logOf(String sessionId) => '${dirOf(sessionId)}/hooks.log';

  /// `settings.json` with one entry per enabled hook, all calling
  /// [command] (the script).
  static Map<String, Object?> settingsJson(
    String command,
    Set<ManagedHook> enabled,
  ) {
    List<Map<String, Object?>> entry(String? matcher) => [
      {
        'matcher': ?matcher,
        'hooks': [
          {'type': 'command', 'command': command, 'timeout': 90},
        ],
      },
    ];
    return {
      'hooks': {
        if (enabled.contains(ManagedHook.block)) 'PreToolUse': entry('Bash'),
        if (enabled.contains(ManagedHook.format))
          'PostToolUse': entry('Write|Edit|MultiEdit'),
        if (enabled.contains(ManagedHook.end)) 'SessionEnd': entry(null),
      },
    };
  }

  /// Writes the session's files; returns the `--settings` path, or null
  /// when no hook applies.
  /// [extra] goes into the same `settings.json` (the plugins and MCP
  /// servers turned off, SPEC-017 R2).
  Future<String?> prepare(
    String sessionId, {
    required Set<ManagedHook> enabled,
    required List<BlockRule> rules,
    String? formatCommand,
    Map<String, Object?> extra = const {},
  }) async {
    final on = {
      for (final h in enabled)
        if (h != ManagedHook.format || formatCommand != null) h,
    };
    if (on.isEmpty && extra.isEmpty) return null;
    final dir = Directory(dirOf(sessionId));
    await dir.create(recursive: true);
    if (on.isEmpty) {
      final settings = File('${dir.path}/settings.json');
      await settings.writeAsString(jsonEncode(extra));
      return settings.path;
    }
    final script = File('${dir.path}/promptorium_hook.py');
    await script.writeAsString(hookScript);
    await File('${dir.path}/hooks-config.json').writeAsString(
      jsonEncode({
        'log': logOf(sessionId),
        'bloquear': [
          if (on.contains(ManagedHook.block))
            for (final r in rules) r.toJson(),
        ],
        'formatar': on.contains(ManagedHook.format) ? formatCommand : null,
      }),
    );
    final settings = File('${dir.path}/settings.json');
    await settings.writeAsString(
      jsonEncode({
        ...settingsJson('$python ${_quote(script.path)}', on),
        ...extra,
      }),
    );
    return settings.path;
  }

  /// New lines of the session's log after byte [offset]; returns them and
  /// the new offset.
  Future<(List<HookActivity>, int)> readLog(
    String sessionId,
    int offset,
  ) async {
    final f = File(logOf(sessionId));
    if (!await f.exists()) return (const <HookActivity>[], offset);
    final len = await f.length();
    if (len <= offset) return (const <HookActivity>[], offset);
    final raf = await f.open();
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(len - offset);
      final text = utf8.decode(bytes, allowMalformed: true);
      final end = text.lastIndexOf('\n');
      if (end < 0) return (const <HookActivity>[], offset);
      final lines = text.substring(0, end).split('\n');
      return (
        [for (final l in lines) ?HookActivity.fromLogLine(l)],
        offset + utf8.encode(text.substring(0, end + 1)).length,
      );
    } finally {
      await raf.close();
    }
  }

  Future<void> cleanup(String sessionId) async {
    try {
      final d = Directory(dirOf(sessionId));
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      debugPrint('hooks de $sessionId não removidos: $e');
    }
  }

  static String _quote(String s) => "'${s.replaceAll("'", r"'\''")}'";
}

/// Whether `python3` runs (the hook script needs it). Checked once.
Future<bool> pythonAvailable() => _python ??= () async {
  try {
    final r = await Process.run('python3', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}();
Future<bool>? _python;

/// The app's hooks; null = off (tests, or no `python3`). Tests that need
/// them override with a temporary [ManagedHooks.runBase].
final managedHooksProvider = Provider<ManagedHooks?>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
  final home = Platform.environment['HOME'] ?? '';
  return ManagedHooks(runBase: '$home/.promptorium/run');
});

/// Whether the hook script can run; null = the app's hooks are off (tests).
final pythonAvailableProvider = FutureProvider<bool?>(
  (ref) async =>
      ref.watch(managedHooksProvider) == null ? null : await pythonAvailable(),
);

/// Last thing each hook did in this app session (Automações screen).
class HookActivityLog extends Notifier<Map<ManagedHook, HookActivity>> {
  @override
  Map<ManagedHook, HookActivity> build() => const {};

  void add(HookActivity a) => state = {...state, a.hook: a};
}

final hookActivityProvider =
    NotifierProvider<HookActivityLog, Map<ManagedHook, HookActivity>>(
      HookActivityLog.new,
    );
