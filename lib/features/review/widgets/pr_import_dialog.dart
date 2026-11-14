import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/git_service.dart' show gitServiceFactoryProvider;
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../project/project_config.dart';
import '../../sessions/widgets/session_style.dart';
import '../pr_import.dart';
import '../review_service.dart';

/// "Trazer PR…" (SPEC-050 R1, R4): the open PRs of the workspace, a search
/// that also takes `#n` or the URL, and, for the PR chosen, how to start.
/// With [number], the dialog opens on that PR (the Grafo's "Trazer para o
/// app", R2). Returns the new session id (null = cancelled or opened in the
/// Review).
Future<String?> showPrImportDialog(
  BuildContext context, {
  required Workspace workspace,
  int? number,
}) => showAppDialog<String>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => PrImportDialog(workspace: workspace, number: number),
);

/// `há 2 h` / `ontem` / `há 3 dias` of a PR's last update.
String prAge(DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays == 1) return 'ontem';
  if (d.inDays < 30) return 'há ${d.inDays} dias';
  final months = d.inDays ~/ 30;
  return months == 1 ? 'há 1 mês' : 'há $months meses';
}

/// `@lucas-andrade · fork · feat/x → main · há 2 h`.
String prMetaLine(GhOpenPr pr, DateTime now) => [
  '@${pr.author}',
  if (pr.isCrossRepository) 'fork',
  '${pr.headRefName} → ${pr.baseRefName}',
  if (pr.updatedAt != null) prAge(pr.updatedAt, now),
].join(' · ');

class PrImportDialog extends ConsumerStatefulWidget {
  const PrImportDialog({super.key, required this.workspace, this.number});

  final Workspace workspace;
  final int? number;

  @override
  ConsumerState<PrImportDialog> createState() => _PrImportDialogState();
}

class _PrImportDialogState extends ConsumerState<PrImportDialog> {
  final _search = TextEditingController();
  final _request = TextEditingController();
  List<PrImportCandidate>? _list;
  String? _error;
  String? _repository;
  PrImportCandidate? _chosen;
  PrImportCandidate? _found;
  bool _resolving = false;
  bool _bringing = false;
  PrStart _start = PrStart.resumir;
  late bool _reply;
  int? _comments;

  PrImportService get _service => ref.read(prImportServiceProvider);

