import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../features/cost/usage_ledger.dart';
import '../claude/claude_event.dart';
import '../claude/readonly_run.dart';
import '../claude/run_prefs.dart';
import '../claude/usage_tracker.dart';
import '../codex/codex_probe.dart' show codexNoSandboxMessage;
import '../codex/codex_provider.dart' show CodexRun;
import '../codex/codex_rpc.dart' show CodexRpc;
import 'agent_registry.dart';
import 'provider_availability.dart';
import 'provider_preferences.dart';
import 'structured_schema.dart';

export '../claude/readonly_run.dart'
    show PlannerException, plannerTimeout, structuredOutput;
export 'capabilities.dart';
export 'structured_schema.dart';

/// Execuções estruturadas (SPEC-100): one read-only round that answers with
/// JSON validated by a schema, on any provider.
///
/// Services describe the run with a [StructuredIntent] and call
/// [runStructured]; none of them builds `ClaudeOptions`. Options only one
/// provider has go in [StructuredIntent.claude] and reach that adapter only
/// (R1). The SPECs 101 and 102 reuse this entry point: Executar spec for
/// "Decidir na etapa" and the reviewer, each with its own [ProviderKind].

/// Model profile of a run (R4): callers ask for a profile, never a model
/// name, and each provider resolves it from its own catalog.
enum StructuredProfile {
  /// The model and effort of the run kind (`<provedor>.model.planner`).
  standard,

  /// A quick check (the VIBE guard): Claude = Haiku · low; Codex = the
  /// model of the kind with effort `low` (P2 b).
  fast,
}

/// Options only the Claude Code takes (R1): the Claude adapter applies them;
/// no other provider ever receives them.
@immutable
class ClaudeStructuredExtras {
  const ClaudeStructuredExtras({
    this.model,
    this.effort,
    this.maxBudgetUsd,
    this.maxTurns,
    this.agent,
    this.tools = const [],
    this.allowedTools = const [],
    this.disallowedTools,
    this.settingsFile,
  });

  /// A Claude alias or id (`haiku`, `opus`): Claude only (R4).
  final String? model;
  final String? effort;
  final double? maxBudgetUsd;
  final int? maxTurns;

  /// `.claude/agents` agent (decisão 7: Claude only).
  final String? agent;

  /// `--tools`; empty = the read-only list.
  final List<String> tools;

  /// `--allowedTools` (the prototype's write rule, SPEC-022 R2).
  final List<String> allowedTools;

  /// `--disallowedTools`; null = the read-only list.
  final List<String>? disallowedTools;
  final String? settingsFile;
}

/// Who runs a kind of execution (R9): one row of "Provedor por tipo".
enum ProviderKind {
  planner(
    'Planner e assistentes',
    'Projeto, Nova spec, Dividir, Perguntas, Design, Verificar, Nova skill, '
        'Decidir na etapa',
    AppFlow.structured,
  ),
  sessions('Sessões e Prompt', 'Nova sessão, conversas, VIBE', AppFlow.prompt),
  runSpec('Executar spec', 'Etapas, gate, Autopilot', AppFlow.runSpec),
  reviewer(
    'Revisor automático',
    'Revisão da spec terminada',
    AppFlow.autoReview,
  );

  const ProviderKind(this.label, this.hint, this.flow);

  final String label;
  final String hint;

  /// The flow whose release decides whether the row is editable.
  final AppFlow flow;

  /// `app_settings` key of the choice (R9): absent = follow the footer.
  String get settingKey => 'agent.provider.kind.$name';

  /// Rows editable in this version: the others show their state (R9).
  /// SPEC-101 R1 releases "Executar spec".
  static const editable = {planner, runSpec};
}

/// The [ProviderKind] of a structured flow.
ProviderKind providerKindOf(AppFlow flow) => switch (flow) {
  AppFlow.autoReview => ProviderKind.reviewer,
  AppFlow.runSpec => ProviderKind.runSpec,
  AppFlow.prompt || AppFlow.sessions => ProviderKind.sessions,
  _ => ProviderKind.planner,
};

