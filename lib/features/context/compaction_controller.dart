import '../../core/providers/capabilities.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'context_snapshot.dart';

/// The CLI's native compaction command. Verified on CLI 2.1.329 in the mode
/// the app uses (`-p` stream-json): the user message `/compact [foco]` runs
/// it (`status compacting` → `compact_boundary trigger: manual` → `result`
/// with `num_turns: 0`; docs/pesquisa/contexto-e-compactacao.md §5).
const compactCommandName = '/compact';

/// `/compact` or `/compact <focus>` (focus on one line).
String compactCommand([String? focus]) {
  final f = (focus ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  return f.isEmpty ? compactCommandName : '$compactCommandName $f';
}

/// Whether "Compactar agora" can run now, and why not (SPEC-087 R9).
@immutable
class CompactAvailability {
  const CompactAvailability._(this.reason);

  static const available = CompactAvailability._(null);

  /// Null = available.
  final String? reason;

  bool get ok => reason == null;
}

/// The agent needs the `compactNow` capability (SPEC-094; Claude `/compact`,
/// Codex `thread/compact/start`, SPEC-107 R8), a history and an idle
/// agent, and never runs over a running compaction.
CompactAvailability compactAvailability({
  required String provider,
  required bool busy,
  required ContextSnapshot snapshot,
  ProviderCapabilities? capabilities,
}) {
  final caps = capabilities ?? capabilitiesFor(provider);
  if (!caps.supports(ProviderCapability.compactNow)) {
    return const CompactAvailability._(
      'Indisponível: este agente não confirmou um comando nativo de '
      'compactação no modo usado pelo app. A compactação automática segue a '
      'cargo dele.',
    );
  }
  if (snapshot.readings.isEmpty) {
    return const CompactAvailability._(
      'Nada para compactar ainda: esta conversa não tem nenhuma medição.',
    );
  }
  if (snapshot.phase == CompactionPhase.compacting) {
    return const CompactAvailability._('O agente já está compactando.');
  }
  if (busy) {
    return const CompactAvailability._(
      'Espere a resposta atual: compactar só com o agente ocioso.',
    );
  }
  return CompactAvailability.available;
}

/// Sends the native compaction command once per history at a time (R9).
/// It never decides by itself when to compact: only a click calls it.
class CompactionController {
  final Set<String> _inFlight = {};

  bool isRunning(String key) => _inFlight.contains(key);

  /// Runs [send] with the command when [availability] allows and no other
  /// request of [key] is on its way. False = nothing was sent. An error of
  /// [send] propagates (the history stays as it was).
  Future<bool> request(
    String key,
    CompactAvailability availability,
    Future<void> Function(String command) send, {
    String? focus,
  }) async {
    if (!availability.ok || !_inFlight.add(key)) return false;
    try {
      await send(compactCommand(focus));
      return true;
    } finally {
      _inFlight.remove(key);
    }
  }
}

final compactionControllerProvider = Provider<CompactionController>(
  (ref) => CompactionController(),
);
