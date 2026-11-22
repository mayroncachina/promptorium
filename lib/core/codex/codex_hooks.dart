import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../claude/managed_hooks.dart';

/// The app's hooks in a Codex session (SPEC-103 R3–R5).
///
/// The neutral [ManagedHookPlan] becomes session config overrides (`-c` of
/// `codex app-server`), which the App Server lists with the origin
/// `sessionFlags`. Nothing is written in `~/.codex`, `--trust` is never used
/// and `CODEX_HOME` is never changed. Whether each hook really runs comes
/// from `hooks/list`, never from what was sent: on the 0.170 a hook given by
/// `-c` stays `untrusted` and does not run (SPEC-093 R15), so the session
/// falls back to the post-turn checks (R7).

/// Codex event of each app hook (`hooks/list` → `eventName`).
String codexHookEvent(ManagedHook h) => switch (h) {
  ManagedHook.block || ManagedHook.secrets => 'preToolUse',
  ManagedHook.format => 'postToolUse',
  ManagedHook.end => 'sessionEnd',
};

/// The `-c` overrides of [plan] for the Codex (R3): one handler per event,
/// all calling [command] (the script with `--provedor codex`). The shape
/// is the one SPEC-093 R15 saw listed: `matcher="*"` and a `command`
/// handler; the script filters the tools itself.
Map<String, String> codexHookOverrides(ManagedHookPlan plan, String command) {
  if (plan.isEmpty) return const {};
  final handler = '{type="command",command=${_tomlString(command)}}';
  String entry({bool matcher = true}) =>
      '[{${matcher ? 'matcher="*",' : ''}hooks=[$handler]}]';
  final on = plan.enabled;
  return {
    if (on.contains(ManagedHook.block) || on.contains(ManagedHook.secrets))
      'hooks.PreToolUse': entry(),
    if (on.contains(ManagedHook.format)) 'hooks.PostToolUse': entry(),
    if (on.contains(ManagedHook.end)) 'hooks.SessionEnd': entry(matcher: false),
  };
}

/// TOML basic string.
String _tomlString(String s) {
  final b = StringBuffer('"');
  for (final r in s.runes) {
    switch (r) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      case 0x09:
        b.write(r'\t');
      default:
        if (r < 0x20) {
          b.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
        } else {
          b.writeCharCode(r);
        }
    }
  }
  b.write('"');
  return b.toString();
}

/// What the session got (R5, R9).
enum CodexHookMode {
  /// Every hook of the plan listed, on and trusted: "Hooks nativos".
  native('Hooks nativos'),

  /// Some of them: "Hooks parciais".
  partial('Hooks parciais'),

  /// None of them (or the list failed): "Hooks só pós-turno".
  postTurn('Hooks só pós-turno'),

  /// Every app hook is off in Automações: nothing to confirm.
  off('Hooks desligados');

  const CodexHookMode(this.label);
  final String label;
}

/// Where each hook of a Codex session runs (R7, R8): before the tool (the
/// Codex runs the script) or the app's substitute after the turn.
enum HookWhen {
  beforeTool('Antes da ferramenta'),
  afterTurn('Ao fim do turno'),
  unavailable('Indisponível');

  const HookWhen(this.label);
  final String label;
}

/// The app's substitute of a hook that did not become active (R7).
String hookSubstitute(ManagedHook h, {bool yolo = false}) => switch (h) {
  ManagedHook.secrets => 'commits conferidos ao fim do turno e no push do app',
  ManagedHook.format => 'formatar: nos arquivos alterados no turno',
  ManagedHook.end => 'o app registra o fim do processo',
  ManagedHook.block =>
    yolo
        ? 'sem bloqueio prévio no YOLO (não há pedido de aprovação)'
        : 'regras aplicadas aos pedidos de aprovação',
};

/// State of the app's hooks in one Codex session, from `hooks/list`.
@immutable
class CodexHookStatus {
  const CodexHookStatus({
    required this.mode,
    this.planned = const {},
    this.active = const {},
    this.problems = const [],
    this.reason,
    this.at,
  });

  final CodexHookMode mode;

  /// Hooks of the plan (on in Automações, with what they need).
  final Set<ManagedHook> planned;

  /// Hooks the App Server listed on, from `sessionFlags`, and trusted.
  final Set<ManagedHook> active;

  /// Errors and warnings of `hooks/list` (debug log and tooltip, R5).
  final List<String> problems;

  /// Why the hooks are not native ("o Codex 0.170 pediu confiança
  /// gravada", "sem python3"…).
  final String? reason;

