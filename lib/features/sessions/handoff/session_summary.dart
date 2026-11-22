import '../../../core/claude/claude_event.dart';
import '../../prompt/prompt_actions.dart' show lastAnswer, lastUserMessage;
import '../timeline.dart';

/// The "Resumo do app" of a session (SPEC-099 R7, R10): built by the app
/// from the timeline, without calling a model, the way the "Nova conversa
/// com resumo" of SPEC-087 is built for conversations. Uses the neutral
/// file and command events, so it works for Claude and Codex sessions.
///
/// The person edits it in the dialog; it goes to the message field of the
/// new session and only leaves when they send it (P1).
String sessionSummary({
  required String title,
  required String provider,
  required List<TimelineItem> items,
  String? root,
  List<String> uncommitted = const [],
  int maxAnswer = 1200,
}) {
  String cut(String t, int max) {
    final s = t.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.length <= max ? s : '${s.substring(0, max).trimRight()}…';
  }

  final b = StringBuffer(
    'Continuação da sessão "$title" (${providerWords(provider)}).\n',
  );
  final ask = lastUserMessage(items);
  if (ask != null) b.write('\nÚltimo pedido: ${cut(ask, 600)}\n');
  final answer = lastAnswer(items);
  if (answer != null) {
    b.write('Última resposta (trecho): ${cut(answer, maxAnswer)}\n');
  }
  final files = changedFiles(items, root: root);
  if (files.isNotEmpty) {
    b.write('Arquivos alterados: ${files.map((f) => '@$f').join(' ')}\n');
  }
  final failed = failedCommands(items);
  if (failed.isNotEmpty) {
    b.write('Comandos que falharam: ${failed.join('; ')}\n');
  }
  final tasks = lastTasks(items);
  if (tasks != null && tasks.isNotEmpty) {
    b.write(
      'Tarefas: ${[for (final t in tasks) '[${t.done ? 'x' : ' '}] ${t.text}'].join('  ')}\n',
    );
  }
  if (uncommitted.isNotEmpty) {
    b.write(
      'Não commitados: ${uncommitted.length} '
      '${uncommitted.length == 1 ? 'arquivo' : 'arquivos'}.\n',
    );
  }
  b.write('\nContinue a partir daqui.');
  return b.toString();
}

/// "Claude Code", "Codex".
String providerWords(String provider) => switch (provider) {
  'codex' => 'Codex',
  'claude' => 'Claude Code',
  final p => p,
};

/// Every top-level card and the cards inside subagents.
Iterable<ToolItem> _tools(List<TimelineItem> items) sync* {
  for (final i in items) {
    if (i is ToolItem) {
      yield i;
      yield* _tools(i.children);
    }
  }
}

/// Files the session changed (applied changes, in order, without
/// duplicates), relative to [root].
List<String> changedFiles(List<TimelineItem> items, {String? root}) {
  String rel(String p) {
    if (root != null && root.isNotEmpty && p.startsWith('$root/')) {
      return p.substring(root.length + 1);
    }
    return p;
  }

  final out = <String>[];
  for (final t in _tools(items)) {
    for (final c in t.fileChanges) {
      if (c.status == FileChangeStatus.declined ||
          c.status == FileChangeStatus.failed ||
          c.path.isEmpty) {
        continue;
      }
      final p = rel(c.path);
      if (!out.contains(p)) out.add(p);
    }
  }
  return out;
}

/// `flutter test test/a_test.dart (saída 1, 11:33)` for each command that
/// failed (exit code other than zero), oldest first; the last [limit].
List<String> failedCommands(List<TimelineItem> items, {int limit = 5}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final out = <String>[];
  for (final t in _tools(items)) {
    final c = t.command;
    if (c == null || !c.done || !c.failed) continue;
    final cmd = c.displayCommand.trim().split('\n').first;
    final short = cmd.length > 120 ? '${cmd.substring(0, 119)}…' : cmd;
    final code = c.exitCode;
    final at = t.at?.toLocal();
    final when = at == null ? '' : ', ${two(at.hour)}:${two(at.minute)}';
    out.add(
      code == null ? '$short (falhou$when)' : '$short (saída $code$when)',
    );
  }
  return out.length <= limit ? out : out.sublist(out.length - limit);
}

/// One item of the last task list.
typedef SessionTask = ({String text, bool done});

/// The last task list of the session: Claude's `TodoWrite` or the Codex
/// `update_plan` (null = none).
List<SessionTask>? lastTasks(List<TimelineItem> items) {
  List<SessionTask>? last;
  for (final t in _tools(items)) {
    final list = switch (t.name) {
      'TodoWrite' => t.input['todos'],
      'update_plan' => t.input['plan'],
      _ => null,
    };
    if (list is! List) continue;
    last = [
      for (final e in list)
        if (e is Map)
          (
            text: '${e['content'] ?? e['step'] ?? ''}'.trim(),
            done: e['status'] == 'completed',
          ),
    ].where((e) => e.text.isNotEmpty).toList();
  }
  return last;
}
