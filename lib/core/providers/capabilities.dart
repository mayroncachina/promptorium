import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart' show appSettingsProvider;

/// How far a provider supports one [ProviderCapability] (SPEC-094 R1).
enum CapabilitySupport { supported, partial, unsupported }

/// What a provider can do, as declared by its adapter (SPEC-094 R1).
///
/// The app builds only intents; services and screens ask these before
/// offering a control or building an option, instead of comparing ids.
enum ProviderCapability {
  images('Imagens nos prompts'),
  structuredOutput('Saída estruturada'),
  budgetUsd('Limite em US\$'),
  maxTurns('Limite de turnos'),
  planMode('Modo planejar'),
  readOnlyEnforced('Somente leitura imposta'),
  managedHooks('Hooks gerenciados'),
  agentFiles('Agentes .claude/agents'),
  subagents('Subagentes'),
  mcpConfig('Configuração de MCP'),
  appMcpServer('MCP do app'),
  compactNow('Compactar agora'),
  steerMidTurn('Interromper e direcionar'),
  liveApprovalChange('Mudar aprovação durante a sessão'),
  quota('Cota do plano'),
  costUsd('Custo em US\$'),
  nativeReview('Review nativo'),
  revertConversation('Desfazer turnos da conversa'),

  /// Reads the project's `CLAUDE.md` (SPEC-104 R1): natively in the Claude
  /// Code, by `project_doc_fallback_filenames` in the Codex. False = plano
  /// B, the app offers a generated `AGENTS.md` (R3).
  instructionsFallback('Lê o CLAUDE.md do projeto'),

  /// Sees the skills of `.claude/skills` and `~/.claude/skills` (SPEC-104
  /// R6): natively in the Claude Code, by `skills/extraRoots/set` in the
  /// Codex. False = plano B, "Disponibilizar no Codex" (R10).
  skillsExtraRoots('Skills do .claude/skills');

  const ProviderCapability(this.label);

  final String label;
}

/// One capability value: support level plus a one-line reason (shown in the
/// "Só Claude Code" hint, R11) when it is partial or unsupported.
@immutable
class CapabilityValue {
  const CapabilityValue.supported([this.reason])
    : support = CapabilitySupport.supported;
  const CapabilityValue.partial(String this.reason)
    : support = CapabilitySupport.partial;
  const CapabilityValue.unsupported(String this.reason)
    : support = CapabilitySupport.unsupported;

  final CapabilitySupport support;
  final String? reason;

  /// Partial counts as available: the adapter does what it can and the
  /// screen shows the reason.
  bool get available => support != CapabilitySupport.unsupported;

  @override
  bool operator ==(Object other) =>
      other is CapabilityValue &&
      other.support == support &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(support, reason);
}

