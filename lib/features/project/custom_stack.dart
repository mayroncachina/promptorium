import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart';
import '../../core/providers/structured_run.dart';
import '../../core/git/git_root.dart' show expandHome;
import 'project_planner.dart';
import 'project_templates.dart';

/// "Definir a stack com o Claude" (SPEC-072 R16–R19): the conversation of
/// the "Outro…" modal. It lives while the Começar screen is open (P9), so
/// the pencil reopens it with the messages and the preview.

/// Runs one read-only call of the modal (tests fake it).
typedef CustomStackRun = Future<Result> Function({
  required String cwd,
  required String prompt,
  String? sessionId,
  String? resumeId,
  Future<void>? cancelled,
});

/// Slot of the Stack própria's provider line (SPEC-100 R10).
const customStackSlot = 'custom-stack';

final customStackRunProvider = Provider<CustomStackRun>(
  (ref) =>
      ({
        required String cwd,
        required String prompt,
        String? sessionId,
        String? resumeId,
        Future<void>? cancelled,
      }) async => (await runStructured(
        ref,
        StructuredIntent(
          cwd: cwd,
          // SPEC-100 R8: the kind's provider (no more fixed Claude Code).
          cancelled: cancelled,
          prompt: prompt,
          sessionId: sessionId,
          resumeId: resumeId,
          instructions: customStackSystemPrompt,
          schema: customStackSchema,
          claude: const ClaudeStructuredExtras(
            maxBudgetUsd: ProjectPlanner.budgetUsd,
          ),
          slot: customStackSlot,
          label: 'a Stack própria',
        ),
      )).raw,
);

/// One message of the modal's conversation (what the person asked).
typedef CustomStackMessage = ({String text, bool adjust});

class CustomStackChat extends ChangeNotifier {
  CustomStackChat({
    required this.run,
    required this.newSessionId,
    required this.cwd,
  });

  final CustomStackRun run;
  final String Function() newSessionId;

  /// Where the read-only call runs (the "Criar dentro de" folder).
  String Function() cwd;

  final messages = <CustomStackMessage>[];
  CustomStack? proposal;
  String? error;

  /// Proposals and adjustments sent: each is a call (R19).
  int calls = 0;
  bool get busy => _cancel != null;

  String? _session;
  bool _answered = false;
  CustomStackMessage? _last;
  Completer<void>? _cancel;
  bool _disposed = false;

  /// "Propor stack".
  Future<void> propose(String description) =>
      _send((text: description.trim(), adjust: false));

  /// "Pedir ajuste…": the same conversation (`--resume`), a new preview.
  Future<void> adjust(String text) => _send((text: text.trim(), adjust: true));

  /// "Tentar de novo" after an error.
  Future<void> retry() async {
    final last = _last;
    if (last == null || busy) return;
    messages.remove(last);
    await _send(last);
  }

  /// "Cancelar" while thinking: ends the call.
  void cancel() {
    final c = _cancel;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// A command edited in the preview.
  void editCommand(String key, String value) {
    final p = proposal;
    if (p == null) return;
    proposal = p.copyWith(commands: p.commands.withValue(key, value));
    _notify();
  }

  Future<void> _send(CustomStackMessage m) async {
    if (m.text.isEmpty || busy) return;
    final adjust = m.adjust && _answered && _session != null;
    messages.add(m);
    _last = m;
    error = null;
    final cancel = _cancel = Completer<void>();
    calls++;
    _notify();
    // The first call opens the conversation; the next ones resume it.
    final String? resume = adjust ? _session : null;
    final String? sid = adjust ? null : (_session = newSessionId());
    try {
      final r = await run(
        cwd: cwd(),
        prompt: customStackPrompt(m.text, adjust: adjust),
        sessionId: sid,
        resumeId: resume,
        cancelled: cancel.future,
      );
      if (cancel.isCompleted) throw const _Cancelled();
      proposal = parseCustomStackResult(r);
      _answered = true;
    } on _Cancelled {
      messages.remove(m);
    } on PlannerException catch (e) {
      if (cancel.isCompleted) {
        messages.remove(m);
      } else {
        error = e.message;
      }
    } catch (e) {
      error = '$e';
    } finally {
      _cancel = null;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Folder the modal's call runs in: [parent] when it exists, else home.
String customStackCwd(String parent) {
  final p = expandHome(parent.trim());
  if (p.isNotEmpty && Directory(p).existsSync()) return p;
  return Platform.environment['HOME'] ?? Directory.systemTemp.path;
}
