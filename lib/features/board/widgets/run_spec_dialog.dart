import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../core/claude/run_prefs.dart';
import '../../../data/providers.dart';
import '../../../data/repos/spec_steps_repo.dart';
import '../../../core/providers/agent_registry.dart' show codexEnabledProvider;
import '../../../core/providers/permission_policy.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../core/providers/provider_preferences.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../project/spec_auto_planner.dart';
import '../../project/project_config.dart';
import '../../review/auto_reviewer.dart' show reviewerApplies;
import '../../settings/settings_sections.dart';
import '../../sessions/agent_names.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/widgets/composer.dart' show uiPermissionModes;
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart';
import '../../../ui/shell/navigation.dart';
import '../board_rules.dart';
import '../board_screen.dart';
import '../orchestrator/orchestrator_rules.dart';
import '../orchestrator/step_classifier.dart';
import '../orchestrator/step_plan.dart';
import '../orchestrator/step_plan_list.dart';
import '../spec_runner.dart';

/// Options of a spec run chosen in [RunSpecDialog].
///
/// In Automático (SPEC-035) [auto] is true, [provider] is `claude`, [plan]
/// has one entry per open step, in queue order, and [model] / [effort] are
/// those of the first one; [review] is the model of the automatic reviewer
/// (null when it is off in the project). In Manual, and in "Executar com"
/// the model of Sessões after a failed classification (R14), [auto] is
/// false and [plan] is empty.
typedef RunSpecOptions = ({
  String provider,
  String? agent,
  String model,
  String effort,
  ClaudePermissionMode mode,
  bool auto,
  List<StepPlanEntry> plan,
  StepRule? review,
});

/// Copies the plan of [o] to `spec_steps` (SPEC-035): in Automático each
/// step gets its kind, model, effort, hash and "você escolheu", and starts
/// from the bottom of the ladder; otherwise the plan left by an earlier run
/// in Automático is removed, so the steps run with the model of the form.
Future<void> storeRunPlan(
  SpecStepsRepo repo,
  int specId,
  RunSpecOptions o,
) async {
  if (o.auto) {
    await storePlanEntries(repo, specId, o.plan);
    return;
  }
  await clearStoredPlan(repo, specId);
}

/// Whether running a spec should warn that it has no Plano (SPEC-017 R3):
/// without it every step gets the whole spec and explores the code again,
/// which only pays off for a spec small enough for one session.
bool needsDesignWarning(String? specText, {required int maxSingleSession}) {
  if (specText == null) return false;
  final doc = SpecDocument.parse(specText);
  return doc.design == null && doc.requirements.length > maxSingleSession;
}