  /// When `hooks/list` answered.
  final DateTime? at;

  Set<ManagedHook> get inactive => planned.difference(active);

  /// Where [h] runs in this session (R7, R8).
  HookWhen whenOf(ManagedHook h, {bool yolo = false}) {
    if (active.contains(h)) return HookWhen.beforeTool;
    if (h == ManagedHook.block && yolo) return HookWhen.unavailable;
    return HookWhen.afterTurn;
  }

  /// Tooltip / line of the chip.
  String get tooltip {
    final b = StringBuffer(switch (mode) {
      CodexHookMode.native =>
        'Os hooks do app rodam antes de cada ferramenta (origem '
            'sessionFlags, confiança só desta sessão).',
      CodexHookMode.partial =>
        'Inativos: ${[for (final h in inactive) h.label].join(', ')}.',
      CodexHookMode.postTurn =>
        'Os hooks do app não ficaram ativos nesta sessão; valem os '
            'substitutos ao fim do turno.',
      CodexHookMode.off => 'Os hooks do app estão desligados em Automações.',
    });
    if (reason != null) b.write(' $reason');
    for (final p in problems) {
      b.write('\n$p');
    }
    return b.toString();
  }
}

/// The 0.170 reason (SPEC-093 R15), shown when the listed hooks are
/// `untrusted`.
const codexUntrustedReason =
    'O Codex pediu confiança gravada para os hooks de sessão; o app não '
    'grava nada no ~/.codex.';

/// Reads a `hooks/list` result (R5): a hook of [plan] is active when an
/// entry of the session's flags runs [command] for its event, is on and
/// is `managed` or `trusted`. [error] = the request failed.
CodexHookStatus codexHookStatus(
  ManagedHookPlan plan, {
  required String command,
  Map<String, dynamic>? result,
  Object? error,
  DateTime? at,
}) {
  if (plan.isEmpty) {
    return CodexHookStatus(mode: CodexHookMode.off, at: at);
  }
  final problems = <String>[];
  final events = <String, String>{}; // eventName → trustStatus of ours
  final enabledEvents = <String>{};
  if (error != null) {
    problems.add('hooks/list falhou: $error');
  }
  for (final entry in result?['data'] as List? ?? const []) {
    if (entry is! Map) continue;
    for (final w in entry['warnings'] as List? ?? const []) {
      problems.add('Aviso: ${w is Map ? w['message'] ?? w : w}');
    }
    for (final e in entry['errors'] as List? ?? const []) {
      problems.add('Erro: ${e is Map ? e['message'] ?? e : e}');
    }
    for (final h in entry['hooks'] as List? ?? const []) {
      if (h is! Map) continue;
      if (h['source'] != 'sessionFlags' || h['command'] != command) continue;
      final event = '${h['eventName']}';
      final trust = '${h['trustStatus']}';
      events[event] = trust;
      if (h['enabled'] == true && (trust == 'managed' || trust == 'trusted')) {
        enabledEvents.add(event);
      }
    }
  }
  final active = {
    for (final h in plan.enabled)
      if (enabledEvents.contains(codexHookEvent(h))) h,
  };
  final mode = active.length == plan.enabled.length
      ? CodexHookMode.native
      : active.isEmpty
      ? CodexHookMode.postTurn
      : CodexHookMode.partial;
  String? reason;
  if (mode != CodexHookMode.native) {
    if (error != null) {
      reason = 'O hooks/list falhou.';
    } else if (events.values.any((t) => t == 'untrusted' || t == 'modified')) {
      reason = codexUntrustedReason;
    } else if (events.isEmpty) {
      reason = 'O Codex não listou os hooks do app.';
    }
  }
  return CodexHookStatus(
    mode: mode,
    planned: plan.enabled,
    active: active,
    problems: problems,
    reason: reason,
    at: at,
  );
}

/// Hook state of each live Codex session (R5, R9), by session id.
class CodexHookStatuses extends Notifier<Map<String, CodexHookStatus>> {
  @override
  Map<String, CodexHookStatus> build() => const {};

  void set(String sessionId, CodexHookStatus s) =>
      state = {...state, sessionId: s};

  void remove(String sessionId) {
    if (!state.containsKey(sessionId)) return;
    state = {...state}..remove(sessionId);
  }
}

final codexHookStatusProvider =
    NotifierProvider<CodexHookStatuses, Map<String, CodexHookStatus>>(
      CodexHookStatuses.new,
    );
