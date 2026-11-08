import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../board/step_gate.dart';
import '../../board/widgets/gate_report_view.dart';
import '../../sessions/widgets/session_style.dart';
import '../conflict_resolution.dart';
import '../review_service.dart';

/// The conflict resolution of a Review item (SPEC-043): the gate running
/// on it, the failed report with the three ways out, what the resolution
/// decided and the outdated state.

String _short(String? sha) =>
    sha == null ? '' : sha.substring(0, sha.length.clamp(0, 7));

(IconData, Color) resolutionLook(ResolutionState s) => switch (s) {
  ResolutionState.resolvendo => (Icons.autorenew, AppColors.amber),
  ResolutionState.conferindo => (Icons.speed, AppColors.blue),
  ResolutionState.aprovada => (Icons.check, AppColors.teal),
  ResolutionState.reprovada => (
    Icons.disabled_by_default_outlined,
    AppColors.red,
  ),
  ResolutionState.desatualizada => (Icons.sync, AppColors.amber),
};

/// Pill of the header with the state of the resolution (R2).
class ResolutionChip extends ConsumerWidget {
  const ResolutionChip({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(conflictResolutionProvider(sessionId));
    if (r == null) return const SizedBox.shrink();
    final (icon, color) = resolutionLook(r.state);
    final text = switch (r.state) {
      ResolutionState.conferindo => 'Conferindo a resolução',
      ResolutionState.reprovada => ResolutionState.reprovada.label,
      _ => r.state.label,
    };
    return Semantics(
      label: r.text,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('review-resolution-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
          color: color.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The panel under the header while the item has a resolution.
class ConflictResolutionPanel extends ConsumerWidget {
  const ConflictResolutionPanel({
    super.key,
    required this.sessionId,
    required this.specCode,
    required this.busy,
    required this.run,
    required this.toast,
    required this.refresh,
  });

  final String sessionId;
  final String specCode;
  final bool busy;
  final Future<void> Function(String, Future<void> Function()) run;
  final void Function(String) toast;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(conflictResolutionProvider(sessionId));
    if (r == null) return const SizedBox.shrink();
    final resolver = ref.read(conflictResolverProvider);
    final files = r.files.isEmpty
        ? 'nos arquivos em conflito'
        : r.files.length == 1
        ? 'em ${r.files.single}'
        : 'em ${r.files.length} arquivos';
    final children = <Widget>[];
    switch (r.state) {
      case ResolutionState.resolvendo:
        final session = ref
            .watch(sessionsProvider(r.workspaceId))
            .value
            ?.where((s) => s.id == sessionId)
            .firstOrNull;
        final alive = session != null && !session.status.isTerminal;
        children.addAll([
          _Intro(
            'O agente está juntando a $specCode com a ${r.base} $files. '
            'Quando ele terminar, o app confere o resultado no worktree, fora '
            'do agente. O merge fica bloqueado até o gate aprovar.',
          ),
          if (!alive) ...[
            const SizedBox(height: 10),
            SmallButton(
              key: const ValueKey('review-resolution-check'),
              label: 'Conferir agora',
              icon: Icons.play_arrow,
              onTap: busy
                  ? null
                  : () => run('Conferir a resolução', () async {
                      await resolver.check(sessionId);
                      refresh();
                    }),
            ),
          ],
        ]);
      case ResolutionState.conferindo:
        children.addAll([
          _Intro(
            'O agente juntou a $specCode com a ${r.base} $files. Agora o app '
            'confere o resultado no worktree, fora do agente. O merge fica '
            'bloqueado até o gate aprovar.',
          ),
          const SizedBox(height: 12),
          _GateCard(resolution: r),
          ?_missingNote(r),
        ]);
      case ResolutionState.reprovada:
        children.addAll([
          _GateCard(resolution: r),
          if (r.automatic && r.autoFixUsed) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('review-resolution-auto-limit'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SessionColors.approvalBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SessionColors.approvalBorder),
              ),
              child: const Text(
                'A resolução automática já pediu uma correção ao agente e o '
                'gate reprovou de novo. As próximas correções são com você.',
                style: TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _WaysOut(
            resolution: r,
            busy: busy,
            fix: () => run('Corrigir e verificar', () async {
              await resolver.fix(sessionId);
              refresh();
              toast('Relatório do gate enviado ao agente da spec.');
            }),
            undo: () => run('Desfazer a resolução', () async {
              final sha = await resolver.undo(sessionId);
              refresh();
              toast(
                'A branch voltou para ${_short(sha)}, como estava antes da '
                'resolução. O conflito continua.',
              );
            }),
            myself: () => run('Resolver eu mesmo', () async {
              await resolver.resolveMyself(sessionId);
              refresh();
            }),
          ),
        ]);
      case ResolutionState.aprovada:
        children.addAll([
          if (r.report != null)
            GateChips(report: r.report!, keyPrefix: 'review-resolution-chip'),
          const SizedBox(height: 14),
          _Decisions(sessionId: sessionId, resolution: r, specCode: specCode),
        ]);
      case ResolutionState.desatualizada:
        children.addAll([
          Container(
            key: const ValueKey('review-resolution-outdated'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SessionColors.approvalBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SessionColors.approvalBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A ${r.base} mudou enquanto o agente resolvia ou o gate '
                  'rodava. O commit conferido, ${_short(r.checkedSha)}, não '
                  'contém a ponta atual da ${r.base}: o gate não pode '
                  'aprovar este resultado.',
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
                const SizedBox(height: 10),
                SmallButton(
                  key: const ValueKey('review-resolution-again'),
                  label: 'Resolver de novo',
                  color: AppColors.amber,
                  border: AppColors.amber,
                  onTap: busy
                      ? null
                      : () => run('Resolver de novo', () async {
                          await ref
                              .read(reviewServiceProvider)
                              .resolveConflict(sessionId);
                          refresh();
                          toast('Instruções do conflito enviadas ao agente.');
                        }),
                ),
              ],
            ),
          ),
        ]);
    }
    return Padding(
      key: const ValueKey('review-resolution-panel'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// "O projeto não tem build:, então esse item não aparece."
  static Widget? _missingNote(ConflictResolution r) {
    final missing = [
      for (final n in ['testes', 'lint', 'build'])
        if (!r.plan.contains(n)) '$n:',
    ];
    if (missing.isEmpty || r.plan.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'O projeto não tem ${missing.join(', ')}, então '
        '${missing.length == 1 ? 'esse item não aparece' : 'esses itens não aparecem'}.',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.text),
  );
}

/// "Gate da resolução": each item of the plan, done, running or waiting.
class _GateCard extends StatelessWidget {
  const _GateCard({required this.resolution});

  final ConflictResolution resolution;

  @override
  Widget build(BuildContext context) {
    final r = resolution;
    final done = r.report?.checks ?? const <GateCheck>[];
    final failed = r.state == ResolutionState.reprovada;
    final names = {for (final c in done) c.name};
    final rest = [
      for (final n in r.plan)
        if (!names.contains(n)) n,
    ];
    final rows = <Widget>[
      for (final c in done) _CheckRow(check: c, base: r.base),
      if (failed && rest.isNotEmpty)
        _Row(
          key: const ValueKey('review-resolution-not-run'),
          leading: const Icon(
            Icons.circle_outlined,
            size: 15,
            color: AppColors.textMuted,
          ),
          title: _list(rest.map(gateItemLabel).toList()),
          trailing: 'não rodaram: o gate para na primeira falha',
          muted: true,
        )
      else if (!failed)
        for (final n in rest)
          n == r.running
              ? _Row(
                  key: ValueKey('review-resolution-running-$n'),
                  highlight: true,
                  leading: const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.blue,
                    ),
                  ),
                  title: _title(n, r.base),
                  trailing: 'rodando',
                  trailingColor: AppColors.blue,
                )
              : _Row(
                  key: ValueKey('review-resolution-queued-$n'),
                  leading: const Icon(
                    Icons.circle_outlined,
                    size: 15,
                    color: AppColors.textMuted,
                  ),
                  title: _title(n, r.base),
                  trailing: 'na fila',
                  muted: true,
                ),
    ];
    return Container(
      key: const ValueKey('review-resolution-gate'),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: failed ? AppColors.red : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Gate da resolução',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Text(
                  [
                    if (r.checkedSha != null || failed)
                      'commit ${_short(r.checkedSha)}',
                    if (r.gates > 0) 'tentativa ${r.gates}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: AppFonts.mono,
                    color: AppColors.blue,
                  ),
                ),
              ],
            ),
          ),
          for (final row in rows) ...[
            const Divider(height: 1, color: AppColors.border),
            row,
          ],
        ],
      ),
    );
  }

  static String _list(List<String> labels) => labels.length <= 1
      ? labels.join()
      : '${labels.sublist(0, labels.length - 1).join(', ')} e ${labels.last}';
}

