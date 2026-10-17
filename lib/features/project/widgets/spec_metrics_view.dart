import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../spec_metrics.dart';

/// Projeto → Métricas (F14): per spec, cost, time, automatic fixes of the
/// gate, review rounds and rejected hunks.
class SpecMetricsView extends ConsumerWidget {
  const SpecMetricsView({super.key, required this.workspace});

  final Workspace workspace;

  static String _time(Duration d) => d.inHours > 0
      ? '${d.inHours} h ${d.inMinutes % 60} min'
      : d.inMinutes > 0
      ? '${d.inMinutes} min'
      : '${d.inSeconds} s';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(specMetricsProvider(workspace.id)).value;
    const head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );
    const cell = TextStyle(fontSize: 12, fontFamily: AppFonts.mono);
    if (list == null) return const Center(child: Text('Calculando…'));
    final total = list.fold(0.0, (a, m) => a + m.cost);
    final resends = list.fold(0, (a, m) => a + m.gateResends);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Métricas de qualidade',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          list.isEmpty
              ? 'Nenhuma spec executada ainda.'
              : '${list.length} spec(s) · ${formatCost(total)} · '
                    '$resends correção(ões) automática(s) da verificação',
          key: const ValueKey('metrics-summary'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        if (list.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const ValueKey('metrics-table'),
              headingRowHeight: 32,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 48,
              columns: const [
                DataColumn(label: Text('Spec', style: head)),
                DataColumn(label: Text('Custo', style: head), numeric: true),
                DataColumn(label: Text('Tempo', style: head), numeric: true),
                DataColumn(label: Text('Sessões', style: head), numeric: true),
                DataColumn(
                  label: Text('Correções\nautomáticas', style: head),
                  numeric: true,
                ),
                DataColumn(label: Text('Rodadas\nrevisor / você', style: head)),
                DataColumn(
                  label: Text('Hunks\nrejeitados', style: head),
                  numeric: true,
                ),
                DataColumn(label: Text('Tempo por etapa', style: head)),
              ],
              rows: [
                for (final m in list)
                  DataRow(
                    key: ValueKey('metrics-${m.spec.code}'),
                    cells: [
                      DataCell(
                        Text(
                          '${m.spec.code} · ${m.spec.title}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DataCell(Text(formatCost(m.cost), style: cell)),
                      DataCell(Text(_time(m.time), style: cell)),
                      DataCell(Text('${m.sessions}', style: cell)),
                      DataCell(Text('${m.gateResends}', style: cell)),
                      DataCell(
                        Text(
                          '${m.reviewerRounds} / ${m.humanRounds}',
                          style: cell,
                        ),
                      ),
                      DataCell(Text('${m.rejectedHunks}', style: cell)),
                      DataCell(
                        Text(
                          [
                            for (final MapEntry(:key, :value)
                                in m.stepTime.entries)
                              '$key ${_time(value)}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
