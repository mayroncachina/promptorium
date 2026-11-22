import '../../core/claude/claude_args.dart';
import '../../core/claude/run_prefs.dart';
import '../../core/providers/provider_preferences.dart';
import '../../core/providers/quota_source.dart';
import '../../core/providers/structured_run.dart';
import '../../data/providers.dart' show Session;

/// The provider of a spec run (SPEC-101): chosen at the first Executar and
/// fixed until the spec reaches Review (R2, P1 = `app_settings`).

/// `app_settings` key of the provider of [specId]'s run (P1): written by
/// the first Executar, removed when the spec reaches Review or is rewound.
String specProviderKey(int specId) => 'spec.$specId.provider';

/// `app_settings` key of the "Só Claude Code" note already written for
/// [specId]'s run (R5, R6: the timeline says it once).
String specClaudeOnlyNoteKey(int specId) => 'spec.$specId.claudeOnlyNote';

/// Provider recorded for [specId]'s run (null = none yet).
String? recordedSpecProvider(Map<String, String> settings, int specId) {
  final v = settings[specProviderKey(specId)];
  return v == null || v.isEmpty ? null : v;
}

/// Provider of the next session of [specId] (R2, R14): the recorded one >
/// the last session's (a run begun before this version) > the one asked
/// ([requested], the dialog of the first Executar) > the "Executar spec"
/// kind (SPEC-100 R9: kind > footer > `claude`).
String specRunProviderFor(
  Map<String, String> settings,
  int specId, {
  Session? last,
  String? requested,
  int? workspaceId,
  ProviderFlows flows = ProviderFlows.defaults,
}) =>
    recordedSpecProvider(settings, specId) ??
    last?.provider ??
    requested ??
    providerForKind(
      settings,
      ProviderKind.runSpec,
      workspaceId: workspaceId,
      flows: flows,
    );

/// Model ids of the Codex catalog (`model/list`, SPEC-094), empty when it
/// was never read.
List<String> codexCatalogModels(Map<String, String> settings) => [
  for (final m in codexModelsCache(settings)?.models ?? const []) m.id,
];

/// Efforts of [model] in the Codex catalog (`default` first); without the
/// catalog, only `default`.
List<String> codexModelEfforts(Map<String, String> settings, String model) {
  final m = codexModelsCache(settings)?.byId(model);
  return [defaultEffort, ...?m?.efforts.where((e) => e != defaultEffort)];
}

/// Whether [model] is one of the Claude choices (R3: never sent to Codex).
bool isClaudeModelChoice(String? model) =>
    model != null &&
    model != 'inherit' &&
    (RunPrefs.defaultModels.containsValue(model) ||
        const {'opus', 'sonnet', 'haiku', 'fable', 'max'}.contains(model));

/// Model of a Codex spec session (R3): [requested] when it is a Codex model
/// of the catalog, else `codex.model.session` when the catalog has it, else
/// the first model of the catalog. `inherit` only when the catalog was never
/// read (the session then records the thread's model, R11).
String codexRunModel(Map<String, String> settings, {String? requested}) {
  final catalog = codexCatalogModels(settings);
  bool ok(String? m) =>
      m != null &&
      m.isNotEmpty &&
      m != 'inherit' &&
      !isClaudeModelChoice(m) &&
      (catalog.isEmpty || catalog.contains(m));
  if (ok(requested)) return requested!;
  final saved = settings['codex.model.${RunKind.session.name}'];
  if (ok(saved)) return saved!;
  return catalog.firstOrNull ?? 'inherit';
}

/// Effort of a Codex spec session: [requested] when [model] takes it, else
/// `codex.effort.session` when it does, else `default`.
String codexRunEffort(
  Map<String, String> settings,
  String model, {
  String? requested,
}) {
  final efforts = codexModelEfforts(settings, model);
  if (requested != null && efforts.contains(requested)) return requested;
  final saved = settings['codex.effort.${RunKind.session.name}'];
  if (saved != null && efforts.contains(saved)) return saved;
  return defaultEffort;
}

/// Access modes of a Codex spec run (R4, decision 3): Editar and, with a
/// worktree, YOLO. Perguntar and Planejar do not run steps. Without the OS
/// sandbox, only YOLO runs (decision 15).
List<ClaudePermissionMode> codexRunModes({
  bool worktree = true,
  bool sandbox = true,
}) => [
  if (sandbox) ClaudePermissionMode.acceptEdits,
  if (worktree) ClaudePermissionMode.skipPermissions,
];

