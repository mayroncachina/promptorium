import 'package:flutter/material.dart';

import '../../ui/providers/provider_logos.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/run_prefs.dart';
import '../../data/providers.dart';
import '../../core/codex/codex_cli.dart';
import '../../core/codex/codex_probe.dart' show codexSandboxFixCommand;
import '../../core/providers/agent_registry.dart';
import '../../core/providers/provider_availability.dart';
import '../../ui/widgets/only_provider_tag.dart';
import '../../core/providers/permission_policy.dart';
import '../../core/providers/provider_preferences.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import 'agent_names.dart';
import 'session_manager.dart';
import 'widgets/composer.dart' show uiPermissionModes;
import 'widgets/session_style.dart';

/// "Nova sessão" (title bar button / Ctrl+N; "Testar em sessão" of the
/// Agentes screen passes [agent]). Returns the new session id.
Future<String?> showNewSessionDialog(
  BuildContext context, {
  String? agent,
  String? title,
  String? prompt,
}) => showAppDialog<String>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => NewSessionDialog(
    initialAgent: agent,
    initialTitle: title,
    initialPrompt: prompt,
  ),
);

/// "Fork" of a session: asks the first message of the fork.
Future<String?> showForkDialog(BuildContext context, Session parent) =>
    showAppDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => NewSessionDialog(forkOf: parent),
    );

class NewSessionDialog extends ConsumerStatefulWidget {
  const NewSessionDialog({
    super.key,
    this.forkOf,
    this.initialAgent,
    this.initialTitle,
    this.initialPrompt,
  });

  /// When set, the dialog creates a fork of this session.
  final Session? forkOf;

  /// Agent preselected (`--agent`).
  final String? initialAgent;

  /// Prefilled fields ("Executar com agente").
  final String? initialTitle;
  final String? initialPrompt;