/// Declared capabilities of one provider (and, after [forModel], of one of
/// its models: only `images` and the efforts vary by model, P5).
@immutable
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.providerId,
    required this.displayName,
    required this.values,
    this.efforts,
  });

  final String providerId;

  /// Name used in hints ("O Codex não tem limite em US$").
  final String displayName;

  /// Declared values; missing ones count as unsupported.
  final Map<ProviderCapability, CapabilityValue> values;

  /// Efforts accepted by the model; null = the provider's fixed list.
  final List<String>? efforts;

  /// Missing entries count as unsupported: "não testada" = não suportada
  /// (R2).
  CapabilityValue operator [](ProviderCapability c) =>
      values[c] ?? const CapabilityValue.unsupported('não testada');

  bool supports(ProviderCapability c) => this[c].available;

  /// One-line reason of a missing capability, for the hint of the tag.
  String reasonFor(ProviderCapability c) =>
      this[c].reason ?? '$displayName não oferece ${c.label.toLowerCase()}.';

  /// Model override (P5): image modality and efforts come from `model/list`.
  ProviderCapabilities forModel({
    List<String>? modalities,
    List<String>? efforts,
  }) => ProviderCapabilities(
    providerId: providerId,
    displayName: displayName,
    values: {
      ...values,
      if (modalities != null)
        ProviderCapability.images: modalities.contains('image')
            ? const CapabilityValue.supported()
            : CapabilityValue.unsupported(
                'Este modelo do $displayName não aceita imagens.',
              ),
    },
    efforts: efforts ?? this.efforts,
  );

  /// Claude Code: what the app already uses with the CLI (R2).
  static const claude = ProviderCapabilities(
    providerId: 'claude',
    displayName: 'Claude Code',
    values: {
      ProviderCapability.images: CapabilityValue.supported(),
      ProviderCapability.structuredOutput: CapabilityValue.supported(),
      ProviderCapability.budgetUsd: CapabilityValue.supported(),
      ProviderCapability.maxTurns: CapabilityValue.supported(),
      ProviderCapability.planMode: CapabilityValue.supported(),
      ProviderCapability.readOnlyEnforced: CapabilityValue.supported(
        'lista de ferramentas de leitura',
      ),
      ProviderCapability.managedHooks: CapabilityValue.supported(),
      ProviderCapability.agentFiles: CapabilityValue.supported(),
      ProviderCapability.subagents: CapabilityValue.supported(),
      ProviderCapability.mcpConfig: CapabilityValue.supported(),
      ProviderCapability.appMcpServer: CapabilityValue.supported(),
      ProviderCapability.compactNow: CapabilityValue.supported(),
      ProviderCapability.steerMidTurn: CapabilityValue.supported(),
      ProviderCapability.liveApprovalChange: CapabilityValue.supported(),
      ProviderCapability.quota: CapabilityValue.supported(),
      ProviderCapability.costUsd: CapabilityValue.supported(),
      ProviderCapability.nativeReview: CapabilityValue.unsupported(
        'O Claude Code não tem review nativo pelo app.',
      ),
      // SPEC-110 R7: the CLI has no way back in the stream-json mode.
      ProviderCapability.revertConversation: CapabilityValue.unsupported(
        'o Claude Code não volta a conversa no modo do app; o agente recebe '
        'o aviso.',
      ),
      ProviderCapability.instructionsFallback: CapabilityValue.supported(
        'nativo',
      ),
      ProviderCapability.skillsExtraRoots: CapabilityValue.supported('nativo'),
    },
    efforts: ['default', 'low', 'medium', 'high', 'xhigh', 'max'],
  );

  /// Codex 0.170: the table "Capacidades comprovadas no 0.170" of SPEC-093
  /// (`docs/pesquisa/codex-0170.md`). Untested = unsupported (R2).
  static const codex = ProviderCapabilities(
    providerId: 'codex',
    displayName: 'Codex',
    values: {
      ProviderCapability.images: CapabilityValue.supported('por modelo'),
      ProviderCapability.structuredOutput: CapabilityValue.supported(),
      ProviderCapability.budgetUsd: CapabilityValue.unsupported(
        'O Codex não tem limite em US\$.',
      ),
      ProviderCapability.maxTurns: CapabilityValue.unsupported(
        'O Codex não tem limite de turnos.',
      ),
      ProviderCapability.planMode: CapabilityValue.unsupported(
        'O Codex não tem modo planejar: Planejar roda em somente leitura.',
      ),
      ProviderCapability.readOnlyEnforced: CapabilityValue.partial('sandbox'),
      ProviderCapability.managedHooks: CapabilityValue.unsupported(
        'O Codex não roda hooks do app sem confiança no global.',
      ),
      // SPEC-106: the app translates the agent (instructions, model,
      // effort and sandbox); the rest is said as ignored.
      ProviderCapability.agentFiles: CapabilityValue.partial(
        'traduzido pelo app: instruções, modelo, esforço e sandbox',
      ),
      ProviderCapability.subagents: CapabilityValue.unsupported(
        'Subagentes do Codex não foram testados.',
      ),
      ProviderCapability.mcpConfig: CapabilityValue.partial(
        'desligar e Bloqueado',
      ),
      // SPEC-105 R7: by override of the run, only the read tools.
      ProviderCapability.appMcpServer: CapabilityValue.partial(
        'só ferramentas de leitura',
      ),
      ProviderCapability.compactNow: CapabilityValue.supported(
        'gasta uma chamada',
      ),
      ProviderCapability.steerMidTurn: CapabilityValue.partial(
        'direcionar sem efeito observado',
      ),
      ProviderCapability.liveApprovalChange: CapabilityValue.supported(
        'entre turnos',
      ),
      ProviderCapability.quota: CapabilityValue.supported(),
      ProviderCapability.costUsd: CapabilityValue.unsupported(
        'O Codex informa só tokens, sem custo em US\$.',
      ),
      ProviderCapability.nativeReview: CapabilityValue.unsupported(
        'O review nativo do Codex não foi testado.',
      ),
      // SPEC-110: `thread/revert` (and `thread/fork` for the copy), checked
      // on the 0.170 App Server without a model call.
      ProviderCapability.revertConversation: CapabilityValue.supported(
        'thread/revert',
      ),
      // SPEC-093 R10 and the SPEC-104 probe (`skills.jsonl`): both work by
      // override of the run, nothing written in ~/.codex.
      ProviderCapability.instructionsFallback: CapabilityValue.supported(
        'project_doc_fallback_filenames',
      ),
      ProviderCapability.skillsExtraRoots: CapabilityValue.supported(
        'skills/extraRoots/set',
      ),
    },
  );

  /// ACP agents: the minimum until someone proves more (R2).
  static ProviderCapabilities acp(String id, String displayName) =>
      ProviderCapabilities(
        providerId: id,
        displayName: displayName,
        values: const {ProviderCapability.images: CapabilityValue.supported()},
        efforts: const ['default'],
      );
}

/// App flows a provider may run in (R3).
enum AppFlow {
  prompt('Prompt'),
  sessions('Sessões'),
  runSpec('Executar spec'),
  autoReview('Review automático'),
  structured('Execuções estruturadas'),
  compare('Comparar'),
  prototype('Protótipo de telas');