/// "Executar" of a card: the first run (or [ask]) opens [RunSpecDialog];
/// later runs reuse the last session's mode / model / effort. A first run of
/// a spec without Plano and with many steps warns first (SPEC-017 R3).
Future<void> runSpec(
  BuildContext context,
  WidgetRef ref,
  SpecCardData data, {
  bool ask = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  // SPEC-037 R10, R13: every way in, not only the card's button.
  if (ref.read(specAutoPlannerProvider).lockOf(data.spec.id) case final lock?) {
    messenger
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text('${lock.reason}.')));
    return;
  }
  // The card (and its `ref`) may be gone when the user taps the snackbar
  // action: it moves to another column as soon as the session starts.
  final container = ProviderScope.containerOf(context, listen: false);
  final max = ref.read(runPrefsProvider).singleSessionMaxSteps;
  // Only a spec with more steps than one session takes can need the
  // warning (the stored requirements say it without reading the file).
  if (data.sessions.isEmpty && data.spec.requirements.length > max) {
    final ws = await ref
        .read(workspacesRepoProvider)
        .getById(data.spec.workspaceId);
    String? text;
    try {
      text = ws == null
          ? null
          : await ref.read(specServiceProvider).read(ws, data.spec);
    } catch (_) {}
    if (!context.mounted) return;
    if (needsDesignWarning(text, maxSingleSession: max)) {
      final choice = await showAppDialog<String>(
        context: context,
        barrierColor: AppColors.scrim,
        builder: (_) => _NoDesignDialog(
          spec: data.spec,
          steps: SpecDocument.parse(text!).requirements.length,
        ),
      );
      if (choice == null || !context.mounted) return;
      if (choice == 'design') {
        container.read(selectedSpecProvider.notifier).select(data.spec.id);
        container.read(pendingDesignProvider.notifier).select(data.spec.id);
        container.read(navigationProvider.notifier).go(AppSection.specs);
        return;
      }
    }
  }
  RunSpecOptions? o;
  if (ask || data.sessions.isEmpty) {
    o = await showAppDialog<RunSpecOptions>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) =>
          RunSpecDialog(spec: data.spec, previous: data.sessions.lastOrNull),
    );
    if (o == null) return;
  }
  try {
    if (o != null) {
      await storeRunPlan(ref.read(specStepsRepoProvider), data.spec.id, o);
      // The line "Revisão" of the plan, for the automatic reviewer (R4, R8).
      await storeReviewRule(
        ref.read(appSettingsProvider.notifier),
        data.spec.id,
        o.auto ? o.review : null,
      );
    }
    final id = await ref
        .read(specRunnerProvider)
        .runNext(
          data.spec.id,
          agent: o?.agent ?? data.spec.agentName ?? '',
          model: o?.model,
          effort: o?.effort,
          mode: o?.mode,
          provider: o?.provider,
        );
    if (o != null) {
      await ref
          .read(appSettingsProvider.notifier)
          .set(permissionModePreferenceKey(o.provider), o.mode.cliValue);
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showAppToast(
        SnackBar(
          content: Text('Sessão aberta para ${data.spec.code}.'),
          // A snackbar with an action does not go away by itself otherwise.
          persist: false,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Ver sessão',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              openSessionIn(container, id);
            },
          ),
        ),
      );
  } on SpecRunException catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(e.message)));
  } on SessionException catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(e.message)));
  }
}

/// Agent, model, effort and permission mode of the step sessions of a spec.
/// In Automático (SPEC-035 R1), the plan of the Orquestrador takes the place
/// of provider, model and effort.
class RunSpecDialog extends ConsumerStatefulWidget {
  const RunSpecDialog({super.key, required this.spec, this.previous});

  final Spec spec;
  final Session? previous;

  @override
  ConsumerState<RunSpecDialog> createState() => _RunSpecDialogState();
}

class _RunSpecDialogState extends ConsumerState<RunSpecDialog> {
  late String _provider =
      widget.previous?.provider ?? ref.read(activeAgentProvider);
  late final String _projectPath =
      ref.read(activeWorkspaceProvider)?.path ?? '';
  late String? _agent =
      widget.spec.agentName ?? ProjectConfig.loadSync(_projectPath).agent;
  late String _model =
      widget.previous?.model ??
      (_provider == 'claude'
          ? ref.read(runPrefsProvider).model(RunKind.session)
          : 'inherit');
  late String _effort =
      widget.previous?.effort ??
      (_provider == 'claude'
          ? ref.read(runPrefsProvider).effort(RunKind.session)
          : 'default');
  late ClaudePermissionMode _mode = () {
    final saved = ClaudePermissionMode.fromCli(
      widget.previous?.permissionMode ??
          ref
              .read(appSettingsProvider.notifier)
              .get(permissionModePreferenceKey(_provider)),
    );
    return saved != null && uiPermissionModes.contains(saved)
        ? saved
        : ClaudePermissionMode.defaultMode;
  }();
  bool _fromAgent = false;

  /// Automático / Manual (R1): Manual unless "Abrir Executar em Automático".
  late bool _auto = ref.read(orchestratorPrefsProvider).autoByDefault;

  /// The automatic reviewer is on in the project: last line of the plan.
  late final bool _reviewOn = reviewerApplies(
    ProjectConfig.loadSync(_projectPath),
  );

  /// What the person chose in the lines of the plan, by step id
  /// ([StepPlanList.reviewStep] for the reviewer). A new classification
  /// never touches them (R4).
  final _picks = <String, StepRule>{};

  late final StepClassifier _classifier = ref.read(
    stepClassifierProvider.notifier,
  );

