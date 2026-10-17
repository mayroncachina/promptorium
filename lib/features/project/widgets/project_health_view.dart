import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../board/board_rules.dart';
import '../../board/board_screen.dart' show specStepsProvider;
import '../../board/step_gate.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_config.dart';
import '../project_memory.dart';
import '../spec_metrics.dart';
import '../stack_detect.dart';

/// Projeto › Saúde (UX v2, U6; docs/mockups/v2/Projeto.dc.html): the last
/// specs in numbers, the gate of each one, the memory with who wrote each
/// line and how the Promptorium works in this repository.
class ProjectHealthView extends ConsumerWidget {
  const ProjectHealthView({super.key, required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = workspace;
    final metrics = ref.watch(specMetricsProvider(ws.id)).value;
    final config = ref.watch(projectConfigProvider(ws.path)).value;
    final memory =
        ref.watch(projectMemoryProvider(ws.path)).value ??
        const ProjectMemory([]);
    final specs = ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final rows = ref.watch(specStepsProvider(ws.id)).value ?? const [];
    final sessions = ref.watch(sessionsProvider(ws.id)).value ?? const [];
    final last = (metrics ?? const <SpecMetrics>[]).reversed.take(10).toList();

    return ListView(
      key: const ValueKey('project-health'),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ws.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ws.path,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SmallButton(
              key: const ValueKey('health-analyze'),
              label: 'Analisar repositório',
              onTap: () => showAnalyzeDialog(context, ref, ws),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _section('Últimas 10 specs'),
        if (metrics == null)
          const Text('Calculando…', style: TextStyle(fontSize: 12))
        else if (last.isEmpty)
          const Text(
            'Nenhuma spec executada ainda.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else
          _Stats(metrics: last),
        const SizedBox(height: 18),
        _section('Gate por spec'),
        if (last.isEmpty)
          const Text(
            'Aparece depois da primeira spec executada.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else
          _GateTable(metrics: last, rows: rows),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _section('Memória do projeto')),
            Text(
              '${ProjectMemory.filePath} · ${memory.entries.length} '
              '${memory.entries.length == 1 ? 'linha' : 'linhas'}',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (memory.isEmpty)
          const Text(
            'Vazia por enquanto. As sessões gravam APRENDIZADO: e a '
            'verificação anota quanto os comandos demoram.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        for (final e in memory.entries.reversed.take(6)) _MemoryRow(entry: e),
        const SizedBox(height: 18),
        _section('Como o Promptorium trabalha aqui'),
        if (config == null)
          const Text('Lendo a configuração…', style: TextStyle(fontSize: 12))
        else
          _HowItWorks(config: config, specs: specs, sessions: sessions),
      ],
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: sectionTitleStyle),
  );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.metrics});

  final List<SpecMetrics> metrics;

  @override
  Widget build(BuildContext context) {
    final n = metrics.length;
    final cost = metrics.fold(0.0, (a, m) => a + m.cost) / n;
    final reviewer = metrics.fold(0, (a, m) => a + m.reviewerRounds) / n;
    final human = metrics.fold(0, (a, m) => a + m.humanRounds) / n;
    final steps = metrics.fold(0, (a, m) => a + m.stepTime.length);
    final resends = metrics.fold(0, (a, m) => a + m.gateResends);
    final hunks = metrics.fold(0, (a, m) => a + m.rejectedHunks);
    final time = metrics.fold(Duration.zero, (a, m) => a + m.time);
    final perStep = steps == 0
        ? Duration.zero
        : Duration(seconds: time.inSeconds ~/ steps);
    String f1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _stat('Custo médio por spec', formatCost(cost), 'em $n specs'),
        _stat(
          'Rodadas de correção',
          f1(reviewer + human),
          'revisor ${f1(reviewer)} · você ${f1(human)}',
        ),
        _stat(
          'Reenvios do gate',
          steps == 0 ? '0' : f1(resends / steps),
          'por etapa',
        ),
        _stat(
          'Hunks rejeitados',
          '$hunks',
          hunks == 0 ? 'nenhum nas últimas $n' : 'nas últimas $n',
        ),
        _stat('Tempo por etapa', formatDuration(perStep), '$steps etapas'),
      ],
    );
  }