String _title(String name, String base) => switch (name) {
  'arvore' => 'Árvore limpa',
  'marcadores' => 'Sem marcadores de conflito',
  'base' => 'A branch contém a ponta da $base',
  'verificar' => 'verificar: dos critérios da spec',
  'contagem' => 'contagem de testes',
  _ => gateItemLabel(name),
};

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, required this.base});

  final GateCheck check;
  final String base;

  @override
  Widget build(BuildContext context) {
    final c = check;
    final title = c.command == null
        ? _title(c.name, base)
        : '${gateItemLabel(c.name)} · ${c.command}';
    final trailing = switch (c.name) {
      'marcadores' when c.ok =>
        c.output.split(' ').first == '1'
            ? '1 arquivo'
            : '${c.output.split(' ').first} arquivos',
      'base' when c.ok => _short(c.output.trim()),
      'testes' when c.count != null => '${c.count!.passed} passaram',
      'contagem' => c.output.split('\n').first,
      _ when !c.ok => 'falhou',
      _ =>
        c.duration.inMilliseconds >= 100
            ? '${(c.duration.inMilliseconds / 1000).toStringAsFixed(1)} s'
            : '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          key: ValueKey('review-resolution-check-${c.name}'),
          highlight: !c.ok,
          leading: Icon(
            c.ok ? Icons.check : Icons.disabled_by_default_outlined,
            size: 15,
            color: c.ok ? AppColors.teal : AppColors.red,
          ),
          title: title,
          trailing: trailing,
          trailingColor: c.ok ? null : AppColors.red,
        ),
        if (!c.ok && c.output.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SessionColors.terminalPanel,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              tailLines(c.output, 12),
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontFamily: AppFonts.mono,
                color: AppColors.text,
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.leading,
    required this.title,
    required this.trailing,
    this.trailingColor,
    this.muted = false,
    this.highlight = false,
  });

  final Widget leading;
  final String title, trailing;
  final Color? trailingColor;
  final bool muted, highlight;

  @override
  Widget build(BuildContext context) => Container(
    color: highlight ? AppColors.surfaceRaised : null,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        SizedBox(width: 18, child: Center(child: leading)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: muted ? AppColors.textSecondary : AppColors.text,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: trailingColor ?? AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The three ways out of a failed resolution (R3).
class _WaysOut extends StatelessWidget {
  const _WaysOut({
    required this.resolution,
    required this.busy,
    required this.fix,
    required this.undo,
    required this.myself,
  });

  final ConflictResolution resolution;
  final bool busy;
  final VoidCallback fix, undo, myself;

  @override
  Widget build(BuildContext context) {
    Widget card(
      String title,
      String text,
      Widget action, {
      bool main = false,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: main ? AppColors.amber : AppColors.border,
            width: main ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card(
            'Corrigir e verificar',
            'Envia este relatório ao agente da spec. O gate roda de novo '
                'quando ele terminar.',
            AmberButton(
              key: const ValueKey('review-resolution-fix'),
              label: 'Corrigir e verificar',
              onTap: busy ? null : fix,
            ),
            main: true,
          ),
          const SizedBox(width: 12),
          card(
            'Desfazer a resolução',
            'Volta a branch para ${_short(resolution.beforeSha)}, como estava '
                'antes da resolução. O conflito continua.',
            SmallButton(
              key: const ValueKey('review-resolution-undo'),
              label: 'Desfazer a resolução',
              onTap: busy ? null : undo,
            ),
          ),
          const SizedBox(width: 12),
          card(
            'Resolver eu mesmo',
            'Desfaz a resolução e começa o rebase no worktree, parado nos '
                'conflitos, para você editar.',
            SmallButton(
              key: const ValueKey('review-resolution-myself'),
              label: 'Começar rebase',
              onTap: busy ? null : myself,
            ),
          ),
        ],
      ),
    );
  }
}

/// "O que a resolução decidiu" (R4): per file, both sides, the result and
/// the agent's explanation.
class _Decisions extends ConsumerWidget {
  const _Decisions({
    required this.sessionId,
    required this.resolution,
    required this.specCode,
  });

  final String sessionId;
  final ConflictResolution resolution;
  final String specCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(resolutionDecisionsProvider(sessionId));
    final d = async.value;
    final byFile = <String, List<ResolutionHunk>>{};
    for (final h in d?.hunks ?? const <ResolutionHunk>[]) {
      byFile.putIfAbsent(h.path, () => []).add(h);
    }
    final count = d?.hunks.length ?? 0;
    return Column(
      key: const ValueKey('review-resolution-decisions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'O que a resolução decidiu',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            if (d != null && count > 0)
              Text(
                '${byFile.length} arquivo${byFile.length == 1 ? '' : 's'} · '
                '$count trecho${count == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (d == null)
          const Text(
            'Lendo a resolução…',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else ...[
          if (d.notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                d.notice!,
                key: const ValueKey('review-resolution-notice'),
                style: const TextStyle(fontSize: 12, color: AppColors.amber),
              ),
            ),
          for (final MapEntry(key: path, value: hunks) in byFile.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DecisionFile(
                path: path,
                hunks: hunks,
                base: resolution.base,
                specCode: specCode,
                explanation: d.explain(path),
                whole: d.how == null,
              ),
            ),
          if (d.raw != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: SessionColors.terminalPanel,
              child: SelectableText(
                d.raw!,
                style: const TextStyle(fontSize: 12, fontFamily: AppFonts.mono),
              ),
            ),
          if (byFile.isEmpty && d.raw == null) ...[
            const Text(
              'Nenhum trecho em conflito apareceu no diff da resolução.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (d.answer != null || d.how != null)
              _Explanation(
                text: d.how?.section ?? d.answer!,
                whole: d.how == null,
              ),
          ],
        ],
      ],
    );
  }
}

class _DecisionFile extends StatefulWidget {
  const _DecisionFile({
    required this.path,
    required this.hunks,
    required this.base,
    required this.specCode,
    required this.explanation,
    required this.whole,
  });

  final String path;
  final List<ResolutionHunk> hunks;
  final String base, specCode;
  final String? explanation;
  final bool whole;

  @override
  State<_DecisionFile> createState() => _DecisionFileState();
}

class _DecisionFileState extends State<_DecisionFile> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final hunks = widget.hunks;
    final i = _index.clamp(0, hunks.length - 1);
    final h = hunks[i];
    Widget nav(IconData icon, String key, VoidCallback? onTap) => InkWell(
      key: ValueKey(key),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null ? AppColors.textMuted : AppColors.text,
        ),
      ),
    );
    return Container(
      key: ValueKey('review-resolution-file-${widget.path}'),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.path,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.mono,
                      color: AppColors.text,
                    ),
                  ),
                ),
                if (hunks.length > 1) ...[
                  nav(
                    Icons.chevron_left,
                    'review-resolution-prev',
                    i == 0 ? null : () => setState(() => _index = i - 1),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  'Trecho ${i + 1} de ${hunks.length} · linhas '
                  '${h.line}–${h.endLine}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (hunks.length > 1) ...[
                  const SizedBox(width: 8),
                  nav(
                    Icons.chevron_right,
                    'review-resolution-next',
                    i == hunks.length - 1
                        ? null
                        : () => setState(() => _index = i + 1),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Side(title: 'Na ${widget.base}', lines: h.base),
                ),
                const VerticalDivider(width: 1, color: AppColors.border),
                Expanded(
                  child: _Side(
                    title: 'Nesta spec (${widget.specCode})',
                    lines: h.spec,
                  ),
                ),
                const VerticalDivider(width: 1, color: AppColors.border),
                Expanded(
                  child: _Side(
                    title: 'Resultado do agente',
                    lines: h.result,
                    result: true,
                  ),
                ),
              ],
            ),
          ),
          if (widget.explanation != null) ...[
            const Divider(height: 1, color: AppColors.border),
            _Explanation(text: widget.explanation!, whole: widget.whole),
          ],
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.title, required this.lines, this.result = false});

  final String title;
  final List<String> lines;
  final bool result;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: result ? AppColors.teal : AppColors.textSecondary,
          ),
        ),
      ),
      const Divider(height: 1, color: AppColors.border),
      Expanded(
        child: Container(
          color: result ? SessionColors.addBg : AppColors.background,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            lines.isEmpty ? '(vazio)' : lines.join('\n'),
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              fontFamily: AppFonts.mono,
              color: AppColors.text,
            ),
          ),
        ),
      ),
    ],
  );
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.text, required this.whole});

  final String text;
  final bool whole;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('review-resolution-explanation'),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          whole
              ? 'Resposta do agente · sem a seção ## Como resolvi'
              : 'Como resolvi · resposta do agente',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          text,
          style: const TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.text,
          ),
        ),
      ],
    ),
  );
}