/// Saved choice of [kind]: `claude`, `codex` or null (follow the footer).
String? providerKindChoice(Map<String, String> settings, ProviderKind kind) {
  if (!ProviderKind.editable.contains(kind)) return null;
  final v = settings[kind.settingKey];
  return v == null || v.isEmpty || v == 'follow' ? null : v;
}

/// Provider of a new run of [kind] (R9): the kind's choice > the footer of
/// the workspace > the global default > `claude`. A kind explicitly on a
/// provider keeps it, even unavailable (R11: the run fails and says why).
String providerForKind(
  Map<String, String> settings,
  ProviderKind kind, {
  int? workspaceId,
  ProviderFlows flows = ProviderFlows.defaults,
}) {
  final chosen = providerKindChoice(settings, kind);
  if (chosen != null) return chosen;
  final footer =
      settings[providerPreferenceKey(workspaceId)] ??
      settings[providerPreferenceKey(null)] ??
      'claude';
  // A locked row ("Só Claude Code" in the card) runs on the Claude Code;
  // an editable row never switches: the run says why it cannot go.
  if (!ProviderKind.editable.contains(kind) &&
      !flows.allows(footer, kind.flow) &&
      !flows.isOff(footer)) {
    return ProviderCapabilities.claude.providerId;
  }
  return footer;
}

/// What one structured run is (R1): the app's intent, not provider flags.
@immutable
class StructuredIntent {
  const StructuredIntent({
    required this.cwd,
    required this.prompt,
    this.schema,
    this.instructions,
    this.images = const [],
    this.kind = RunKind.planner,
    this.profile = StructuredProfile.standard,
    this.sessionId,
    this.resumeId,
    this.forkSession = false,
    this.timeout = plannerTimeout,
    this.cancelled,
    this.workspaceId,
    this.specId,
    this.specCode,
    this.usageSource,
    this.usageStep,
    this.denyMessage = 'O planner do Promptorium é somente leitura.',
    this.flow = AppFlow.structured,
    this.providerId,
    this.claude = const ClaudeStructuredExtras(),
    this.slot,
    this.label,
  });

  final String cwd;
  final String prompt;

  /// The answer's JSON Schema (null = free text in [StructuredResult.text]).
  final Map<String, Object?>? schema;

  /// System instructions: `--append-system-prompt` on the Claude Code,
  /// `developerInstructions` on the Codex (R4).
  final String? instructions;

  /// Prints of "Nova spec" (SPEC-083 R6), as image input (R6).
  final List<ImagePart> images;

  /// Model and effort come from this kind's preferences (R4).
  final RunKind kind;
  final StructuredProfile profile;

  /// New local id of the round (`agent.run.<id>.*`), to continue it later.
  final String? sessionId;

  /// Round to continue (R7): it runs on its own provider and thread.
  final String? resumeId;
  final bool forkSession;

  /// Limit of the round (R5, P4: the caller's own).
  final Duration timeout;

  /// Completing it interrupts the round: a cancellation, not a failure.
  final Future<void>? cancelled;

  /// Origin of the usage (R12, SPEC-081 R2).
  final int? workspaceId;
  final int? specId;
  final String? specCode;
  final UsageSource? usageSource;
  final String? usageStep;

  /// Answer to any permission request (R2).
  final String denyMessage;

  /// The flow, for the release of each provider (SPEC-094 R3).
  final AppFlow flow;

  /// Provider chosen for this run (a dialog, "Usar o Claude Code desta
  /// vez", or a flow only the Claude Code runs). Null = the kind's (R9).
  final String? providerId;
  final ClaudeStructuredExtras claude;

  /// Where the dialog of the flow reads the run's provider line (R10).
  final String? slot;

  /// Name of the flow in messages ("a Nova spec").
  final String? label;

  StructuredIntent copyWith({String? providerId, List<ImagePart>? images}) =>
      StructuredIntent(
        cwd: cwd,
        prompt: prompt,
        schema: schema,
        instructions: instructions,
        images: images ?? this.images,
        kind: kind,
        profile: profile,
        sessionId: sessionId,
        resumeId: resumeId,
        forkSession: forkSession,
        timeout: timeout,
        cancelled: cancelled,
        workspaceId: workspaceId,
        specId: specId,
        specCode: specCode,
        usageSource: usageSource,
        usageStep: usageStep,
        denyMessage: denyMessage,
        flow: flow,
        providerId: providerId ?? this.providerId,
        claude: claude,
        slot: slot,
        label: label,
      );
}

