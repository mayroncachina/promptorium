import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import 'agent_names.dart';
import 'session_manager.dart';
import 'widgets/composer.dart' show permissionLabel, uiPermissionModes;
import 'widgets/session_style.dart';

/// "Nova sessão" (title bar button / Ctrl+N). Returns the new session id.
Future<String?> showNewSessionDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => const NewSessionDialog(),
    );

/// "Fork" of a session: asks the first message of the fork.
Future<String?> showForkDialog(BuildContext context, Session parent) =>
    showDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => NewSessionDialog(forkOf: parent),
    );

class NewSessionDialog extends ConsumerStatefulWidget {
  const NewSessionDialog({super.key, this.forkOf});

  /// When set, the dialog creates a fork of this session.
  final Session? forkOf;

  @override
  ConsumerState<NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends ConsumerState<NewSessionDialog> {
  late final _title = TextEditingController(
    text: widget.forkOf == null
        ? ''
        : 'Fork de ${sessionTitle(widget.forkOf!)}',
  );
  final _prompt = TextEditingController();
  String? _agent;
  String _model = 'inherit';
  ClaudePermissionMode _mode = ClaudePermissionMode.defaultMode;
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
                title: _title.text,
                prompt: _prompt.text,
                agent: _agent,
                model: _model,
                permissionMode: _mode,
                useWorktree: _worktree,
              ),
            );
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
                                for (final a in agents)
                                  (
                                    a.name,
                                    a.project ? '${a.name} · projeto' : a.name,
                                  ),
                              ],
                              onChanged: (v) => setState(() => _agent = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            label('Modelo'),
                            dropdown<String>(
                              key: const ValueKey('new-session-model'),
                              value: _model,
                              items: [
                                for (final m in sessionModels)
                                  (m, m == 'inherit' ? 'inherit (padrão)' : m),
                              ],
                              onChanged: (v) => setState(() => _model = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  label('Modo de permissão'),
                  dropdown<ClaudePermissionMode>(
                    key: const ValueKey('new-session-mode'),
                    value: _mode,
                    items: [
                      for (final m in uiPermissionModes)
                        (m, '${m.cliValue} — ${permissionLabel(m)}'),
                    ],
                    onChanged: (v) => setState(() => _mode = v),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const ValueKey('new-session-worktree'),
                    value: _worktree,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() => _worktree = v ?? true),
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