  Widget _stat(String label, String value, String hint) => Container(
    width: 180,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          hint,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _GateTable extends StatelessWidget {
  const _GateTable({required this.metrics, required this.rows});

  final List<SpecMetrics> metrics;
  final List<SpecStep> rows;

  /// Last gate of the spec (its last verified step).
  GateReport? _lastGate(Spec spec) {
    GateReport? out;
    for (final st in stepsOf(spec, rows)) {
      if (st.gate != null) out = st.gate;
    }
    return out;
  }

  Widget _check(GateReport? g, String name) {
    final c = g?.checks.where((c) => c.name == name).firstOrNull;
    if (c == null) {
      return const Text('—', style: TextStyle(color: AppColors.textMuted));
    }
    final secs = c.duration.inSeconds;
    return Text(
      c.ok ? '✓${secs > 0 ? ' · $secs s' : ''}' : '✗',
      style: TextStyle(color: c.ok ? AppColors.teal : AppColors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );
    const cell = TextStyle(fontSize: 12, fontFamily: AppFonts.mono);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const ValueKey('health-gate-table'),
          headingRowHeight: 32,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 40,
          columns: const [
            DataColumn(label: Text('Spec', style: head)),
            DataColumn(label: Text('Testes', style: head)),
            DataColumn(label: Text('Lint', style: head)),
            DataColumn(label: Text('Reenvios', style: head), numeric: true),
            DataColumn(label: Text('Revisor', style: head)),
            DataColumn(label: Text('Custo', style: head), numeric: true),
          ],
          rows: [
            for (final m in metrics)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      '${m.spec.code} ${m.spec.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  DataCell(
                    DefaultTextStyle.merge(
                      style: cell,
                      child: _check(_lastGate(m.spec), 'testes'),
                    ),
                  ),
                  DataCell(
                    DefaultTextStyle.merge(
                      style: cell,
                      child: _check(_lastGate(m.spec), 'lint'),
                    ),
                  ),
                  DataCell(Text('${m.gateResends}', style: cell)),
                  DataCell(
                    Text(
                      m.reviewerRounds == 0
                          ? '—'
                          : '${m.reviewerRounds} rodada(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(Text(formatCost(m.cost), style: cell)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.entry});

  final MemoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final o = entry.origin;
    final (bg, fg) = o == 'você'
        ? (AppColors.amberTint, AppColors.amber)
        : o == 'verificação' || o == 'análise'
        ? (SessionColors.runningToolBg, AppColors.teal)
        : (const Color(0xFF2A2233), AppColors.lilac);
    final d = entry.date;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              o,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(entry.text, style: const TextStyle(fontSize: 12)),
          ),
          if (d != null) ...[
            const SizedBox(width: 10),
            Text(
              '${d.day.toString().padLeft(2, '0')}/'
              '${d.month.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({
    required this.config,
    required this.specs,
    required this.sessions,
  });

  final ProjectConfig config;
  final List<Spec> specs;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) {
    final c = config;
    final w = c.worktree;
    Widget card(String label, String value, String hint, {Color? hintColor}) =>
        Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
              ),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 11,
                  color: hintColor ?? AppColors.textMuted,
                ),
              ),
            ],
          ),
        );
    return Wrap(
      key: const ValueKey('health-config'),
      spacing: 10,
      runSpacing: 10,
      children: [
        card(
          'Testes',
          c.testCommand ?? '—',
          c.testCommand == null
              ? 'sem gate: "Analisar repositório" sugere'
              : 'gate ligado',
          hintColor: c.testCommand == null ? AppColors.amber : AppColors.teal,
        ),
        card(
          'Lint · Formatar',
          [c.lintCommand, c.formatCommand].whereType<String>().join(' · '),
          c.formatCommand == null ? 'sem hook de formatação' : 'hooks ligados',
          hintColor: c.formatCommand == null
              ? AppColors.textMuted
              : AppColors.teal,
        ),
        card(
          'Revisor',
          c.reviewer.enabled
              ? '${c.reviewer.model} · ${c.reviewer.rounds} rodadas · '
                    '${formatCost(c.reviewer.budgetUsd)}'
              : 'desligado',
          c.reviewer.enabled ? 'ligado' : 'liga em Configurações',
          hintColor: c.reviewer.enabled ? AppColors.teal : AppColors.textMuted,
        ),
        card(
          'Worktree',
          [
            if (w.copy.isNotEmpty) w.copy.join(', '),
            if (w.prepare != null) w.prepare!,
            if (w.basePort != null) ':${w.basePort}+',
          ].join(' · ').ifEmpty('—'),
          '${specs.where((s) => s.worktreePath != null).length} worktree(s) '
              'de spec · ${sessions.length} sessões',
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String alt) => isEmpty ? alt : this;
}

/// "Analisar repositório": shows what was detected and applies it to the
/// empty fields of the config plus a memory line.
Future<void> showAnalyzeDialog(
  BuildContext context,
  WidgetRef ref,
  Workspace ws,
) async {
  final d = await detectStack(ws.path);
  if (!context.mounted) return;
  final config = ProjectConfig.loadSync(ws.path);
  final (_, changes) = applyDetection(config, d);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('analyze-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        d.isUnknown ? 'Stack não reconhecida' : 'Stack: ${d.name}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.isUnknown
                  ? 'Nenhum arquivo conhecido na raiz (pubspec.yaml, '
                        'package.json, pyproject.toml, Cargo.toml, go.mod, '
                        'Makefile). Preencha a Configuração à mão.'
                  : 'Lido de ${d.evidence.join(', ')}. Só os campos vazios da '
                        'configuração são preenchidos; o que você já escreveu '
                        'fica.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (final (k, v) in [
              ('testes', d.tests),
              ('lint', d.lint),
              ('formatar', d.format),
              ('preparar', d.prepare),
            ])
              if (v != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          k,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          v,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            if (!d.isUnknown && !changes)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'A configuração já tem tudo isso; só a memória é anotada.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        if (!d.isUnknown)
          TextButton(
            key: const ValueKey('analyze-apply'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Aplicar'),
          ),
      ],
    ),
  );
  if (ok != true) return;
  await applyDetectionToWorkspace(ws.path, d);
  ref.invalidate(projectConfigProvider(ws.path));
  ref.invalidate(projectMemoryProvider(ws.path));
}