  /// [StepClassifier.classify] was called and needs its [StepClassifier.cancel].
  bool _classifying = false;

  /// The picks stored by the last plan were read.
  bool _picksLoaded = false;

  /// "Executar" was tapped while classifying: the dialog confirms with the
  /// plan as soon as the classification ends (or shows the failure, R14).
  bool _waiting = false;

  /// The dialog is closing with the plan ([_waiting] ended).
  bool _confirmed = false;

  @override
  void dispose() {
    if (_classifying) _classifier.cancel(widget.spec.id);
    super.dispose();
  }

  /// Same rule as Nova sessão: an agent with `model` runs with it; its
  /// `effort` and `permissionMode` are preselected.
  void _pick(String? name, List<AgentRef> agents) {
    _agent = name;
    final a = agents.where((x) => x.name == name).firstOrNull;
    final prefs = ref.read(runPrefsProvider);
    _model = a?.model != null ? 'inherit' : prefs.model(RunKind.session);
    _effort = ClaudeOptions.effortLevels.contains(a?.effort)
        ? a!.effort!
        : prefs.effort(RunKind.session);
    final mode = ClaudePermissionMode.fromCli(a?.permissionMode);
    if (mode != null &&
        mode != ClaudePermissionMode.skipPermissions &&
        uiPermissionModes.contains(mode)) {
      _mode = mode;
    }
  }

  void _setAuto(bool on) => setState(() {
    _auto = on;
    if (!on) _waiting = false;
    if (!on && _classifying) {
      _classifying = false;
      _classifier.cancel(widget.spec.id);
    }
  });

  /// Status of the Claude Code for Automático (R15), asked when the dialog
  /// opens (watching the provider starts the check when it is not known
  /// yet): [checking] while it runs; [blocked] is why Automático is off.
  /// Manual never waits for it.
  ({bool checking, String? blocked}) _claudeStatus() {
    final a = ref.watch(providerAvailabilityProvider('claude'));
    final value = a.value;
    if (value != null) {
      return (
        checking: false,
        blocked: value.available
            ? null
            : 'Claude Code ${value.label}. ${value.message}',
      );
    }
    if (a.hasError) {
      return (
        checking: false,
        blocked: 'Não foi possível verificar o Claude Code.',
      );
    }
    return (checking: true, blocked: null);
  }

  void _openSettings(SettingsSection section) {
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(context).pop();
    container.read(selectedSettingsSectionProvider.notifier).select(section);
    container.read(navigationProvider.notifier).go(AppSection.settings);
  }

