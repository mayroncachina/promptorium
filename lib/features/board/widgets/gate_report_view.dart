import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../step_gate.dart';

/// `✓ commit · ✓ testes · ✗ lint`; a tap opens [showGateReportDialog].
class GateChips extends StatelessWidget {
  const GateChips({super.key, required this.report, required this.keyPrefix});

  final GateReport report;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final c in report.checks)
        InkWell(
          key: ValueKey('$keyPrefix-${c.name}'),
          borderRadius: BorderRadius.circular(4),
          onTap: () => showGateReportDialog(context, report),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: c.ok ? SessionColors.addBg : SessionColors.delBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${c.ok ? '✓' : '✗'} ${c.label}',
              style: TextStyle(
                fontSize: 10,
                color: c.ok ? AppColors.teal : AppColors.red,
              ),
            ),
          ),
        ),
    ],
  );
}

/// "Ver saída da verificação": each check with its command, time and output.
Future<void> showGateReportDialog(
  BuildContext context,
  GateReport report,
) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (context) => Dialog(
    key: const ValueKey('gate-report-dialog'),
    backgroundColor: AppColors.panel,
    child: SizedBox(
      width: 760,
      height: 560,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              report.ok ? 'Verificação aprovada' : 'Verificação falhou',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: report.ok ? AppColors.teal : AppColors.red,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_when(report.at)}'
              '${report.attempt > 0 ? ' · ${report.attempt} reenvio(s) ao agente' : ''}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final c in report.checks)
                    _CheckTile(check: c, initiallyExpanded: !c.ok),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

String _when(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check, required this.initiallyExpanded});

  final GateCheck check;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final secs = check.duration.inMilliseconds / 1000;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('gate-check-${check.name}'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(
          check.ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: check.ok ? AppColors.teal : AppColors.red,
        ),
        title: Text(
          check.command == null
              ? check.label
              : '${check.label} · ${check.command}',
          style: const TextStyle(fontSize: 12, fontFamily: AppFonts.mono),
        ),
        subtitle: secs >= 0.1
            ? Text(
                '${secs.toStringAsFixed(1)} s',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              )
            : null,
        children: [
          if (check.output.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: SessionColors.terminalPanel,
              child: SelectableText(
                check.output.trimRight(),
                style: const TextStyle(fontSize: 11, fontFamily: AppFonts.mono),
              ),
            ),
        ],
      ),
    );
  }
}
