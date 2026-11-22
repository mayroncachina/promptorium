/// App events of the context contract that the Codex adapter emits besides
/// the neutral readings and compactions (SPEC-107 R6, R10, R12). They are
/// stored with the session / conversation events like any other row
/// (`{"type":"promptorium_…","v":1,…}`) and read back by the context
/// tracker and its sources.
library;

abstract final class ContextAppEvents {
  /// Instruction files the agent says it loaded (`instructionSources` of
  /// `thread/start` / `thread/resume`, R10).
  static const instructions = 'promptorium_instructions';

  /// The model of the thread changed: rerouted by the service
  /// (`model/rerouted`) or by a settings update (`thread/settings/updated`)
  /// (R12).
  static const modelChange = 'promptorium_model_change';

  /// The compaction limit the agent reports as effective (`config/read`,
  /// R6) and its scope, shown as text (P2).
  static const agentConfig = 'promptorium_agent_config';

  /// `reason` of [modelChange].
  static const rerouted = 'rerouted';
  static const settings = 'settings';

  static Map<String, dynamic> instructionsEvent({
    required String provider,
    required List<String> sources,
    DateTime? at,
  }) => {
    'type': instructions,
    'v': 1,
    'provider': provider,
    'sources': sources,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

  static Map<String, dynamic> modelChangeEvent({
    required String provider,
    required String? from,
    required String to,
    required String reason,
    DateTime? at,
  }) => {
    'type': modelChange,
    'v': 1,
    'provider': provider,
    'from': ?from,
    'to': to,
    'reason': reason,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

  static Map<String, dynamic> agentConfigEvent({
    required String provider,
    int? autocompactLimit,
    String? autocompactScope,
    DateTime? at,
  }) => {
    'type': agentConfig,
    'v': 1,
    'provider': provider,
    'autocompact_limit': ?autocompactLimit,
    'autocompact_scope': ?autocompactScope,
    'source': 'config/read',
    'at': (at ?? DateTime.now()).toIso8601String(),
  };
}