  const AppFlow(this.label);

  final String label;
}

/// Which flows each provider is released in (R3). Replaces the global
/// `codexEnabledProvider` switch: each spec of the epic turns on its flows
/// (SPEC-096 turns on Prompt and Sessions for Codex).
@immutable
class ProviderFlows {
  const ProviderFlows(
    this.enabled, {
    this.others = acpFlows,
    this.off = const {},
  });

  final Map<String, Set<AppFlow>> enabled;

  /// Providers turned off by the user in Configurações ("Desligar o Codex",
  /// SPEC-096 P1): no flow runs them, and the reason is the switch.
  final Set<String> off;

  /// Flows of providers not listed (ACP agents): what they ran in before.
  final Set<AppFlow> others;

  static const acpFlows = {
    AppFlow.prompt,
    AppFlow.structured,
    AppFlow.autoReview,
  };

  /// Codex runs in Prompt, Sessões (SPEC-096 R1), the structured runs
  /// (SPEC-100 R8), Executar spec (SPEC-101 R1) and the automatic reviewer
  /// (SPEC-102); the other flows wait for their specs (108).
  static const defaults = ProviderFlows({
    'claude': {...AppFlow.values},
    'codex': codexFlows,
  });

  /// Flows released for the Codex in this version (SPEC-096 R1, SPEC-100
  /// R8, SPEC-101 R1, SPEC-102).
  static const codexFlows = {
    AppFlow.prompt,
    AppFlow.sessions,
    AppFlow.structured,
    AppFlow.runSpec,
    AppFlow.autoReview,
  };

  bool allows(String provider, AppFlow flow) =>
      (enabled[provider] ?? others).contains(flow);

  /// Whether the provider runs anywhere at all.
  bool anyFor(String provider) => (enabled[provider] ?? others).isNotEmpty;

  ProviderFlows copyWith(String provider, Set<AppFlow> flows) =>
      ProviderFlows({...enabled, provider: flows}, others: others, off: off);

  /// [provider] turned off in Configurações: no flow at all.
  ProviderFlows turnOff(String provider) => ProviderFlows(
    {...enabled, provider: const {}},
    others: others,
    off: {...off, provider},
  );

  /// Whether the user turned [provider] off in Configurações.
  bool isOff(String provider) => off.contains(provider);

  /// Why [flow] refuses [provider] (R12): the switch of Configurações when
  /// the user turned it off, else the flow not released yet.
  String refusal(String provider, String displayName, AppFlow flow) =>
      isOff(provider)
      ? providerOffMessage(displayName)
      : flowLockedMessage(displayName, flow);
}

/// `app_settings` key of the emergency switch (SPEC-096 P1): `1` turns the
/// Codex off in every flow without a new version.
const codexKillSwitchKey = 'codex.desligado';

/// The spec that releases each flow still locked for the Codex (mock 4).
const codexFlowSpecs = {AppFlow.compare: 'SPEC-108'};

/// The flow registry (tests override it to turn Codex flows on). The
/// emergency switch removes every Codex flow (P1).
final providerFlowsProvider = Provider<ProviderFlows>((ref) {
  final off = ref.watch(
    appSettingsProvider.select((s) => s[codexKillSwitchKey] == '1'),
  );
  return off ? ProviderFlows.defaults.turnOff('codex') : ProviderFlows.defaults;
});

/// Label of a provider turned off in Configurações (SPEC-096 P1).
const providerOffLabel = 'Desligado nas Configurações';

/// Message when something tries to run a provider turned off in
/// Configurações (SPEC-096 P1).
String providerOffMessage(String displayName) =>
    'O $displayName está desligado nas Configurações '
    '(Desligar o $displayName). Escolha o Claude Code ou religue o '
    '$displayName em Configurações → Consumo.';

/// "Codex · Só Claude Code por enquanto" (R11): label of a provider not
/// released in a flow.
String flowLockedLabel(String displayName) =>
    '$displayName · Só Claude Code por enquanto';

/// Message when a flow refuses a provider (R12): never switches by itself.
String flowLockedMessage(String displayName, AppFlow flow) =>
    '${flow.label} ainda não roda com o $displayName. '
    'Escolha o Claude Code nesta execução; nada troca de provedor sozinho.';

/// Whether [providerId] is the Claude Code adapter: for dispatch to the
/// Claude CLI process and its own state (rate limits, hooks), not for
/// deciding features — those ask [ProviderCapabilities] (R13).
bool isClaudeCode(String providerId) =>
    providerId == ProviderCapabilities.claude.providerId;

/// Declared capabilities of a provider id without the registry.
ProviderCapabilities capabilitiesFor(String providerId, {String? name}) =>
    switch (providerId) {
      'claude' => ProviderCapabilities.claude,
      'codex' => ProviderCapabilities.codex,
      _ => ProviderCapabilities.acp(providerId, name ?? providerId),
    };
