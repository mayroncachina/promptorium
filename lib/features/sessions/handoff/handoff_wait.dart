import 'package:flutter/foundation.dart';

import '../../../core/memory/handoff.dart';

/// Reads `memory_handoff_list` (no claim) in the session's directory.
typedef HandoffLister = Future<HandoffList> Function();

/// The ai-memory agent kind of an app provider (`finalize-session --agent`).
String aiMemoryAgentKind(String provider) =>
    provider == 'codex' ? 'codex' : 'claude-code';

/// What the wait for the origin's handoff found (SPEC-099 R4.2, R4.3).
@immutable
class HandoffWaitResult {
  const HandoffWaitResult({
    this.handoff,
    this.list,
    this.finalized = false,
    this.error,
  });

  /// The automatic handoff written by the origin's end (null = none).
  final Handoff? handoff;
  final HandoffList? list;

  /// `finalize-session` was called (P8).
  final bool finalized;

  /// The last read failed (shown as a status line).
  final String? error;

  /// The origin was cut without a handoff (R4.3): ai-memory points it to
  /// the next session (`newer_unended_session`).
  bool get cut => handoff == null && error == null;

  /// A manual handoff that ai-memory delivers before this one (R5).
  Handoff? get manualBefore {
    for (final h in list?.open ?? const <Handoff>[]) {
      if (h.manual && h.id != handoff?.id) return h;
    }
    return null;
  }
}

/// The open automatic handoff left by the session [nativeId] (null = none).
Handoff? handoffOfSession(HandoffList list, String nativeId) {
  for (final h in list.open) {
    if (!h.manual && h.fromSessionId == nativeId) return h;
  }
  return null;
}

/// R4.2, P8: polls `memory_handoff_list` until the origin's handoff shows
/// up, for at most [timeout] (10 s). If it is not there after
/// [finalizeAfter], [finalize] runs once (`ai-memory finalize-session
/// --session-id`, which ends the session and writes the handoff through
/// the server) and the wait goes on until [timeout].
Future<HandoffWaitResult> waitForHandoff({
  required HandoffLister list,
  required String nativeId,
  Future<void> Function()? finalize,
  Duration timeout = const Duration(seconds: 10),
  Duration finalizeAfter = const Duration(seconds: 5),
  Duration interval = const Duration(seconds: 1),
  Future<void> Function(Duration)? delay,
}) async {
  final wait = delay ?? Future<void>.delayed;
  // Real time, or the waits added up (whichever is longer: a fake clock
  // in tests only moves the waits).
  final watch = Stopwatch()..start();
  var waited = Duration.zero;
  Duration elapsed() => watch.elapsed > waited ? watch.elapsed : waited;
  var finalized = false;
  HandoffList? last;
  String? error;
  for (;;) {
    try {
      last = await list();
      error = null;
      final h = handoffOfSession(last, nativeId);
      if (h != null) {
        return HandoffWaitResult(handoff: h, list: last, finalized: finalized);
      }
    } catch (e) {
      error = '$e';
    }
    if (!finalized && finalize != null && elapsed() >= finalizeAfter) {
      finalized = true;
      try {
        await finalize();
      } catch (e) {
        debugPrint('ai-memory finalize-session: $e');
      }
      continue;
    }
    if (elapsed() >= timeout) break;
    await wait(interval);
    waited += interval;
  }
  return HandoffWaitResult(list: last, finalized: finalized, error: error);
}

/// The state of a delivered handoff after the first turn (R4.5, R8).
enum HandoffAcceptance {
  /// Left the open list: taken by the new session at its start.
  delivered('entregue no início'),

  /// The row says it was accepted (with the time).
  accepted('aceita'),

  /// Still open after the first turn.
  unconfirmed('não confirmada');

  const HandoffAcceptance(this.label);
  final String label;
}

/// R4.5: what `memory_handoff_list` says of [handoffId] now.
({HandoffAcceptance state, DateTime? at}) handoffAcceptance(
  HandoffList list,
  String handoffId,
) {
  for (final h in list.handoffs) {
    if (h.id != handoffId) continue;
    if (h.state == HandoffState.accepted) {
      return (state: HandoffAcceptance.accepted, at: h.acceptedAt);
    }
    if (h.isOpen) return (state: HandoffAcceptance.unconfirmed, at: null);
    return (state: HandoffAcceptance.delivered, at: null);
  }
  return (state: HandoffAcceptance.delivered, at: null);
}

/// `ai-memory run <destino> --no-autowire` (R6): `--no-autowire` keeps the
/// launcher from changing the agent's configuration without the SPEC-098
/// preview; `--yolo` only when the session already was YOLO in a worktree.
List<String> aiMemoryRunArgs(String target, {bool yolo = false}) => [
  'run',
  target == 'codex' ? 'codex' : 'claude',
  '--no-autowire',
  if (yolo) '--yolo',
];