/// What a structured round produced (R1).
@immutable
class StructuredResult {
  const StructuredResult({
    required this.raw,
    required this.provider,
    required this.model,
    required this.elapsed,
    this.externalId,
    this.switchedFrom,
  });

  /// The `result` event. On providers without a separate structured field
  /// (Codex) it carries the validated answer in `structured_output`.
  final Result raw;

  /// Who ran it, and the model it reported.
  final String provider;
  final String? model;

  /// The provider's own id of the round (Claude session, Codex thread).
  final String? externalId;

  /// R11: the provider of the kind, when this run went to another one.
  final String? switchedFrom;
  final Duration elapsed;

  /// The validated answer. Throws [PlannerException] when the round failed.
  Object? get data => structuredOutput(raw);

  /// Final text of the round.
  String? get text => raw.result;
  bool get isSuccess => raw.isSuccess;
  Usage get usage => raw.usage;
  int get reasoningTokens => reasoningTokensOf(raw);

  /// US$ of the round, only when the provider reports it (R12, decisão 5).
  double? get costUsd => providerHasCost(provider) ? raw.totalCostUsd : null;
}

/// The round was cancelled (R5): not a failure.
class StructuredCancelled extends PlannerException {
  const StructuredCancelled([super.message = 'Verificação cancelada.']);
}

/// The provider could not run (R11): says which one and why, and which
/// provider "desta vez" may run it instead. Nothing switches by itself.
/// The model of the run does not read images (R6): the dialog warns and
/// offers to send without the prints or to use the other provider this
/// time. The prints are never dropped silently.
class StructuredImagesUnsupported extends PlannerException {
  const StructuredImagesUnsupported(
    super.message, {
    required this.provider,
    required this.model,
    required this.count,
  });

  final String provider;
  final String? model;

  /// How many prints the request has.
  final int count;
}

class StructuredProviderFailure extends PlannerException {
  const StructuredProviderFailure(
    super.message, {
    required this.provider,
    required this.reason,
    this.alternative,
  });

  final String provider;
  final String reason;

  /// The other provider offered in "Usar o … desta vez".
  final String? alternative;
}

/// The other provider offered by R11 (Claude Code ↔ Codex).
String? alternativeProvider(String provider) => switch (provider) {
  'claude' => 'codex',
  'codex' => 'claude',
  _ => 'claude',
};

/// "Codex" / "Claude Code".
String providerDisplayName(String id) => capabilitiesFor(id).displayName;

/// One run as its dialog shows it (R10).
@immutable
class StructuredRunInfo {
  const StructuredRunInfo({
    required this.provider,
    required this.model,
    this.running = true,
    this.tokens,
    this.costUsd,
    this.elapsed,
    this.switchedFrom,
    this.resumed = false,
    this.failure,
  });

  final String provider;
  final String? model;
  final bool running;

  /// Why the run did not finish (R6, R11): the dialog offers the choices.
  final PlannerException? failure;
  final int? tokens;
  final double? costUsd;
  final Duration? elapsed;
  final String? switchedFrom;

  /// It continues a round of before, on that round's provider (R7).
  final bool resumed;
}

/// A choice that holds for the next run of a slot only (R6, R11): "Usar o
/// Claude Code desta vez" or "Enviar sem os prints". The saved preference
/// never changes.
typedef StructuredOnce = ({String? provider, bool dropImages});

/// Runs by [StructuredIntent.slot] (R10): the dialogs watch their slot.
class StructuredRuns extends Notifier<Map<String, StructuredRunInfo>> {
  @override
  Map<String, StructuredRunInfo> build() => const {};

  final _once = <String, StructuredOnce>{};

  /// The next run of [slot] goes to [provider] and/or without images.
  void once(String slot, {String? provider, bool dropImages = false}) =>
      _once[slot] = (provider: provider, dropImages: dropImages);

  /// The pending choice of [slot], without using it.
  StructuredOnce? peekOnce(String slot) => _once[slot];