  /// Picks of the last confirmed plan (`user_picked`), read once.
  void _loadPicks(Iterable<SpecStep> rows) {
    if (_picksLoaded) return;
    _picksLoaded = true;
    for (final r in rows) {
      if (r.specId == widget.spec.id && r.userPicked && r.planModel != null) {
        _picks.putIfAbsent(
          r.step,
          () => StepRule(r.planModel!, r.planEffort ?? 'medium'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    final agents =
        ref.watch(agentListProvider(ws?.path)).value ?? const <AgentRef>[];
    if (!_fromAgent && _agent != null && agents.isNotEmpty) {
      _fromAgent = true;
      _pick(_agent, agents);
    }
    final steps = widget.spec.requirements.length;
    final runPrefs = ref.watch(runPrefsProvider);
    final single = steps <= runPrefs.singleSessionMaxSteps;
    final (:checking, :blocked) = _claudeStatus();
    // With Automático chosen, the dialog stays in it while the CLI is
    // checked (no Manual in between) and only falls back to Manual when the
    // Claude Code is not available (R15).
    final auto = _auto && blocked == null;

    Widget field<T>(
      String label,
      String key,
      T value,
      List<(T, String)> items,
      ValueChanged<T> onChanged,
    ) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          KeyedSubtree(
            key: ValueKey('$key-$value'),
            child: DropdownButtonFormField<T>(
              key: ValueKey(key),
              initialValue: value,
              isDense: true,
              isExpanded: true,
              dropdownColor: AppColors.panel,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              items: [
                for (final (v, l) in items)
                  DropdownMenuItem(
                    value: v,
                    child: Text(l, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => onChanged(v as T)),
            ),
          ),
        ],
      ),
    );

    Widget modeField(String provider) => field<ClaudePermissionMode>(
      'Modo de permissão',
      'run-spec-mode',
      _mode,
      [
        for (final m in uiPermissionModes)
          (m, permissionModeOption(m, provider: provider)),
      ],
      (v) => _mode = v,
    );

    Widget bypass(String provider) =>
        _mode == ClaudePermissionMode.skipPermissions
        ? Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              bypassWarning(provider),
              style: TextStyle(fontSize: 11, color: AppColors.red),
            ),
          )
        : const SizedBox.shrink();

    final manualFields = <Widget>[
      if (widget.previous != null)
        Text('Provedor: ${_provider == 'codex' ? 'Codex' : 'Claude Code'}'),
      if (widget.previous == null)
        field<String>(
          'Provedor',
          'run-spec-provider',
          _provider,
          [
            ('claude', 'Claude Code'),
            if (ref.watch(codexEnabledProvider) || _provider == 'codex')
              ('codex', 'Codex'),
          ],
          (v) {
            _provider = v;
            _model = 'inherit';
            _effort = 'default';
            _agent = null;
            _mode = ClaudePermissionMode.defaultMode;
          },
        ),
      field<String?>('Agente (--agent)', 'run-spec-agent', _agent, [
        (null, 'nenhum'),
        for (final a in agents)
          (a.name, a.project ? '${a.name} · projeto' : a.name),
        if (_agent != null && !agents.any((a) => a.name == _agent))
          (_agent, _agent!),
      ], (v) => _pick(v, agents)),
      Row(
        children: [
          Expanded(
            child: field<String>('Modelo', 'run-spec-model', _model, [
              for (final m in {
                ...(_provider == 'codex' ? const ['inherit'] : sessionModels),
                _model,
              })
                (m, m == 'inherit' ? 'inherit (padrão)' : m),
            ], (v) => _model = v),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: field<String>('Esforço', 'run-spec-effort', _effort, [
              for (final e in {...effortChoices, _effort}) (e, effortLabel(e)),
            ], (v) => _effort = v),
          ),
        ],
      ),
      modeField(_provider),
      bypass(_provider),
    ];

    void submitManual() => Navigator.of(context).pop((
      provider: _provider,
      agent: _agent ?? '',
      model: _model,
      effort: _effort,
      mode: _mode,
      auto: false,
      plan: const <StepPlanEntry>[],
      review: null,
    ));

    // --- Automático ----------------------------------------------------------
    final orchestrator = ref.watch(orchestratorPrefsProvider);
    final sessionModel = runPrefs.model(RunKind.session);
    final sessionEffort = runPrefs.effort(RunKind.session);
    final sessionLabel = sessionModel == 'inherit' || sessionModel.isEmpty
        ? 'o modelo padrão'
        : orchestratorModelLabel(sessionModel);
    var children = manualFields;
    var actions = <Widget>[
      AmberButton(
        key: const ValueKey('run-spec-submit'),
        label: 'Executar',
        onTap: submitManual,
      ),
    ];
    if (auto && checking) {
      children = [
        const SizedBox(height: 12),
        const Text(
          'Verificando o Claude Code…',
          key: ValueKey('run-spec-auto-checking'),
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        StepPlanSkeleton(rows: steps + (_reviewOn ? 1 : 0)),
        modeField('claude'),
        bypass('claude'),
      ];
      actions = [
        SmallButton(
          key: const ValueKey('run-spec-use-manual'),
          label: 'Usar Manual',
          onTap: () => _setAuto(false),
        ),
        const SizedBox(width: 8),
        const AmberButton(
          key: ValueKey('run-spec-submit'),
          label: 'Executar',
          onTap: null,
        ),
      ];
    } else if (auto) {
      final rowsValue = ref.watch(specStepsProvider(widget.spec.workspaceId));
      final rows = rowsValue.value;
      final views = rows == null ? null : stepsOf(widget.spec, rows);
      if (views != null && !_classifying) {
        _classifying = true;
        _loadPicks(rows!);
        unawaited(_classifier.classify(widget.spec, views, rows: rows));
      }
      final cls = ref.watch(stepClassificationProvider(widget.spec.id));
      final status = views == null ? StepClassifierStatus.loading : cls.status;
      final plan = views == null
          ? const <StepPlanEntry>[]
          : buildStepPlan(
              spec: widget.spec,
              steps: views,
              kinds: cls.result?.kinds ?? const {},
              prefs: orchestrator,
              picks: _picks,
            );
      final review = _reviewOn
          ? StepPlanEntry(
              step: StepPlanList.reviewStep,
              title: 'Revisão automática do diff',
              kind: StepKind.revisao,
              reason: 'revisa o diff no fim, não é etapa da fila',
              suggested: orchestrator.rule(StepKind.revisao),
              pick: _picks[StepPlanList.reviewStep],
            )
          : null;
      RunSpecOptions confirm() => (
        provider: 'claude',
        agent: _agent ?? '',
        // The first session starts with the first step's plan.
        model: plan.firstOrNull?.rule.model ?? sessionModel,
        effort: plan.firstOrNull?.rule.effort ?? sessionEffort,
        mode: _mode,
        auto: true,
        plan: plan,
        review: review?.rule,
      );
      // "Executar" tapped while classifying: confirm once the plan is in;
      // a failure leaves the choice to the person (R14).
      if (_waiting && status == StepClassifierStatus.failed) _waiting = false;
      if (_waiting && status == StepClassifierStatus.ready && !_confirmed) {
        _confirmed = true;
        final options = confirm();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(options);
        });
      }
      final rowsCount =
          (views?.where((s) => !s.isDone).length ?? steps) +
          (_reviewOn ? 1 : 0);
      final classifierLabel = orchestratorModelLabel(
        orchestrator.classifierModel,
      );
      children = [
        const SizedBox(height: 12),
        switch (status) {
          StepClassifierStatus.loading => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Classificando as etapas com $classifierLabel…',
                key: const ValueKey('run-spec-classifying'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              StepPlanSkeleton(rows: rowsCount < 1 ? 1 : rowsCount),
            ],
          ),
          StepClassifierStatus.failed => Container(
            key: const ValueKey('run-spec-classify-failed'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: SessionColors.stopBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Não deu para classificar as etapas: '
                  '${cls.result!.error}.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sem classificação, todas as etapas usam o modelo de '
                  'Sessões em Configurações: $sessionLabel · '
                  '${effortLabel(sessionEffort)}.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          StepClassifierStatus.ready => StepPlanList(
            entries: plan,
            review: review,
            onPick: (step, rule) => setState(() => _picks[step] = rule),
          ),
        },
        modeField('claude'),
        bypass('claude'),
        if (status == StepClassifierStatus.ready && plan.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              planSessionsLabel(planSessions(plan.map((e) => e.rule))),
              key: const ValueKey('run-spec-sessions'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ];
      actions = switch (status) {
        StepClassifierStatus.loading => [
          SmallButton(
            key: const ValueKey('run-spec-use-manual'),
            label: 'Usar Manual',
            onTap: () => _setAuto(false),
          ),
          const SizedBox(width: 8),
          // Enabled while classifying (mockup): waits for the plan.
          AmberButton(
            key: const ValueKey('run-spec-submit'),
            label: 'Executar',
            busy: _waiting,
            onTap: () => setState(() => _waiting = true),
          ),
        ],
        StepClassifierStatus.failed => [
          SmallButton(
            key: const ValueKey('run-spec-retry'),
            label: 'Tentar de novo',
            onTap: () {
              final rows = rowsValue.value ?? const <SpecStep>[];
              unawaited(
                _classifier.retry(
                  widget.spec,
                  stepsOf(widget.spec, rows),
                  rows: rows,
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          AmberButton(
            key: const ValueKey('run-spec-fallback'),
            label: 'Executar com $sessionLabel',
            // R14: every step with the model of Sessões, no plan.
            onTap: () => Navigator.of(context).pop((
              provider: 'claude',
              agent: _agent ?? '',
              model: sessionModel,
              effort: sessionEffort,
              mode: _mode,
              auto: false,
              plan: const <StepPlanEntry>[],
              review: null,
            )),
          ),
        ],
        StepClassifierStatus.ready => [
          AmberButton(
            key: const ValueKey('run-spec-submit'),
            label: 'Executar',
            busy: _confirmed,
            onTap: () => Navigator.of(context).pop(confirm()),
          ),
        ],
      };
    }

    return Align(
      alignment: const Alignment(0, -0.4),
      child: Material(
        key: const ValueKey('run-spec-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: auto ? 640 : 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Executar ${widget.spec.code}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  auto
                      ? '$steps etapas no worktree da spec: cada etapa roda '
                            'com o modelo do plano, no Claude Code.'
                      : single
                      ? '$steps etapas: roda inteira numa sessão, no worktree '
                            'da spec.'
                      : '$steps etapas: uma sessão por etapa, em sequência, '
                            'no worktree da spec. Cada sessão começa com '
                            'contexto limpo.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _RunModeSwitch(
                      auto: auto,
                      autoEnabled: !checking && blocked == null,
                      onChanged: _setAuto,
                    ),
                    if (checking && !auto) ...[
                      const SizedBox(width: 10),
                      const Flexible(
                        flex: 4,
                        child: Text(
                          'Verificando o Claude Code…',
                          key: ValueKey('run-spec-auto-checking'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (auto)
                      SmallButton(
                        key: const ValueKey('run-spec-rules'),
                        label: 'Regras em Configurações',
                        onTap: () =>
                            _openSettings(SettingsSection.orchestrator),
                      ),
                  ],
                ),
                if (blocked != null)
                  Container(
                    key: const ValueKey('run-spec-auto-blocked'),
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Automático indisponível: $blocked',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SmallButton(
                          key: const ValueKey('run-spec-open-providers'),
                          label: 'Abrir Provedores',
                          onTap: () => _openSettings(SettingsSection.providers),
                        ),
                      ],
                    ),
                  ),
                ...children,
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      label: 'Cancelar',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    ...actions,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Automático / Manual of [RunSpecDialog] (R1, R15).
class _RunModeSwitch extends StatelessWidget {
  const _RunModeSwitch({
    required this.auto,
    required this.autoEnabled,
    required this.onChanged,
  });

  final bool auto;
  final bool autoEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, String key, bool on, VoidCallback? onTap) =>
        Semantics(
          button: true,
          selected: on,
          enabled: onTap != null,
          child: Material(
            color: on ? SessionColors.selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              key: ValueKey(key),
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: on
                        ? AppColors.text
                        : onTap == null
                        ? AppColors.textDisabled
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(
            'Automático',
            'run-spec-auto',
            auto,
            autoEnabled ? () => onChanged(true) : null,
          ),
          const SizedBox(width: 2),
          segment('Manual', 'run-spec-manual', !auto, () => onChanged(false)),
        ],
      ),
    );
  }
}

/// "SPEC-NNN não tem Plano" (SPEC-017 R3): returns `design`, `run` or null.
class _NoDesignDialog extends StatelessWidget {
  const _NoDesignDialog({required this.spec, required this.steps});

  final Spec spec;
  final int steps;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('run-no-design-dialog'),
    backgroundColor: AppColors.panel,
    title: Text(
      '${spec.code} não tem Plano',
      style: const TextStyle(fontSize: 16),
    ),
    content: SizedBox(
      width: 460,
      child: Text(
        'Sem Plano, cada etapa recebe a spec inteira e explora o código do '
        'zero. Com $steps etapas, isso se repete $steps vezes.\n\n'
        '"Planejar" lê o repositório uma vez e escreve o que já existe e '
        'os arquivos de cada etapa; as sessões passam a receber só o trecho '
        'delas.',
        style: const TextStyle(fontSize: 13),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      TextButton(
        key: const ValueKey('run-no-design-run'),
        onPressed: () => Navigator.of(context).pop('run'),
        child: const Text('Executar mesmo assim'),
      ),
      TextButton(
        key: const ValueKey('run-no-design-generate'),
        onPressed: () => Navigator.of(context).pop('design'),
        child: const Text('Planejar'),
      ),
    ],
  );
}