/// Mode of a Codex spec session (R4): [requested] when it is one of
/// [codexRunModes], else Editar (YOLO without the sandbox).
ClaudePermissionMode codexRunMode(
  ClaudePermissionMode? requested, {
  bool sandbox = true,
}) {
  final modes = codexRunModes(sandbox: sandbox);
  if (requested != null && modes.contains(requested)) return requested;
  return modes.first;
}

/// Share of the model's window a Codex session may fill before the next
/// step goes to a new session (P2).
const codexContinueWindowShare = 0.7;

/// Context limit for continuing in the same session (R10, P2): the limit of
/// Execução de specs, and for a provider that reports its window (the
/// Codex) at most 70% of it.
int effectiveContinueLimit(int limit, {String? provider, int? window}) {
  if (provider == null || isClaudeCode(provider) || window == null) {
    return limit;
  }
  final cap = (window * codexContinueWindowShare).floor();
  return cap < limit ? cap : limit;
}

/// Above this share of the 5-hour window the autopilot starts no new spec
/// on the Codex (R14, P3).
const codexAutopilotQuotaPercent = 90.0;

/// Why the autopilot holds new Codex specs (R14, P3): the 5-hour window
/// above 90% or a limit reached. Null = it may start them.
String? codexAutopilotBrake(QuotaSnapshot? quota, DateTime now) {
  if (quota == null) return null;
  final limit = quota.limit(now);
  final five = quota.window(300, fallbackId: 'primary');
  final pct = five?.usedPercent;
  if (limit != null) {
    return pct == null
        ? 'Autopilot parado: ${limit.words} do Codex atingido'
        : 'Autopilot parado: cota do Codex em ${pct.round()}%';
  }
  if (pct != null && pct > codexAutopilotQuotaPercent) {
    return 'Autopilot parado: cota do Codex em ${pct.round()}%';
  }
  return null;
}

/// "O agente spec-implementer e os subagentes desta spec são só do Claude
/// Code; o Codex executa sem eles" (R6).
String claudeOnlyAgentsNote({
  String? agent,
  required bool subagents,
  String provider = 'Codex',
}) {
  final hasAgent = agent != null && agent.isNotEmpty;
  final tail = 'só do Claude Code; o $provider executa sem';
  if (hasAgent && subagents) {
    return 'O agente $agent e os subagentes desta spec são $tail eles.';
  }
  if (hasAgent) return 'O agente $agent é $tail ele.';
  return 'Os subagentes desta spec são $tail eles.';
}

/// Timeline note when "Abrir Executar em Automático" meets a spec on the
/// Codex (R5).
const autoOnlyClaudeNote =
    'Automático é só do Claude Code: o Orquestrador escolhe modelos do '
    'Claude; com o Codex, as etapas rodam no modo Manual.';

/// Hint of the Automático segment with the Codex selected (R5).
const autoOnlyClaudeHint =
    'o Orquestrador escolhe modelos do Claude; com o Codex, as etapas rodam '
    'no modo Manual';

/// The run's provider fixed until Review (R2). SPEC-099 ("Passar para
/// outro agente") is not in this version: stopping is the way to switch.
String fixedProviderNotice(String displayName) =>
    'Esta spec fica no $displayName até chegar ao Review: etapas, reenvios '
    'do gate, correções e Corrigir CI. Para trocar no meio, pare a execução '
    '(Passar para outro agente chega com a SPEC-099).';

/// P4: the spec runs on [running] while the kind is now on another
/// provider.
String runningOnNotice(String displayName) =>
    'Esta spec está rodando no $displayName. Para trocar, pare a execução '
    '(Passar para outro agente chega com a SPEC-099).';

/// Label of a Codex mode in the Executar dialog (R4).
String codexRunModeLabel(ClaudePermissionMode mode) => switch (mode) {
  ClaudePermissionMode.acceptEdits => 'Editar · escreve com confirmação',
  ClaudePermissionMode.skipPermissions =>
    'YOLO · só em worktree, sem aprovações',
  ClaudePermissionMode.plan => 'Planejar · não executa etapas',
  _ => 'Perguntar · não executa etapas',
};
