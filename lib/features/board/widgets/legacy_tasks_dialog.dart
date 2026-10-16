import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart';
import '../board_screen.dart';

/// Markdown of the draft spec made from an old task: its title is the
/// objective's subject and the single requirement; its text, the objective.
String specFromTaskMarkdown(Task task, String code) {
  final body = task.body?.trim() ?? '';
  return '''
---
id: $code
status: ${specStatusValue(SpecStatus.draft)}
---

# ${task.title}

## Objetivo

${body.isEmpty ? task.title : body}

## Requisitos

- R1 · ${task.title}

## Critérios de aceite

- [ ]
''';
}

/// Old tasks (before the spec became the card) that are not a step of any
/// spec: each one can become a draft spec or be discarded.
Future<void> showLegacyTasksDialog(
  BuildContext context,
  Workspace ws,
  List<Task> tasks,
) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _LegacyTasksDialog(ws: ws),
);

class _LegacyTasksDialog extends ConsumerStatefulWidget {
  const _LegacyTasksDialog({required this.ws});

  final Workspace ws;

  @override
  ConsumerState<_LegacyTasksDialog> createState() => _LegacyTasksDialogState();
}

class _LegacyTasksDialogState extends ConsumerState<_LegacyTasksDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _toSpec(Task t) => _do(() async {
    await ref
        .read(specServiceProvider)
        .create(
          widget.ws,
          title: t.title,
          render: (code) => specFromTaskMarkdown(t, code),
        );
    await ref.read(tasksRepoProvider).delete(t.id);
  });

  Future<void> _discard(Task t) =>
      _do(() => ref.read(tasksRepoProvider).delete(t.id));

  Future<void> _do(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks =
        ref.watch(legacyTasksProvider(widget.ws.id)).value ?? const <Task>[];
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Material(
        key: const ValueKey('legacy-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 600,
          height: 480,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tarefas antigas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Não pertencem a nenhuma etapa de spec. Transformar cria uma '
                  'spec em rascunho (specs/SPEC-NNN-….md) com a tarefa como '
                  'requisito R1; aprove-a em Specs para ela entrar no quadro.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: tasks.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhuma tarefa antiga.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (_, i) {
                            final t = tasks[i];
                            return Padding(
                              key: ValueKey('legacy-${t.code}'),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 76,
                                    child: Text(
                                      t.code,
                                      style: const TextStyle(
                                        fontFamily: AppFonts.mono,
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      t.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SmallButton(
                                    key: ValueKey('legacy-spec-${t.code}'),
                                    label: 'Virar spec',
                                    height: 26,
                                    onTap: _busy ? null : () => _toSpec(t),
                                  ),
                                  const SizedBox(width: 6),
                                  SmallButton(
                                    key: ValueKey('legacy-drop-${t.code}'),
                                    label: 'Descartar',
                                    height: 26,
                                    color: AppColors.red,
                                    onTap: _busy ? null : () => _discard(t),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: SmallButton(
                    label: 'Fechar',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