  @override
  ConsumerState<NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends ConsumerState<NewSessionDialog> {
  late final _title = TextEditingController(
    text: widget.forkOf == null
        ? (widget.initialTitle ?? '')
        : 'Fork de ${sessionTitle(widget.forkOf!)}',
  );
  late final _prompt = TextEditingController(text: widget.initialPrompt ?? '');
  late String? _agent = widget.initialAgent;
  late String _provider =
      widget.forkOf?.provider ?? ref.read(activeAgentProvider);

  /// Defaults of Configurações → Consumo (an agent may change them).
  late String _model = _defaultModel(_provider);
  late String _effort = _defaultEffort(_provider);

  String _defaultModel(String provider) => providerModelFrom(
    ref.read(runPrefsProvider),
    ref.read(appSettingsProvider),
    provider,
    RunKind.session,
  );

  String _defaultEffort(String provider) => providerEffortFrom(
    ref.read(runPrefsProvider),
    ref.read(appSettingsProvider),
    provider,
    RunKind.session,
  );

  /// Last mode chosen here (remembered), else `default`.
  late ClaudePermissionMode _mode = () {
    final saved = ClaudePermissionMode.fromCli(
      ref
          .read(appSettingsProvider.notifier)
          .get(permissionModePreferenceKey(_provider)),
    );
    return saved != null && uiPermissionModes.contains(saved)
        ? saved
        : ClaudePermissionMode.defaultMode;
  }();

  /// Whether the mode was taken from the initial agent already.
  bool _modeFromAgent = false;

  /// `--agent` does not apply the frontmatter `permissionMode` to the main
  /// thread (sondado na Fase 7): choosing an agent preselects its mode. An
  /// agent with `model` gets `inherit` (its own model wins over `--model`)
  /// and its `effort` is preselected; otherwise the defaults come back.
  void _pickAgent(String? name, List<AgentRef> agents) {
    _agent = name;
    final ref = agents.where((a) => a.name == name).firstOrNull;
    final prefs = this.ref.read(runPrefsProvider);
    _model = ref?.model != null ? 'inherit' : prefs.model(RunKind.session);
    _effort = ClaudeOptions.effortLevels.contains(ref?.effort)
        ? ref!.effort!
        : prefs.effort(RunKind.session);
    final mode = ClaudePermissionMode.fromCli(ref?.permissionMode);
    // Never preselected: skipping permissions is only the user's choice.
    if (mode != null &&
        mode != ClaudePermissionMode.skipPermissions &&
        uiPermissionModes.contains(mode)) {
      _mode = mode;
    }
  }

  void _setProvider(String v) {
    _provider = v;
    _model = _defaultModel(v);
    _effort = _defaultEffort(v);
    _agent = null;
    _mode = ClaudePermissionMode.defaultMode;
  }

  bool _worktree = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ws = ref.read(activeWorkspaceProvider);
    final fork = widget.forkOf;
    if (fork == null && ws == null) {
      setState(() => _error = 'Selecione um workspace na barra de título.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final manager = ref.read(sessionManagerProvider.notifier);
    try {
      final id = fork != null
          ? await manager.fork(
              fork.id,
              prompt: _prompt.text,
              title: _title.text,
            )
          : await manager.create(
              NewSessionRequest(
                workspace: ws!,
                provider: _provider,
                title: _title.text,
                prompt: _prompt.text,
                agent: _agent,
                model: _model,
                effort: _effort,
                permissionMode: _mode,
                useWorktree: _worktree,
              ),
            );
      if (fork == null) {
        await ref
            .read(appSettingsProvider.notifier)
            .set(permissionModePreferenceKey(_provider), _mode.cliValue);
      }
      ref.read(selectedSessionProvider.notifier).select(id);
      if (mounted) Navigator.of(context).pop(id);
    } on SessionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fork = widget.forkOf;
    final ws = ref.watch(activeWorkspaceProvider);
    final agents = fork == null
        ? ref.watch(agentListProvider(ws?.path)).value ?? const <AgentRef>[]
        : const <AgentRef>[];
    if (!_modeFromAgent && _agent != null && agents.isNotEmpty) {
      _modeFromAgent = true;
      _pickAgent(_agent, agents);
    }
    final caps = capabilitiesFor(_provider);
    final providerName = _provider == 'codex' ? 'Codex' : 'Claude Code';
    // R12: a provider not released for sessions never starts here, and the
    // screen says why before the click.
    final flowLocked =
        fork == null &&
        !ref.watch(providerFlowsProvider).allows(_provider, AppFlow.sessions);
    // R7a: without the OS sandbox, Codex only runs in a worktree with full
    // access (YOLO).
    final availability = caps.providerId == 'codex'
        ? ref.watch(providerAvailabilityProvider(_provider)).value
        : null;
    final noSandbox = availability?.sandboxWarning != null;
    final codexCache = caps.providerId == 'codex'
        ? codexModelsCache(ref.watch(appSettingsProvider))
        : null;
    // A preselected agent that is not in the list (yet) stays selectable.
    final agentItems = [
      for (final a in agents)
        (a.name, a.project ? '${a.name} · projeto' : a.name),
      if (_agent != null && !agents.any((a) => a.name == _agent))
        (_agent!, _agent!),
    ];

    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      isDense: true,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    );

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        t,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );

    Widget dropdown<T>({
      required Key key,
      required T value,
      required List<(T, String)> items,
      required ValueChanged<T> onChanged,
      Widget? Function(T)? leading,
    }) => DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      isDense: true,
      isExpanded: true,
      dropdownColor: AppColors.panelSolid,
      decoration: deco(''),
      style: const TextStyle(fontSize: 13, color: AppColors.text),
      items: [
        for (final (v, l) in items)
          DropdownMenuItem(
            value: v,
            child: Row(
              children: [
                if (leading?.call(v) case final w?) ...[
                  w,
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(l, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      onChanged: (v) => onChanged(v as T),
    );

    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        key: const ValueKey('new-session-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fork == null ? 'Nova sessão' : 'Fork da sessão',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fork == null
                      ? 'Workspace: ${ws?.name ?? '—'}'
                      : 'Continua a conversa (--resume --fork-session) num '
                            'novo worktree a partir da branch ${fork.branch}. '
                            'Alterações não commitadas não são copiadas.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                label('Título'),
                TextField(
                  key: const ValueKey('new-session-title'),
                  controller: _title,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: deco('Ex.: Shell da IDE'),
                ),
                label(
                  fork == null ? 'Prompt inicial' : 'Primeira mensagem do fork',
                ),
                TextField(
                  key: const ValueKey('new-session-prompt'),
                  controller: _prompt,
                  minLines: 4,
                  maxLines: 10,
                  style: const TextStyle(fontSize: 13),
                  decoration: deco(
                    'O que o ${_provider == 'codex' ? 'Codex' : 'Claude'} deve fazer?',
                  ),
                ),
                if (fork == null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (caps.supports(
                              ProviderCapability.agentFiles,
                            )) ...[
                              label('Agente (--agent)'),
                              dropdown<String?>(
                                key: const ValueKey('new-session-agent'),
                                value: _agent,
                                items: [
                                  (null, 'nenhum'),
                                  for (final (n, l) in agentItems) (n, l),
                                ],
                                onChanged: (v) =>
                                    setState(() => _pickAgent(v, agents)),
                              ),
                            ] else ...[
                              // R11: disabled with the reason, not hidden.
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 6,
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Agente',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: OnlyProviderTag(
                                        key: const ValueKey(
                                          'new-session-agent-only',
                                        ),
                                        provider: 'Claude Code',
                                        reason: caps.reasonFor(
                                          ProviderCapability.agentFiles,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _DisabledField(
                                caps.reasonFor(ProviderCapability.agentFiles),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            label('Provedor'),
                            dropdown<String>(
                              key: const ValueKey('new-session-provider'),
                              value: _provider,
                              // R11: a provider not released here shows up
                              // with the tag, it does not disappear.
                              items: [
                                ('claude', 'Claude Code'),
                                (
                                  'codex',
                                  ref
                                          .watch(providerFlowsProvider)
                                          .allows('codex', AppFlow.sessions)
                                      ? 'Codex'
                                      : flowLockedLabel('Codex'),
                                ),
                              ],
                              onChanged: (v) => setState(() => _setProvider(v)),
                              // R15: official logo next to the name.
                              leading: (v) => hasProviderIdentity(v)
                                  ? ProviderLogo(v)
                                  : null,
                            ),
                            label('Modelo'),
                            // Rebuilt when an agent changes the value.
                            KeyedSubtree(
                              key: ValueKey('new-session-model-$_model'),
                              child: dropdown<String>(
                                key: const ValueKey('new-session-model'),
                                value: _model,
                                items: [
                                  for (final m in {
                                    ...(codexCache != null
                                        ? [
                                            'inherit',
                                            for (final m in codexCache.models)
                                              m.id,
                                          ]
                                        : caps.providerId == 'codex'
                                        ? const ['inherit']
                                        : sessionModels),
                                    _model,
                                  })
                                    (
                                      m,
                                      m == 'inherit'
                                          ? (_agent == null
                                                ? 'inherit (padrão do CLI)'
                                                : 'inherit (do agente)')
                                          : m,
                                    ),
                                ],
                                onChanged: (v) => setState(() => _model = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            label('Esforço'),
                            KeyedSubtree(
                              key: ValueKey('new-session-effort-$_effort'),
                              child: dropdown<String>(
                                key: const ValueKey('new-session-effort'),
                                value: _effort,
                                items: [
                                  for (final e in {
                                    ...(codexCache == null
                                        ? effortChoices
                                        : [
                                            'default',
                                            ...?codexCache
                                                .byId(_model)
                                                ?.efforts,
                                          ]),
                                    _effort,
                                  })
                                    (e, effortLabel(e)),
                                ],
                                onChanged: (v) => setState(() => _effort = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Padrões em Configurações → Consumo. Sessões longas '
                      'custam mais: cada resposta relê a conversa inteira.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  label('Modo de permissão'),
                  // Rebuilt when an agent preselects the mode (initialValue).
                  KeyedSubtree(
                    key: ValueKey('new-session-mode-${_mode.cliValue}'),
                    child: dropdown<ClaudePermissionMode>(
                      key: const ValueKey('new-session-mode'),
                      value: _mode,
                      items: [
                        for (final m in uiPermissionModes)
                          if ((_worktree ||
                                  m != ClaudePermissionMode.skipPermissions) &&
                              (!noSandbox ||
                                  m == ClaudePermissionMode.skipPermissions))
                            (m, permissionModeOption(m, provider: _provider)),
                        // Keeps the dropdown valid while nothing applies.
                        if (noSandbox &&
                            _mode != ClaudePermissionMode.skipPermissions)
                          (
                            _mode,
                            permissionModeOption(_mode, provider: _provider),
                          ),
                      ],
                      onChanged: (v) => setState(() => _mode = v),
                    ),
                  ),
                  if (_mode == ClaudePermissionMode.skipPermissions)
                    Padding(
                      key: ValueKey('new-session-skip-warning'),
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        bypassWarning(_provider),
                        style: TextStyle(fontSize: 11, color: AppColors.red),
                      ),
                    ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const ValueKey('new-session-worktree'),
                    value: _worktree,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() {
                      _worktree = v ?? true;
                      // "Sem perguntar" only in a worktree (F12).
                      if (!_worktree &&
                          _mode == ClaudePermissionMode.skipPermissions) {
                        _mode = ClaudePermissionMode.defaultMode;
                      }
                    }),
                    title: const Text(
                      'Criar worktree isolado (branch pr/<slug>)',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Desmarcado: roda na raiz do workspace.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  // SPEC-096 R10: what the sandbox opens in a worktree.
                  if (_provider == 'codex' &&
                      _worktree &&
                      !noSandbox &&
                      _mode != ClaudePermissionMode.skipPermissions)
                    Container(
                      key: const ValueKey('new-session-writable-roots'),
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Raízes graváveis do sandbox\n',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            const TextSpan(text: 'o worktree da sessão\n'),
                            TextSpan(
                              text:
                                  '${ws == null ? '' : '${ws.path.split('/').last}/'}'
                                  '.git: worktrees/<wt>, objects, refs, logs',
                              style: const TextStyle(fontFamily: AppFonts.mono),
                            ),
                            const TextSpan(
                              text:
                                  ' (git common dir: permite git commit; '
                                  'hooks e config ficam fora). O que sobrar '
                                  'sem commit, o app commita no fim do turno.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
                if (noSandbox && fork == null)
                  _Notice(
                    key: const ValueKey('new-session-no-sandbox'),
                    text:
                        'Sandbox do Codex indisponível nesta máquina: '
                        'Perguntar, Planejar e Editar não rodam. O Codex só '
                        'roda em worktree com acesso total (YOLO), e o app '
                        'commita no fim do turno. Para liberar: '
                        '$codexSandboxFixCommand',
                    action: 'Verificar de novo',
                    onAction: () {
                      ref.invalidate(codexCliInfoProvider);
                      ref.invalidate(providerAvailabilityProvider(_provider));
                    },
                  ),
                if (flowLocked)
                  _Notice(
                    key: const ValueKey('new-session-flow-locked'),
                    text: flowLockedMessage(providerName, AppFlow.sessions),
                    action: 'Usar Claude Code',
                    onAction: () => setState(() => _setProvider('claude')),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const ValueKey('new-session-error'),
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      label: 'Cancelar',
                      onTap: _busy ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AmberButton(
                      key: const ValueKey('new-session-submit'),
                      label: _busy
                          ? 'Iniciando…'
                          : (fork == null ? 'Iniciar sessão' : 'Criar fork'),
                      onTap:
                          _busy ||
                              flowLocked ||
                              (noSandbox &&
                                  _mode != ClaudePermissionMode.skipPermissions)
                          ? null
                          : _submit,
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

/// A field that does not apply to the selected provider (R11).
class _DisabledField extends StatelessWidget {
  const _DisabledField(this.reason);

  final String reason;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      reason,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    ),
  );
}

/// Amber notice with one action (R7a, R12).
class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 8),
          SmallButton(label: action, onTap: onAction),
        ],
      ),
    ),
  );
}
