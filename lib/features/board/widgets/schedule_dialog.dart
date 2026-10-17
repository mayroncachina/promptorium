import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../autopilot.dart';

/// "Agendar Autopilot" (F17): time of day and budget of that run.
Future<void> showScheduleDialog(
  BuildContext context,
  WidgetRef ref,
  int workspaceId,
) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _ScheduleDialog(workspaceId: workspaceId),
);

class _ScheduleDialog extends ConsumerStatefulWidget {
  const _ScheduleDialog({required this.workspaceId});

  final int workspaceId;

  @override
  ConsumerState<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends ConsumerState<_ScheduleDialog> {
  late final AutopilotSchedule? _saved = ref
      .read(autopilotProvider.notifier)
      .scheduleOf(widget.workspaceId);
  late final _time = TextEditingController(
    text: _saved?.encode().split('|').first ?? '02:00',
  );
  late final _budget = TextEditingController(
    text: _saved?.budgetUsd?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _time.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final b = _budget.text.trim().replaceAll(',', '.');
    final s = AutopilotSchedule.decode(
      b.isEmpty ? _time.text.trim() : '${_time.text.trim()}|$b',
    );
    if (s == null) {
      setState(() => _error = 'Use HH:MM (ex.: 02:30) e um valor em US\$.');
      return;
    }
    await ref
        .read(autopilotProvider.notifier)
        .setSchedule(widget.workspaceId, s);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('schedule-dialog'),
    backgroundColor: AppColors.panel,
    title: const Text('Agendar Autopilot', style: TextStyle(fontSize: 16)),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Todo dia, nesse horário, o Autopilot liga sozinho (com o app '
            'aberto) e para ao atingir o orçamento do dia.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('schedule-time'),
            controller: _time,
            decoration: const InputDecoration(
              labelText: 'Horário (HH:MM)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('schedule-budget'),
            controller: _budget,
            decoration: const InputDecoration(
              labelText: 'Orçamento do dia em US\$ (vazio = o do config)',
              isDense: true,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.red),
              ),
            ),
        ],
      ),
    ),
    actions: [
      if (_saved != null)
        TextButton(
          key: const ValueKey('schedule-remove'),
          onPressed: () async {
            await ref
                .read(autopilotProvider.notifier)
                .setSchedule(widget.workspaceId, null);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Remover agendamento'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      TextButton(
        key: const ValueKey('schedule-save'),
        onPressed: _save,
        child: const Text('Salvar'),
      ),
    ],
  );
}
