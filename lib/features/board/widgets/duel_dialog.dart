import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/diff_parser.dart';
import '../../../core/git/git_service.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../review/review_logic.dart';
import '../../review/review_service.dart' show ReviewDraft;
import '../../review/widgets/review_all_files.dart';
import '../../sessions/widgets/session_style.dart';
import '../spec_runner.dart';
import '../step_gate.dart';
import 'gate_report_view.dart';

/// Open best-of-N attempts of the workspace's specs (Quadro).
final openDuelsProvider = StreamProvider.family<List<SpecDuel>, int>(
  (ref, workspaceId) => ref.watch(specDuelsRepoProvider).watchOpen(workspaceId),
);

/// Diff of one attempt against the spec's HEAD when the duel started.
final _attemptDiffProvider = FutureProvider.autoDispose
    .family<List<DiffFile>, (String, String)>((ref, key) async {
      final (worktree, base) = key;
      final git = ref.read(gitServiceFactoryProvider)(worktree);
      try {
        return DiffParser.parse(
          await git.git(['diff', '--no-color', '--no-ext-diff', '-M', base]),
        );
      } on GitException {
        return const [];
      }
    });

/// "Comparar A/B" (F15): the gate, the files and the diff of each attempt;
/// the chosen one goes into the spec's branch.
Future<void> showDuelDialog(BuildContext context, SpecDuel duel) =>
    showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => _DuelDialog(duel: duel),
    );

class _DuelDialog extends ConsumerStatefulWidget {
  const _DuelDialog({required this.duel});

  final SpecDuel duel;

  @override
  ConsumerState<_DuelDialog> createState() => _DuelDialogState();
}

class _DuelDialogState extends ConsumerState<_DuelDialog> {
  String _shown = 'A';
  bool _busy = false;
  String? _error;

  Future<void> _do(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _side(String v) {
    final d = widget.duel;
    final wt = v == 'A' ? d.worktreeA : d.worktreeB;
    final report = GateReport.decode(v == 'A' ? d.reportA : d.reportB);
    final files =
        ref.watch(_attemptDiffProvider((wt, d.baseSha))).value ??
        const <DiffFile>[];
    final (add, del) = files.fold((
      0,
      0,
    ), (a, f) => (a.$1 + fileStats(f).$1, a.$2 + fileStats(f).$2));
    final on = _shown == v;
    return Expanded(
      child: InkWell(
        key: ValueKey('duel-side-$v'),
        onTap: () => setState(() => _shown = v),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? AppColors.amber : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tentativa $v',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${files.length} arquivo(s) · +$add −$del',
                key: ValueKey('duel-stats-$v'),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              if (report != null && report.checks.isNotEmpty)
                GateChips(report: report, keyPrefix: 'duel-gate-$v')
              else
                const Text(
                  'sem verificação',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              const SizedBox(height: 8),
              AmberButton(
                key: ValueKey('duel-choose-$v'),
                label: 'Escolher $v',
                height: 28,
                onTap: _busy
                    ? null
                    : () => _do(
                        () => ref
                            .read(specRunnerProvider)
                            .chooseDuel(widget.duel.id, v),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.duel;
    final wt = _shown == 'A' ? d.worktreeA : d.worktreeB;
    final files =
        ref.watch(_attemptDiffProvider((wt, d.baseSha))).value ??
        const <DiffFile>[];
    return Dialog(
      key: const ValueKey('duel-dialog'),
      backgroundColor: AppColors.panel,
      child: SizedBox(
        width: 980,
        height: 680,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Comparar A/B · ${d.steps}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'A etapa rodou duas vezes, em worktrees separados. A escolhida '
                'entra na branch da spec; a outra é apagada.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [_side('A'), const SizedBox(width: 12), _side('B')],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ReviewAllFiles(
                  key: ValueKey('duel-diff-$_shown'),
                  files: files,
                  draft: const ReviewDraft(),
                  readOnly: true,
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
              const SizedBox(height: 8),
              Row(
                children: [
                  SmallButton(
                    key: const ValueKey('duel-discard'),
                    label: 'Descartar as duas',
                    color: AppColors.red,
                    onTap: _busy
                        ? null
                        : () => _do(
                            () =>
                                ref.read(specRunnerProvider).discardDuel(d.id),
                          ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