  StructuredOnce? takeOnce(String slot) => _once.remove(slot);

  void put(String slot, StructuredRunInfo info) {
    if (ref.mounted) state = {...state, slot: info};
  }

  void clear(String slot) {
    if (ref.mounted && state.containsKey(slot)) {
      state = {...state}..remove(slot);
    }
  }
}

final structuredRunsProvider =
    NotifierProvider<StructuredRuns, Map<String, StructuredRunInfo>>(
      StructuredRuns.new,
    );

/// Provider of a run (R7, R9): the original round's on a continuation >
/// the run's own choice > the kind > the footer > `claude`.
String structuredProviderFor(Ref ref, StructuredIntent intent, int? ws) {
  final settings = ref.read(appSettingsProvider);
  if (intent.resumeId case final id?) {
    return settings['agent.run.$id.provider'] ?? 'claude';
  }
  if (intent.providerId case final id?) return id;
  return structuredKindProvider(ref, intent, ws);
}

/// The provider the kind gives [intent] (R9), ignoring its own choice.
String structuredKindProvider(Ref ref, StructuredIntent intent, int? ws) {
  final settings = ref.read(appSettingsProvider);
  return providerForKind(
    settings,
    providerKindOf(intent.flow),
    workspaceId: ws,
    flows: ref.read(providerFlowsProvider),
  );
}

