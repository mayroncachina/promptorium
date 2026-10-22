import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../core/claude/run_prefs.dart';
import '../../../data/providers.dart';
import '../../../core/providers/agent_registry.dart' show codexEnabledProvider;
import '../../../core/providers/permission_policy.dart';
import '../../../core/providers/provider_preferences.dart';
import '../../../ui/theme/tokens.dart';
import '../../project/project_config.dart';
import '../../sessions/agent_names.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/widgets/composer.dart' show uiPermissionModes;
import '../../sessions/widgets/session_style.dart';
import '../board_screen.dart';
import '../spec_runner.dart';

/// Options of a spec run chosen in [RunSpecDialog].
typedef RunSpecOptions = ({
  String provider,
  String? agent,
  String model,
  String effort,
  ClaudePermissionMode mode,
});

/// "Executar" of a card: the first run (or [ask]) opens [RunSpecDialog];
/// later runs reuse the last session's mode / model / effort.
Future<void> runSpec(
  BuildContext context,
  WidgetRef ref,
  SpecCardData data, {
  bool ask = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The card (and its `ref`) may be gone when the user taps the snackbar
  // action: it moves to another column as soon as the session starts.
  final container = ProviderScope.containerOf(context, listen: false);
  RunSpecOptions? o;
  if (ask || data.sessions.isEmpty) {
    o = await showDialog<RunSpecOptions>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) =>
          RunSpecDialog(spec: data.spec, previous: data.sessions.lastOrNull),
    );
    if (o == null) return;
  }
  try {
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
      ..showSnackBar(
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
      ..showSnackBar(SnackBar(content: Text(e.message)));
  } on SessionException catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Agent, model, effort and permission mode of the step sessions of a spec.
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
  late String? _agent =
      widget.spec.agentName ??
      ProjectConfig.loadSync(ref.read(activeWorkspaceProvider)?.path ?? '')
          .agent;
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
    final single = steps <= ref.watch(runPrefsProvider).singleSessionMaxSteps;

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
          width: 480,
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
                  single
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
                if (widget.previous != null)
                  Text(
                    'Provedor: ${_provider == 'codex' ? 'Codex' : 'Claude Code'}',
                  ),
                if (widget.previous == null)
                  field<String>(
                    'Provedor',
                    'run-spec-provider',
                    _provider,
                    [
                      ('claude', 'Claude Code'),
                      if (ref.watch(codexEnabledProvider) ||
                          _provider == 'codex')
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
                          ...(_provider == 'codex'
                              ? const ['inherit']
                              : sessionModels),
                          _model,
                        })
                          (m, m == 'inherit' ? 'inherit (padrão)' : m),
                      ], (v) => _model = v),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: field<String>(
                        'Esforço',
                        'run-spec-effort',
                        _effort,
                        [
                          for (final e in {...effortChoices, _effort})
                            (e, effortLabel(e)),
                        ],
                        (v) => _effort = v,
                      ),
                    ),
                  ],
                ),
                field<ClaudePermissionMode>(
                  'Modo de permissão',
                  'run-spec-mode',
                  _mode,
                  [
                    for (final m in uiPermissionModes)
                      (m, permissionModeOption(m, provider: _provider)),
                  ],
                  (v) => _mode = v,
                ),
                if (_mode == ClaudePermissionMode.skipPermissions)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      bypassWarning(_provider),
                      style: TextStyle(fontSize: 11, color: AppColors.red),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      label: 'Cancelar',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AmberButton(
                      key: const ValueKey('run-spec-submit'),
                      label: 'Executar',
                      onTap: () => Navigator.of(context).pop((
                        provider: _provider,
                        agent: _agent ?? '',
                        model: _model,
                        effort: _effort,
                        mode: _mode,
                      )),
                    ),
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
