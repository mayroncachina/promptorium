import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../review/review_service.dart' show selectedReviewProvider;
import '../../sessions/widgets/session_style.dart';
import 'release_dispatcher.dart';
import 'releases_tab.dart' show openExternal;

/// Green of a finished job (the mockup's `#5BC88A`).
const _done = Color(0xFF5BC88A);

/// `6 min 12 s`, `48 s`.
String formatElapsed(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final m = d.inMinutes, s = d.inSeconds % 60;
  return m == 0 ? '$s s' : '$m min $s s';
}

/// `4:51`, `48 s`.
String formatJobTime(Duration d) {
  if (d.isNegative) d = Duration.zero;
  if (d.inMinutes == 0) return '${d.inSeconds} s';
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// The release being followed (R7) and how it ended (R8)
/// (docs/mockups/spec-044/3-acompanhando.png).
class ReleaseRunCard extends ConsumerStatefulWidget {
  const ReleaseRunCard({super.key, required this.run, required this.onRetry});

  final ReleaseRun run;

  /// "Disparar de novo" (R8): the dialog again, with the same version.
  final VoidCallback onRetry;

  @override
  ConsumerState<ReleaseRunCard> createState() => _ReleaseRunCardState();
}

class _ReleaseRunCardState extends ConsumerState<ReleaseRunCard> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // The elapsed time ticks between polls.
    if (!widget.run.status.done) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(ReleaseRunCard old) {
    super.didUpdateWidget(old);
    if (widget.run.status.done) {
      _clock?.cancel();
      _clock = null;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  ReleaseDispatcher get _dispatcher =>
      ref.read(releaseDispatcherProvider.notifier);

  Future<void> _cancel() async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('release-cancel-confirm'),
        backgroundColor: AppColors.panel,
        title: Text(
          'Cancelar a release ${widget.run.tag}?',
          style: const TextStyle(fontSize: 16),
        ),
        content: const Text(
          'O GitHub para a execução. O que ela já fez (tag, rascunho) fica '
          'como está e é resolvido no GitHub.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          TextButton(
            key: const ValueKey('release-cancel-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Cancelar execução',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _dispatcher.cancel(widget.run.workspaceId);
    } on GhException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showAppToast(SnackBar(content: Text('Não foi possível cancelar: $e')));
    }
  }

  /// "Abrir no Review": the session whose PR this is (the Review follows
  /// PRs of sessions; a PR the workflow opened has none).
  String? _sessionOf(String url) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) return null;
    final sessions = ref.watch(sessionsProvider(ws.id)).value ?? const [];
    return sessions.where((s) => s.prUrl == url).firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final status = run.status;
    final (label, color) = switch (status) {
      ReleaseRunStatus.finding => ('Procurando a execução', AppColors.blue),
      ReleaseRunStatus.running => ('Em andamento', AppColors.blue),
      ReleaseRunStatus.success => ('Publicada', _done),
      ReleaseRunStatus.failure => ('Falhou', AppColors.red),
      ReleaseRunStatus.cancelled => ('Cancelada', AppColors.textSecondary),
      ReleaseRunStatus.draftCreated => ('Rascunho criado', AppColors.blue),
    };
    final elapsed = DateTime.now().toUtc().difference(run.dispatchedAt);
    final sub = [
      if (run.workflowName.isNotEmpty) run.workflowName,
      'disparada por você às ${formatClock(run.dispatchedAt)}',
      if (run.runId != null) 'run #${run.runId}',
    ].join(' · ');
    final url = run.runUrl ?? run.releaseUrl;
    return Container(
      key: const ValueKey('release-run-card'),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == ReleaseRunStatus.failure
              ? SessionColors.stopBorder
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!status.done)
                            const SizedBox.square(
                              dimension: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.blue,
                              ),
                            )
                          else
                            Icon(
                              status == ReleaseRunStatus.failure
                                  ? Icons.close
                                  : Icons.check,
                              size: 15,
                              color: color,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            status.done
                                ? label
                                : '$label · ${formatElapsed(elapsed)}',
                            key: const ValueKey('release-run-status'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                          children: [
                            const TextSpan(text: 'Release '),
                            TextSpan(
                              text: run.tag,
                              style: const TextStyle(fontFamily: AppFonts.mono),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (url != null) ...[
                  SmallButton(
                    key: const ValueKey('release-run-github'),
                    label: 'Abrir no GitHub',
                    height: 40,
                    fontSize: 14,
                    onTap: () => openExternal(ref, url),
                  ),
                ],
                if (!status.done && run.runId != null) ...[
                  const SizedBox(width: 12),
                  SmallButton(
                    key: const ValueKey('release-run-cancel'),
                    label: 'Cancelar execução',
                    height: 40,
                    fontSize: 14,
                    color: AppColors.red,
                    border: SessionColors.stopBorder,
                    onTap: _cancel,
                  ),
                ],
                if (status == ReleaseRunStatus.failure) ...[
                  const SizedBox(width: 12),
                  AmberButton(
                    key: const ValueKey('release-run-retry'),
                    label: 'Disparar de novo',
                    height: 40,
                    fontSize: 14,
                    onTap: widget.onRetry,
                  ),
                ],
                if (status.done) ...[
                  const SizedBox(width: 12),
                  SmallButton(
                    key: const ValueKey('release-run-dismiss'),
                    label: 'Fechar',
                    height: 40,
                    fontSize: 14,
                    onTap: () => _dispatcher.dismiss(run.workspaceId),
                  ),
                ],
              ],
            ),
          ),
          if (run.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                run.error!,
                style: const TextStyle(fontSize: 12, color: AppColors.amber),
              ),
            ),
          if (run.jobs.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: _Progress(jobs: run.jobs),
            ),
            for (final j in run.jobs)
              _JobRow(job: j, expanded: j.status == 'in_progress'),
          ],
          ..._outcome(run),
          if (!status.done) ...[
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Text(
                'Atualiza a cada 10 s nesta tela e a cada 60 s fora dela. Se '
                'o app fechar, o acompanhamento volta ao abrir.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _outcome(ReleaseRun run) {
    switch (run.status) {
      case ReleaseRunStatus.success:
        final pr = run.prUrl;
        final session = pr == null ? null : _sessionOf(pr);
        return [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: pr == null
                ? Text(
                    '${run.tag} publicada. O workflow não abriu um PR da '
                    'versão.',
                    style: const TextStyle(fontSize: 13),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${run.tag} publicada. PR da versão: '
                          '#${run.prNumber ?? ''}',
                          key: const ValueKey('release-run-pr'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      SmallButton(
                        key: const ValueKey('release-run-pr-open'),
                        label: 'Abrir PR',
                        onTap: () => openExternal(ref, pr),
                      ),
                      if (session != null) ...[
                        const SizedBox(width: 8),
                        SmallButton(
                          key: const ValueKey('release-run-review'),
                          label: 'Abrir no Review',
                          onTap: () {
                            ref
                                .read(selectedReviewProvider.notifier)
                                .select(session);
                            ref
                                .read(navigationProvider.notifier)
                                .request(AppSection.review);
                          },
                        ),
                      ],
                    ],
                  ),
          ),
        ];
      case ReleaseRunStatus.failure:
        return [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  run.failedJob == null
                      ? 'A execução falhou.'
                      : 'Falhou em ${run.failedJob}'
                            '${run.failedStep == null ? '' : ' · ${run.failedStep}'}',
                  key: const ValueKey('release-run-failed-step'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.red,
                  ),
                ),
                if (run.failedLog.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: SessionColors.terminalPanel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        run.failedLog.join('\n'),
                        key: const ValueKey('release-run-log'),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ];
      case ReleaseRunStatus.draftCreated:
        return [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'O rascunho da ${run.tag} está no GitHub. Publique por lá: a '
              'tag nasce na publicação.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ];
      default:
        return const [];
    }
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.jobs});

  final List<GhJob> jobs;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: 5,
      child: Row(
        children: [
          for (final j in jobs)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 1),
                color: switch (j) {
                  _ when j.conclusion == 'success' => _done,
                  _ when j.conclusion == 'failure' => AppColors.red,
                  _ when j.status == 'in_progress' => AppColors.blue,
                  _ => AppColors.border,
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.expanded});

  final GhJob job;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final running = job.status == 'in_progress';
    final done = job.status == 'completed';
    final failed = done && job.conclusion == 'failure';
    final current = job.steps
        .where((s) => s.status == 'in_progress')
        .firstOrNull;
    final (state, color) = failed
        ? ('falhou', AppColors.red)
        : done
        ? (job.conclusion == 'skipped' ? 'pulado' : 'pronto', _done)
        : running
        ? (
            current == null
                ? 'rodando'
                : 'etapa ${job.steps.indexOf(current) + 1} de '
                      '${job.steps.length}',
            AppColors.blue,
          )
        : ('na fila', AppColors.textSecondary);
    final start = job.startedAt;
    final time = start == null
        ? ''
        : formatJobTime(
            (job.completedAt ?? DateTime.now().toUtc()).difference(start),
          );
    return Container(
      key: ValueKey('release-job-${job.name}'),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                child: running
                    ? const SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.blue,
                        ),
                      )
                    : Icon(
                        failed
                            ? Icons.close
                            : done
                            ? Icons.check
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: color,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  job.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(state, style: TextStyle(fontSize: 13, color: color)),
              SizedBox(
                width: 76,
                child: Text(
                  time,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (expanded)
            for (final s in job.steps)
              if (s.conclusion != 'skipped' &&
                  !s.name.startsWith('Set up') &&
                  !s.name.startsWith('Post ') &&
                  s.name != 'Complete job')
                Padding(
                  padding: const EdgeInsets.only(left: 34, top: 8),
                  child: Row(
                    children: [
                      Dot(
                        s.conclusion == 'success'
                            ? _done
                            : s.conclusion == 'failure'
                            ? AppColors.red
                            : s.status == 'in_progress'
                            ? AppColors.blue
                            : AppColors.textMuted,
                        size: 6,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: s.status == 'queued' || s.status == 'pending'
                                ? AppColors.textSecondary
                                : AppColors.text,
                          ),
                        ),
                      ),
                      if (s.startedAt != null)
                        Text(
                          formatJobTime(
                            (s.completedAt ?? DateTime.now().toUtc())
                                .difference(s.startedAt!),
                          ),
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
