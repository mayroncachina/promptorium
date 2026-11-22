import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_memory_state.dart';

/// Kinds of execution the app starts, as ai-memory should see them
/// (SPEC-098 R6).
enum AiMemoryRunKind {
  /// Read-only runs with structured output (planner, questions and design
  /// of a spec, verifier, automatic reviewer, titles, step decisions and
  /// classification, `vibe_guard`, `/usage`): no capture, no handoff taken,
  /// no handoff left.
  auxiliary,

  /// Step sessions of the Quadro: captured, but no automatic handoff at the
  /// end — the app already carries the context between steps (P3).
  stepSession,

  /// Free sessions and Prompt conversations: ai-memory's normal behavior.
  free,
}

/// Hands capture to an external producer: the hooks stop capturing and
/// offer the pending handoff without claiming it (`claim=0`), P4.
const aiMemoryCaptureOwnerVar = 'AI_MEMORY_CAPTURE_OWNER';

/// `off` skips the automatic handoff at the end of that execution only.
const aiMemoryAutoHandoffVar = 'AI_MEMORY_AUTO_HANDOFF';

/// The producer name the app declares.
const aiMemoryCaptureOwner = 'promptorium';

/// Variables of one execution (R6). Empty without the ai-memory binary
/// (R2: the agents get the same environment as before). With the binary
/// present they apply whatever the server state, and also to hooks the
/// person installed outside the app: a stopped server spools the events
/// and would replay them later.
Map<String, String> aiMemoryEnvironmentFor(
  AiMemoryRunKind kind, {
  required bool installed,
}) {
  if (!installed) return const {};
  return switch (kind) {
    AiMemoryRunKind.auxiliary => const {
      aiMemoryCaptureOwnerVar: aiMemoryCaptureOwner,
      aiMemoryAutoHandoffVar: 'off',
    },
    AiMemoryRunKind.stepSession => const {aiMemoryAutoHandoffVar: 'off'},
    AiMemoryRunKind.free => const {},
  };
}

/// [aiMemoryEnvironmentFor] with the binary looked up on disk (cached; no
/// process runs). Never throws: a failed lookup counts as not installed.
Future<Map<String, String>> aiMemoryRunEnvironment(
  Ref ref,
  AiMemoryRunKind kind,
) async {
  if (kind == AiMemoryRunKind.free) return const {};
  String? exe;
  try {
    exe = await ref.read(aiMemoryExecutableProvider.future);
  } catch (_) {
    exe = null;
  }
  return aiMemoryEnvironmentFor(kind, installed: exe != null);
}

/// The environment of a process: [base] plus the ai-memory variables, or
/// [base] itself (possibly null) when there are none — so without the
/// binary nothing changes, not even a null becoming an empty map.
Map<String, String>? withAiMemory(
  Map<String, String>? base,
  Map<String, String> memory,
) => memory.isEmpty ? base : {...?base, ...memory};