  @override
  void initState() {
    super.initState();
    _reply =
        ref.read(appSettingsProvider)[replyInPrKey(widget.workspace.id)] == '1';
    _search.addListener(_onSearch);
    _request.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    _request.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await _service.availability(widget.workspace);
      _repository = a.repository;
      final list = await _service.candidates(widget.workspace);
      if (!mounted) return;
      setState(() => _list = list);
      final n = widget.number;
      if (n != null) {
        final c =
            list.where((c) => c.number == n).firstOrNull ??
            await _service.resolve(widget.workspace, '$n');
        if (mounted && c != null && !c.alreadyIn) _choose(c);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// A `#n` or URL not in the list is looked up on the host.
  void _onSearch() {
    setState(() => _found = null);
    final text = _search.text;
    int? n;
    try {
      n = parsePrReference(text, repository: _repository);
    } on PrImportException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (_error != null && _list != null) setState(() => _error = null);
    if (n == null || (_list ?? []).any((c) => c.number == n)) return;
    setState(() => _resolving = true);
    final asked = text;
    unawaited(
      _service
          .resolve(widget.workspace, text)
          .then((c) {
            if (!mounted || _search.text != asked) return;
            setState(() {
              _found = c;
              _resolving = false;
            });
          })
          .catchError((Object e) {
            if (!mounted || _search.text != asked) return;
            setState(() {
              _error = '$e';
              _resolving = false;
            });
          }),
    );
  }

  void _choose(PrImportCandidate c) {
    setState(() {
      _chosen = c;
      _comments = null;
    });
    unawaited(
      _service.openComments(widget.workspace, c.number).then((list) {
        if (mounted && _chosen == c) setState(() => _comments = list.length);
      }),
    );
  }

  void _openInReview(PrImportCandidate c) {
    ref.read(selectedReviewProvider.notifier).select(c.sessionId!);
    ref.read(navigationProvider.notifier).request(AppSection.review);
    Navigator.of(context).pop();
  }

  Future<void> _bring() async {
    final c = _chosen;
    if (c == null) return;
    setState(() {
      _bringing = true;
      _error = null;
    });
    try {
      final id = await _service.bring(
        widget.workspace,
        c,
        start: _start,
        request: _request.text,
        replyInPr: _reply,
      );
      if (!mounted) return;
      ref.invalidate(reviewQueueProvider(widget.workspace.id));
      ref.read(selectedReviewProvider.notifier).select(id);
      Navigator.of(context).pop(id);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _bringing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.4),
    child: Material(
      key: const ValueKey('pr-import-dialog'),
      color: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: _chosen == null ? _listView() : _startView(_chosen!),
      ),
    ),
  );

  // --- step 1: the list (R1) -------------------------------------------------

  Widget _listView() {
    final list = _list;
    final shown = [
      ?_found,
      for (final c in list ?? const <PrImportCandidate>[])
        if (prMatches(c.pr, _search.text) ||
            parsePrReferenceOrNull(_search.text) == c.number)
          c,
    ];
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Trazer PR', style: _titleStyle),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'PRs abertos de '),
                    TextSpan(
                      text: _repository ?? widget.workspace.name,
                      style: const TextStyle(fontFamily: AppFonts.mono),
                    ),
                    const TextSpan(
                      text:
                          ' · o app faz o checkout num worktree próprio e '
                          'abre uma sessão do agente.',
                    ),
                  ],
                ),
                style: _bodyStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pr-import-search'),
                controller: _search,
                autofocus: true,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText:
                      'Buscar por título, autor, número ou colar a URL do PR',
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              _error!,
              key: const ValueKey('pr-import-error'),
              style: const TextStyle(fontSize: 12, color: AppColors.red),
            ),
          ),
        Flexible(
          child: list == null && _error == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Lendo os PRs abertos…', style: _bodyStyle),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    if (_resolving)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Buscando o PR…', style: _bodyStyle),
                      ),
                    if (shown.isEmpty && !_resolving && list != null)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Nenhum PR aberto com essa busca.',
                          style: _bodyStyle,
                        ),
                      ),
                    for (final c in shown) _row(c, now),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${list?.length ?? 0} abertos · a busca também aceita o '
                  'número ou a URL de um PR fora da lista',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              SmallButton(
                key: const ValueKey('pr-import-cancel'),
                label: 'Cancelar',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(PrImportCandidate c, DateTime now) {
    final pr = c.pr;
    final ciColor = switch (pr.ci) {
      CiState.passed => AppColors.teal,
      CiState.failed => AppColors.red,
      CiState.running => AppColors.amber,
      CiState.none => AppColors.textSecondary,
    };
    return Padding(
      key: ValueKey('pr-import-row-${c.number}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '#${c.number}',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        pr.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      if (pr.isDraft) const _Pill('Rascunho'),
                      if (c.alreadyIn)
                        const _Pill(
                          'Já no app',
                          color: AppColors.teal,
                          key: ValueKey('pr-import-already'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    prMetaLine(pr, now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              c.checksLabel,
              key: ValueKey('pr-import-checks-${c.number}'),
              style: TextStyle(fontSize: 12, color: ciColor),
            ),
            const SizedBox(width: 12),
            c.alreadyIn
                ? SmallButton(
                    key: ValueKey('pr-import-open-${c.number}'),
                    label: 'Abrir no Review',
                    onTap: () => _openInReview(c),
                  )
                : SmallButton(
                    key: ValueKey('pr-import-pick-${c.number}'),
                    label: 'Trazer',
                    onTap: () => _choose(c),
                  ),
          ],
        ),
      ),
    );
  }

  // --- step 2: how to start (R3, R4, R7, R8) ---------------------------------

  Widget _startView(PrImportCandidate c) {
    final pr = c.pr;
    final config = ProjectConfig.loadSync(widget.workspace.path);
    final wc = config.worktree;
    final base = ref.read(gitServiceFactoryProvider)(widget.workspace.path);
    final prepare = [
      if (wc.copy.isNotEmpty) 'copiar ${wc.copy.join(', ')}',
      ?wc.prepare,
    ].join(' · ');
    final canBring =
        !_bringing &&
        (_start != PrStart.pedido || _request.text.trim().isNotEmpty);
    Widget info(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: _bodyStyle)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const ValueKey('pr-import-start'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  [
                    'PR #${pr.number}',
                    '@${pr.author}',
                    if (pr.isCrossRepository)
                      'fork ${pr.headOwner}/${_repository?.split('/').last ?? ''}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(pr.title, style: _titleStyle),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      info('Branch local', c.localBranch),
                      info('Base', pr.baseRefName),
                      info(
                        'Worktree',
                        '${base.worktreesBase}/${base.repoName}-pr-${pr.number}',
                      ),
                      if (prepare.isNotEmpty) info('Preparar', prepare),
                    ],
                  ),
                ),
                if (!c.canPush) ...[
                  const SizedBox(height: 12),
                  Container(
                    key: const ValueKey('pr-import-no-push'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.amberTint,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SessionColors.approvalBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: AppColors.amber,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sem permissão de escrita na branch do PR',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(noPushReason(c), style: _bodyStyle),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Como começar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                for (final s in PrStart.values) _choice(s),
                if (_start == PrStart.pedido) ...[
                  const SizedBox(height: 4),
                  TextField(
                    key: const ValueKey('pr-import-request'),
                    controller: _request,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 13, color: AppColors.text),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'O que o agente deve fazer neste PR',
                    ),
                  ),
                ],
                if (_start == PrStart.comentarios && c.canPush) ...[
                  const SizedBox(height: 4),
                  _ReplyToggle(
                    value: _reply,
                    onChanged: (v) => setState(() => _reply = v),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'A primeira mensagem leva título, descrição, base, '
                  'git diff --stat, comentários abertos e os checks que '
                  'falharam. Push forçado fica bloqueado nesta sessão.',
                  style: _bodyStyle.copyWith(fontSize: 12),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const ValueKey('pr-import-error'),
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SmallButton(
                key: const ValueKey('pr-import-back'),
                label: 'Voltar',
                onTap: _bringing
                    ? null
                    : () => setState(() {
                        _chosen = null;
                        _error = null;
                      }),
              ),
              const SizedBox(width: 8),
              AmberButton(
                key: const ValueKey('pr-import-bring'),
                label: _bringing ? 'Trazendo…' : 'Trazer e começar',
                onTap: canBring ? () => unawaited(_bring()) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _choice(PrStart s) {
    final selected = _start == s;
    final description = switch (s) {
      PrStart.resumir =>
        'O agente lê o PR em modo plano, sem editar nada, e responde com o '
            'que muda, os riscos e as perguntas em aberto.',
      PrStart.comentarios =>
        'Envia os comentários do PR com arquivo e linha e pede as correções.',
      PrStart.pedido => 'Você escreve o que o agente deve fazer.',
    };
    final label = s == PrStart.comentarios && _comments != null
        ? '${s.label} · $_comments ${_comments == 1 ? 'aberto' : 'abertos'}'
        : s.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.amberTint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.amber : AppColors.border,
          ),
        ),
        child: InkWell(
          key: ValueKey('pr-import-start-${s.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _start = s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? AppColors.amber : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(description, style: _bodyStyle),
                    ],
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

/// Why the agent's commits stay local (R7).
String noPushReason(PrImportCandidate c) {
  final pr = c.pr;
  if (pr.isCrossRepository && !pr.maintainerCanModify) {
    return 'O fork de @${pr.author} não permite edições de mantenedores. Os '
        'commits do agente ficam locais, e o Review oferece "Copiar patch" '
        'para você mandar à autora.';
  }
  return 'A sua conta não tem permissão de escrita neste repositório. Os '
      'commits do agente ficam locais, e o Review oferece "Copiar patch".';
}

/// `#212` / URL → 212, null for anything else (no exception).
int? parsePrReferenceOrNull(String text) {
  try {
    return parsePrReference(text);
  } on PrImportException {
    return null;
  }
}

/// "Responder no PR depois do push, com o SHA que corrigiu" (R8, P3).
class _ReplyToggle extends StatelessWidget {
  const _ReplyToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const ValueKey('pr-import-reply'),
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: value ? AppColors.amber : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Responder no PR depois do push, com o SHA que corrigiu',
              style: TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {super.key, this.color = AppColors.textSecondary});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}

const _titleStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  color: AppColors.text,
);

const _bodyStyle = TextStyle(fontSize: 13, color: AppColors.textSecondary);

/// "Trazer PR…" on top of the Review's queue (R1); off with the reason on
/// GitLab or without a GitHub remote (R10).
class PrImportButton extends ConsumerWidget {
  const PrImportButton({super.key, required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(prImportAvailabilityProvider(workspace));
    final reason = a.value?.reason;
    final enabled = a.value?.available ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: reason ?? 'Trazer um PR aberto do repositório para o app',
          child: SmallButton(
            key: const ValueKey('review-bring-pr'),
            label: 'Trazer PR…',
            icon: Icons.add,
            height: 34,
            expand: true,
            semanticLabel: reason == null
                ? 'Trazer PR'
                : 'Trazer PR, indisponível: $reason',
            onTap: enabled
                ? () => unawaited(
                    showPrImportDialog(context, workspace: workspace),
                  )
                : null,
          ),
        ),
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              reason,
              key: const ValueKey('review-bring-pr-reason'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}
