import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/agent_names.dart';
import '../sessions/widgets/session_style.dart';
import 'task_actions.dart';

/// "Nova tarefa" (title bar of the Tarefas screen). [specId] preselects the
/// spec. Returns the created task.
Future<Task?> showNewTaskDialog(BuildContext context, {int? specId}) =>
    showDialog<Task>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => NewTaskDialog(initialSpecId: specId),
    );

class NewTaskDialog extends ConsumerStatefulWidget {
  const NewTaskDialog({super.key, this.initialSpecId});

  final int? initialSpecId;

  @override
  ConsumerState<NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends ConsumerState<NewTaskDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _req = TextEditingController();
  final _deps = TextEditingController();
  late int? _specId = widget.initialSpecId;
  String? _agent;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _req.dispose();
    _deps.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ws = ref.read(activeWorkspaceProvider);
    if (ws == null) {
      setState(() => _error = 'Selecione um workspace na barra de título.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await ref
          .read(taskActionsProvider)
          .create(
            workspaceId: ws.id,
            title: _title.text,
            description: _body.text,
            specId: _specId,
            agentName: _agent,
            requirement: _req.text,
            dependsOn: parseTaskCodes(_deps.text),
          );
      if (mounted) Navigator.of(context).pop(t);
    } on TaskException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    final specs = ws == null
        ? const <Spec>[]
        : ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final agents =
        ref.watch(agentListProvider(ws?.path)).value ?? const <AgentRef>[];

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
        key: const ValueKey('new-task-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nova tarefa',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                label('Título'),
                TextField(
                  key: const ValueKey('new-task-title'),
                  controller: _title,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: deco('Ex.: Persistir eventos com drift'),
                ),
                label('Descrição'),
                TextField(
                  key: const ValueKey('new-task-body'),
                  controller: _body,
                  minLines: 3,
                  maxLines: 8,
                  style: const TextStyle(fontSize: 13),
                  decoration: deco('O que fazer e como verificar'),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          label('Spec'),
                          dropdown<int?>(
                            key: const ValueKey('new-task-spec'),
                            value: _specId,
                            items: [
                              (null, 'nenhuma'),
                              for (final s in specs)
                                (s.id, '${s.code} · ${s.title}'),
                            ],
                            onChanged: (v) => setState(() => _specId = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          label('Agente'),
                          dropdown<String?>(
                            key: const ValueKey('new-task-agent'),
                            value: _agent,
                            items: [
                              (null, 'nenhum'),
                              for (final a in agents) (a.name, a.name),
                            ],
                            onChanged: (v) => setState(() => _agent = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          label('Requisito'),
                          TextField(
                            key: const ValueKey('new-task-req'),
                            controller: _req,
                            style: const TextStyle(fontSize: 13),
                            decoration: deco('R1'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          label('Depende de'),
                          TextField(
                            key: const ValueKey('new-task-deps'),
                            controller: _deps,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: AppFonts.mono,
                            ),
                            decoration: deco('TASK-001, TASK-002'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const ValueKey('new-task-error'),
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
                      key: const ValueKey('new-task-submit'),
                      label: _busy ? 'Criando…' : 'Criar tarefa',
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
