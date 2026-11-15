import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../repository/releases/releases_tab.dart' show openExternal;
import '../../sessions/widgets/session_style.dart';
import '../ci_fixer.dart';
import '../ci_log.dart';
import '../pr_babysitter.dart';

/// "Corrigir CI" with the warning of a PR brought without write permission
/// (SPEC-073 R10). Returns whether something was sent or queued.
Future<bool> confirmAndFixCi(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
) async {
  final fixer = ref.read(ciFixerProvider.notifier);
  if (fixer.pushBlocked(sessionId)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('ci-fix-local-warning'),
        title: const Text('Corrigir CI'),
        content: const Text(
          'Você não tem permissão de escrita neste PR. O commit fica '
          'local; use Copiar patch para mandar ao autor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('ci-fix-local-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Corrigir mesmo assim'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }
  return fixer.fix(sessionId);
}

/// The failed checks of the PR in the Review (SPEC-073 R2): one row per
/// check with the step that failed and the excerpt of its log, "Corrigir
/// CI", "Rodar de novo" and where the fix is.
class CiPanel extends ConsumerStatefulWidget {
  const CiPanel({super.key, required this.sessionId, required this.status});

  final String sessionId;
  final PrStatus status;

  @override
  ConsumerState<CiPanel> createState() => _CiPanelState();
}

class _CiPanelState extends ConsumerState<CiPanel> {
  bool _busy = false;
  String? _error;
  final _open = <String>{};
  Future<CiFailure>? _failure;
  String? _failureSha;

  String get _id => widget.sessionId;

  Future<CiFailure>? _load(PrStatus status) {
    if (status.failedChecks.isEmpty) return null;
    if (_failure == null || _failureSha != status.headSha) {
      _failureSha = status.headSha;
      _failure = ref.read(ciFixerProvider.notifier).failure(_id, status);
    }
    return _failure;
  }

  Future<void> _do(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final st = ref.watch(ciFixerProvider)[_id];
    final failed = status.failedChecks;
    if (failed.isEmpty && st == null) return const SizedBox.shrink();
    final future = _load(status);
    return Container(
      key: const ValueKey('ci-panel'),
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: failed.isEmpty
              ? AppColors.border
              : AppColors.red.withValues(alpha: .45),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<CiFailure>(
          future: future,
          builder: (context, snap) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (st != null) _phase(st),
              if (failed.isNotEmpty) ...[
                _header(status, st, snap.data),
                const SizedBox(height: 4),
                const Text(
                  'O log dos jobs que falharam vai para a sessão. O agente '
                  'corrige, roda os testes afetados e commita. O app envia o '
                  'commit para o PR.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                if (snap.data?.excerpt.flaky case final why?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Parece intermitente: $why',
                      key: const ValueKey('ci-flaky'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SelectableText(
                      _error!,
                      key: const ValueKey('ci-error'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (snap.hasError)
                  Text(
                    'Log não lido: ${snap.error}',
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  )
                else if (snap.data == null)
                  const Text(
                    'Lendo o log dos checks…',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                for (final c in failed) _row(c, snap.data),
                _passed(status),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(PrStatus status, CiFixState? st, CiFailure? failure) {
    final fixer = ref.read(ciFixerProvider.notifier);
    final reason = failure?.blockReason;
    final inFlight = st?.inFlight ?? false;
    final flaky = failure?.excerpt.flaky != null;
    final runs = failure?.runs ?? const <int>[];
    final link = status.failedChecks
        .where((c) => c.hasLog)
        .map((c) => c.url)
        .whereType<String>()
        .firstOrNull;
    final fix = Tooltip(
      message: reason ?? '',
      child: SmallButton(
        key: const ValueKey('ci-fix'),
        label: inFlight ? 'Corrigindo CI…' : 'Corrigir CI',
        icon: Icons.edit_outlined,
        color: flaky ? AppColors.text : AppColors.onAmber,
        background: flaky ? AppColors.panel : AppColors.amber,
        border: flaky ? AppColors.border : AppColors.amber,
        onTap: _busy || inFlight || failure == null || reason != null
            ? null
            : () => _do(() async {
                await confirmAndFixCi(context, ref, _id);
              }),
      ),
    );
    final rerun = SmallButton(
      key: const ValueKey('ci-rerun'),
      label: 'Rodar de novo',
      icon: Icons.refresh,
      color: flaky ? AppColors.onAmber : AppColors.text,
      background: flaky ? AppColors.amber : AppColors.panel,
      border: flaky ? AppColors.amber : AppColors.border,
      onTap: _busy || inFlight || runs.isEmpty
          ? null
          : () => _do(() => fixer.rerun(_id)),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        const Icon(Icons.cancel, size: 18, color: AppColors.red),
        Text(
          'CI falhou no commit ${shortSha(status.headSha)}',
          key: const ValueKey('ci-title'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        if (runs.isNotEmpty)
          Text(
            runs.map((r) => 'run $r').join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        if (link != null)
          SmallButton(
            key: const ValueKey('ci-open-github'),
            label: 'Abrir no GitHub',
            onTap: () => openExternal(ref, link),
          ),
        // R8: with an intermittent failure "Rodar de novo" is the main one.
        rerun,
        fix,
      ],
    );
  }

  Widget _phase(CiFixState st) {
    final fixer = ref.read(ciFixerProvider.notifier);
    final (text, color, action) = switch (st.phase) {
      CiFixPhase.queued => (
        'Na fila: a sessão está ocupada. A correção sai quando o turno acabar.',
        AppColors.amber,
        ('Cancelar', () => fixer.cancel(_id)),
      ),
      CiFixPhase.fixing => (
        'Corrigindo CI · rodada CI${st.round} · o agente recebeu o log de '
            '${st.checks} ${st.checks == 1 ? 'check' : 'checks'}.',
        AppColors.amber,
        null,
      ),
      CiFixPhase.running => (
        'Push feito pelo app · CI rodando · ${shortSha(st.pushedSha ?? '')}',
        AppColors.blue,
        null,
      ),
      CiFixPhase.rerunning => (
        'Rodando de novo · tentativa ${st.attempt}',
        AppColors.blue,
        null,
      ),
      CiFixPhase.fixed => (
        'CI corrigido · ${st.round} ${st.round == 1 ? 'rodada' : 'rodadas'}',
        AppColors.teal,
        null,
      ),
      CiFixPhase.stopped => (
        'Correção automática parada. O CI continua vermelho depois da '
            'correção automática (CI${st.round}). O app não tenta de novo '
            'sozinho. A correção automática volta quando o CI ficar verde ou '
            'quando você usar "Corrigir CI" ou "Rodar de novo".',
        AppColors.amber,
        null,
      ),
      CiFixPhase.noCommit => (
        'O agente terminou sem commit.'
            '${st.detail == null ? '' : '\n${st.detail}'}',
        AppColors.red,
        ('Fechar', () async => fixer.dismiss(_id)),
      ),
      CiFixPhase.external => (
        'Falha externa, segundo o agente: ${st.detail ?? ''}',
        AppColors.amber,
        ('Rodar de novo', () => fixer.rerun(_id)),
      ),
      CiFixPhase.pushRefused => (
        'O push foi recusado: ${st.detail ?? ''}',
        AppColors.red,
        ('Tentar de novo', () => fixer.retryPush(_id)),
      ),
      CiFixPhase.local => (
        'O commit da correção ficou local. Use Copiar patch para mandar ao '
            'autor.',
        AppColors.amber,
        ('Fechar', () async => fixer.dismiss(_id)),
      ),
    };
    return Container(
      key: ValueKey('ci-phase-${st.phase.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            SmallButton(
              key: ValueKey('ci-phase-action-${st.phase.name}'),
              label: action.$1,
              onTap: _busy ? null : () => _do(action.$2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(PrCheck c, CiFailure? failure) {
    final open = _open.contains(c.name);
    final ex = failure?.excerptOf(c);
    final mono = const TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    final title = Row(
      children: [
        const Icon(Icons.cancel, size: 16, color: AppColors.red),
        const SizedBox(width: 8),
        Text(c.name, style: mono.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            !c.hasLog
                ? 'sem log disponível · não vai para o agente'
                : [
                    if (c.workflow.isNotEmpty) c.workflow,
                    if (ex != null && ex.step.isNotEmpty) 'passo "${ex.step}"',
                    if (!open && ex?.firstError != null) ex!.firstError!.trim(),
                  ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (ex != null && ex.alsoIn.isNotEmpty && ex.job == c.name)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              'mesmo erro em ${ex.alsoIn.join(', ')}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        if (!c.hasLog && c.url != null)
          SmallButton(
            key: ValueKey('ci-open-check-${c.name}'),
            label: 'Abrir check',
            onTap: () => openExternal(ref, c.url!),
          ),
        if (c.hasLog && ex != null)
          Icon(
            open ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: AppColors.textSecondary,
          ),
      ],
    );
    return Container(
      key: ValueKey('ci-check-${c.name}'),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: ex == null
                ? null
                : () => setState(
                    () => open ? _open.remove(c.name) : _open.add(c.name),
                  ),
            child: Padding(padding: const EdgeInsets.all(8), child: title),
          ),
          if (open && ex != null)
            Container(
              key: ValueKey('ci-excerpt-${c.name}'),
              padding: const EdgeInsets.all(10),
              color: SessionColors.terminalPanel,
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    for (final l in ex.lines)
                      TextSpan(
                        text: '$l\n',
                        style: mono.copyWith(
                          color: isCiCutLine(l)
                              ? AppColors.textMuted
                              : ciErrorLine.hasMatch(l)
                              ? AppColors.red
                              : AppColors.text,
                          fontStyle: isCiCutLine(l) ? FontStyle.italic : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _passed(PrStatus status) {
    final ok = [
      for (final c in status.checks)
        if (!c.failed && !c.running) c.name,
    ];
    final running = [
      for (final c in status.checks)
        if (c.running) c.name,
    ];
    if (ok.isEmpty && running.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        [
          if (ok.isNotEmpty)
            '${ok.length} ${ok.length == 1 ? 'check passou' : 'checks passaram'}: ${ok.join(', ')}',
          if (running.isNotEmpty)
            '${running.length} rodando: ${running.join(', ')}',
        ].join(' · '),
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Toast of a "Corrigir CI" started from the card.
void showCiToast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showAppToast(SnackBar(content: Text(text)));
