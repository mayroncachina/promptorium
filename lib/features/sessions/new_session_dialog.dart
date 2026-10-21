import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/run_prefs.dart';
import '../../data/providers.dart';
import '../../core/providers/permission_policy.dart';
import '../../core/providers/provider_preferences.dart';
import '../../ui/theme/tokens.dart';
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
}) => showDialog<String>(
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
    showDialog<String>(
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
  late String _model = _provider == 'claude'
      ? ref.read(runPrefsProvider).model(RunKind.session)
      : 'inherit';
  late String _effort = _provider == 'claude'
      ? ref.read(runPrefsProvider).effort(RunKind.session)
      : 'default';

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
    }) => DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      isDense: true,
      isExpanded: true,
      dropdownColor: AppColors.panel,
      decoration: deco(''),
      style: const TextStyle(fontSize: 13, color: AppColors.text),
      items: [
        for (final (v, l) in items)
          DropdownMenuItem(
            value: v,
            child: Text(l, overflow: TextOverflow.ellipsis),
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
                  decoration: deco('O que o Claude deve fazer?'),
                ),
                if (fork == null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                              items: const [
                                ('claude', 'Claude Code'),
                                ('codex', 'Codex'),
                              ],
                              onChanged: (v) => setState(() {
                                _provider = v;
                                _model = 'inherit';
                                _effort = 'default';
                                _agent = null;
                                _mode = ClaudePermissionMode.defaultMode;
                              }),
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
                                    ...(_provider == 'codex'
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
                                  for (final e in {...effortChoices, _effort})
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
                          if (_worktree ||
                              m != ClaudePermissionMode.skipPermissions)
                            (m, permissionModeOption(m, provider: _provider)),
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
                ],
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
                      onTap: _busy ? null : _submit,
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