/// Runs one structured round (R1–R12) and returns its validated answer.
///
/// Throws [StructuredProviderFailure] when the provider cannot start (R11),
/// [StructuredCancelled] when [StructuredIntent.cancelled] completes, and
/// [PlannerException] when the round fails, times out or answers outside
/// the schema (R3).
Future<StructuredResult> runStructured(
  Ref ref,
  StructuredIntent intent, {
  String? switchedFrom,
}) async {
  final ws = intent.workspaceId ?? ref.read(activeWorkspaceProvider)?.id;
  final runs = ref.read(structuredRunsProvider.notifier);
  if (intent.slot case final slot?) {
    // R6, R11: a choice "desta vez" holds for this run only; a
    // continuation stays where its round started (R7).
    final once = runs.takeOnce(slot);
    if (once != null) {
      final kind = structuredProviderFor(ref, intent, ws);
      if (once.provider != null &&
          intent.resumeId == null &&
          once.provider != kind) {
        switchedFrom ??= kind;
        intent = intent.copyWith(providerId: once.provider);
      }
      if (once.dropImages) intent = intent.copyWith(images: const []);
    }
  }
  final chosen = structuredProviderFor(ref, intent, ws);
  final settings = ref.read(appSettingsProvider.notifier);
  final name = providerDisplayName(chosen);
  if (intent.sessionId != null) {
    await settings.set('agent.run.${intent.sessionId}.provider', chosen);
  }
  final started = DateTime.now();
  final claude = isClaudeCode(chosen);
  final StructuredStart start;
  try {
    if (claude) {
      start = await startClaudeStructured(ref, intent);
    } else {
      final provider = agentProviderForFlow(ref, chosen, intent.flow);
      // Decisão 15: without the sandbox the Codex only runs in a worktree
      // with full access, which a read-only round never has.
      // Read only when already probed: a run never starts the probe.
      final probe = providerAvailabilityProvider(chosen);
      if (chosen == ProviderCapabilities.codex.providerId &&
          ref.exists(probe) &&
          ref.read(probe).value?.sandboxWarning != null) {
        throw AgentUnavailable(codexNoSandboxMessage());
      }
      start = await startProviderStructured(ref, provider, intent);
    }
  } catch (e) {
    final reason = '$e';
    final failure = StructuredProviderFailure(
      'Falha ao iniciar $name: $reason',
      provider: chosen,
      reason: reason,
      alternative: alternativeProvider(chosen),
    );
    if (intent.slot case final slot?) {
      runs.put(
        slot,
        StructuredRunInfo(
          provider: chosen,
          model: null,
          running: false,
          failure: failure,
          switchedFrom: switchedFrom,
        ),
      );
    }
    throw failure;
  }
  final process = start.run;
  if (intent.images.isNotEmpty &&
      process is CodexRun &&
      !process.supportsImages) {
    await process.stop(timeout: const Duration(seconds: 2));
    final m = process.model ?? start.model;
    final failure = StructuredImagesUnsupported(
      'O modelo ${m ?? 'padrão'} do $name não lê imagens.',
      provider: chosen,
      model: m,
      count: intent.images.length,
    );
    if (intent.slot case final slot?) {
      runs.put(
        slot,
        StructuredRunInfo(
          provider: chosen,
          model: m,
          running: false,
          failure: failure,
        ),
      );
    }
    throw failure;
  }
  var model = start.model;
  final slot = intent.slot;
  void publish(StructuredRunInfo info) {
    if (slot != null) runs.put(slot, info);
  }

  publish(
    StructuredRunInfo(
      provider: chosen,
      model: model,
      switchedFrom: switchedFrom,
      resumed: intent.resumeId != null,
    ),
  );
  final done = Completer<Result>();
  final logSub = process.logs.listen(
    (l) => debugPrint('planner: $l'),
    onError: (_) {},
  );
  final sub = process.events.listen(
    (e) {
      switch (e) {
        case SystemInit():
          final key = intent.sessionId ?? intent.resumeId;
          if (key != null && e.sessionId != null) {
            unawaited(settings.set('agent.run.$key.externalId', e.sessionId!));
          }
          if (!claude && e.model.isNotEmpty && e.model != 'inherit') {
            model = e.model;
            publish(
              StructuredRunInfo(
                provider: chosen,
                model: model,
                switchedFrom: switchedFrom,
                resumed: intent.resumeId != null,
              ),
            );
          }
        case PermissionRequest():
          // Non-interactive and read-only: nothing to approve (R2).
          process.deny(e.requestId, intent.denyMessage);
        case Result():
          if (!done.isCompleted) done.complete(e);
        case RateLimit():
          // R12: the Codex quota goes to its own source (SPEC-097), never
          // to the Claude tracker.
          if (claude) ref.read(usageTrackerProvider).handle(e);
        default:
          break;
      }
    },
    onDone: () {
      if (!done.isCompleted) {
        done.completeError(
          PlannerException('O provedor $chosen encerrou antes de responder.'),
        );
      }
    },
  );
  var cancelled = false;
  Future<void> interrupt() async {
    // R5: the Codex turn is interrupted before the process goes.
    if (!claude && process is ManagedAgentRun) {
      try {
        await process.interrupt().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  final response = done.future.timeout(
    intent.timeout,
    onTimeout: () async {
      await interrupt();
      throw PlannerException(
        'O planner não respondeu em ${intent.timeout.inMinutes} minutos.',
      );
    },
  );
  // Cancellation can arrive while send is still flushing. Attach an error
  // listener now; awaiting response below still propagates the failure.
  response.ignore();
  var finished = false;
  if (intent.cancelled case final cancel?) {
    unawaited(
      cancel.then((_) async {
        if (finished) return;
        cancelled = true;
        if (!done.isCompleted) done.completeError(const StructuredCancelled());
        await interrupt();
        await process.stop(timeout: const Duration(seconds: 2));
      }),
    );
  }
  try {
    await process.send(intent.prompt, images: intent.images);
    var result = await response;
    final elapsed = DateTime.now().difference(started);
    debugPrint(
      'planner: $chosen · ${model ?? 'padrão'} · ${elapsed.inSeconds} s',
    );
    await ref
        .read(usageLedgerProvider)
        .record(
          workspaceId: ws,
          specId: intent.specId,
          specCode: intent.specCode,
          source:
              intent.usageSource ??
              (intent.specId == null && intent.specCode == null
                  ? UsageSource.livre
                  : UsageSource.outros),
          step: intent.usageStep,
          model: resultModel(result, claude ? start.model : model),
          usage: result.usage,
          costUsd: result.totalCostUsd,
          provider: chosen,
          reasoningTokens: reasoningTokensOf(result),
        );
    if (result.isInterrupted && cancelled) throw const StructuredCancelled();
    if (!claude && intent.schema != null) {
      result = validatedResult(result, intent.schema!, provider: name);
    }
    final out = StructuredResult(
      raw: result,
      provider: chosen,
      model: claude ? resultModel(result, start.model) : model,
      elapsed: elapsed,
      externalId: result.json['session_id'] as String?,
      switchedFrom: switchedFrom,
    );
    publish(
      StructuredRunInfo(
        provider: chosen,
        model: out.model,
        running: false,
        tokens: result.usage.total,
        costUsd: out.costUsd,
        elapsed: elapsed,
        switchedFrom: switchedFrom,
        resumed: intent.resumeId != null,
      ),
    );
    return out;
  } catch (e) {
    if (slot != null) {
      if (e is PlannerException && e is! StructuredCancelled) {
        runs.put(
          slot,
          StructuredRunInfo(
            provider: chosen,
            model: model,
            running: false,
            failure: e,
            switchedFrom: switchedFrom,
            resumed: intent.resumeId != null,
          ),
        );
      } else {
        runs.clear(slot);
      }
    }
    rethrow;
  } finally {
    finished = true;
    await process.stop(timeout: const Duration(seconds: 2));
    await sub.cancel();
    await logSub.cancel();
  }
}

/// A started round: the process and the model it was asked to use.
typedef StructuredStart = ({AgentRun run, String? model});

/// Starts a structured round on a provider other than the Claude Code: the
/// read-only intent (Perguntar), the kind's model and effort of that
/// provider, the strict variant of the schema and none of the Claude
/// extras (R1–R5).
Future<StructuredStart> startProviderStructured(
  Ref ref,
  AgentProvider provider,
  StructuredIntent intent,
) async {
  final id = provider.id;
  final caps = provider.capabilities;
  final settings = ref.read(appSettingsProvider);
  final model = providerModel(ref, id, intent.kind);
  var effort = effortArg(providerEffort(ref, id, intent.kind));
  if (intent.profile == StructuredProfile.fast) {
    // P2 (b): the kind's model with effort `low`, when it has one.
    final efforts = id == ProviderCapabilities.codex.providerId
        ? codexModelsCache(settings)?.byId(model)?.efforts
        : caps.efforts;
    // An unknown catalog keeps the kind's effort: the App Server refuses
    // an effort the model does not have.
    effort = efforts != null && efforts.contains('low') ? 'low' : effort;
  }
  final resume = intent.resumeId;
  final run = await provider.start(
    AgentStartOptions(
      workingDirectory: intent.cwd,
      mode: PromptMode.ask,
      model: model,
      effort: effort,
      resumeId: resume == null
          ? null
          : settings['agent.run.$resume.externalId'] ?? resume,
      forkSession: intent.forkSession,
      appendSystemPrompt: intent.instructions,
      jsonSchema:
          intent.schema != null &&
              caps.supports(ProviderCapability.structuredOutput)
          ? jsonEncode(
              id == ProviderCapabilities.codex.providerId
                  ? codexCompatibleSchema(intent.schema!)
                  : intent.schema,
            )
          : null,
    ),
  );
  return (run: run, model: model == 'inherit' ? null : model);
}

/// The answer of a provider without CLI-side validation, parsed and checked
/// against [schema] (R3). The nulls of the strict variant leave, and the
/// answer goes to `structured_output`, like the Claude Code's.
Result validatedResult(
  Result r,
  Map<String, Object?> schema, {
  required String provider,
}) {
  if (!r.isSuccess) return r;
  Object? data = r.json['structured_output'];
  final text = r.result;
  if (data == null && text != null) {
    try {
      data = jsonDecode(text);
    } on FormatException {
      data = null;
    }
  }
  final why = data == null
      ? 'a resposta não é JSON'
      : schemaMismatch(stripAddedNulls(data, schema), schema);
  if (why != null) {
    debugPrint('planner: resposta fora do schema ($provider): ${_cut(text)}');
    throw PlannerException(
      'O planner não devolveu uma resposta no formato pedido ($provider: '
      '$why).',
    );
  }
  return ClaudeEvent.fromJson({
    ...r.json,
    'structured_output': stripAddedNulls(data, schema),
  }) as Result;
}

String _cut(String? text) {
  final t = CodexRpc.redact(text ?? '');
  return t.length > 2000 ? '${t.substring(0, 2000)}…' : t;
}
