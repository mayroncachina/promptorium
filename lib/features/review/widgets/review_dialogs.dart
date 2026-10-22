import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../review_logic.dart';

/// Frame shared by the Review dialogs (same look as "Nova spec").
class ReviewDialogFrame extends StatelessWidget {
  const ReviewDialogFrame({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.width = 520,
  });

  final String title;
  final List<Widget> content;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Material(
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: content,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _body = TextStyle(fontSize: 13, color: AppColors.textSecondary);

/// "Pedir ajustes ao agente": preview of the message + optional note.
/// Returns the note (null = cancelled).
Future<String?> showAdjustDialog(
  BuildContext context,
  List<ReviewComment> comments,
) => showDialog<String>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _AdjustDialog(comments: comments),
);

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.comments});

  final List<ReviewComment> comments;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.comments.isNotEmpty || _note.text.trim().isNotEmpty;
    return ReviewDialogFrame(
      key: const ValueKey('review-adjust-dialog'),
      title: 'Pedir ajustes ao agente',
      width: 620,
      content: [
        Text(
          widget.comments.isEmpty
              ? 'Nenhum comentário inline. Descreva o ajuste abaixo '
                    '(ou clique no número de uma linha do diff para comentar).'
              : '${widget.comments.length} comentário(s) vão numa única '
                    'mensagem para a sessão; a tarefa volta para Em execução.',
          style: _body,
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('review-adjust-note'),
          controller: _note,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Observação geral (opcional)',
          ),
        ),
        const SizedBox(height: 12),
        const Text('Mensagem', style: sectionTitleStyle),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            adjustmentMessage(widget.comments, note: _note.text),
            key: const ValueKey('review-adjust-preview'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.text,
            ),
          ),
        ),
      ],
      actions: [
        SmallButton(
          label: 'Cancelar',
          onTap: () => Navigator.of(context).pop(),
        ),
        AmberButton(
          key: const ValueKey('review-adjust-send'),
          label: 'Enviar para a sessão',
          onTap: canSend ? () => Navigator.of(context).pop(_note.text) : null,
        ),
      ],
    );
  }
}

/// "Fazer merge" confirmation. Returns `deleteBranch` (null = cancelled).
Future<bool?> showMergeDialog(
  BuildContext context, {
  required String branch,
  required String base,
  required int uncommitted,
}) => showDialog<bool>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) =>
      _MergeDialog(branch: branch, base: base, uncommitted: uncommitted),
);

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({
    required this.branch,
    required this.base,
    required this.uncommitted,
  });

  final String branch;
  final String base;
  final int uncommitted;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  bool _deleteBranch = true;

  @override
  Widget build(BuildContext context) {
    final mono = _body.copyWith(fontFamily: AppFonts.mono, fontSize: 12);
    return ReviewDialogFrame(
      key: const ValueKey('review-merge-dialog'),
      title: 'Fazer merge',
      content: [
        Text.rich(
          TextSpan(
            style: _body,
            children: [
              const TextSpan(text: 'Integrar '),
              TextSpan(text: widget.branch, style: mono),
              const TextSpan(text: ' em '),
              TextSpan(text: widget.base, style: mono),
              const TextSpan(
                text: ' no repositório principal (merge --no-ff).',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (widget.uncommitted > 0)
              '• ${widget.uncommitted} alteração(ões) não commitada(s) no '
                  'worktree serão commitadas antes.',
            '• O agente da sessão é encerrado e o worktree é removido.',
            '• A tarefa vai para Feito.',
            '• Em conflito, o merge é desfeito (merge --abort) e nada muda.',
          ].join('\n'),
          style: _body,
        ),
        const SizedBox(height: 10),
        InkWell(
          key: const ValueKey('review-merge-delete-branch'),
          onTap: () => setState(() => _deleteBranch = !_deleteBranch),
          child: Row(
            children: [
              Checkbox(
                value: _deleteBranch,
                onChanged: (v) => setState(() => _deleteBranch = v ?? true),
              ),
              Flexible(
                child: Text(
                  'Apagar a branch ${widget.branch} depois do merge',
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ],
      actions: [
        SmallButton(
          label: 'Cancelar',
          onTap: () => Navigator.of(context).pop(),
        ),
        AmberButton(
          key: const ValueKey('review-merge-confirm'),
          label: 'Fazer merge',
          onTap: () => Navigator.of(context).pop(_deleteBranch),
        ),
      ],
    );
  }
}

/// Link of the PR just created (copy / open in the browser).
Future<void> showPrCreatedDialog(
  BuildContext context, {
  required String url,
  required VoidCallback onOpen,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (ctx) => ReviewDialogFrame(
    key: const ValueKey('review-pr-dialog'),
    title: 'Pull request criado',
    content: [
      SelectableText(
        url.isEmpty ? '(o gh não devolveu o link)' : url,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12,
          color: AppColors.amber,
        ),
      ),
    ],
    actions: [
      SmallButton(
        label: 'Copiar link',
        onTap: url.isEmpty
            ? null
            : () => Clipboard.setData(ClipboardData(text: url)),
      ),
      SmallButton(label: 'Abrir', onTap: url.isEmpty ? null : onOpen),
      AmberButton(label: 'Fechar', onTap: () => Navigator.of(ctx).pop()),
    ],
  ),
);

/// Error with a long, explanatory message (merge / PR failures).
Future<void> showReviewError(BuildContext context, String title, String msg) =>
    showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => ReviewDialogFrame(
        key: const ValueKey('review-error-dialog'),
        title: title,
        content: [
          SelectableText(
            msg,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
          ),
        ],
        actions: [
          AmberButton(label: 'OK', onTap: () => Navigator.of(ctx).pop()),
        ],
      ),
    );

/// "Mergear mesmo assim": criteria still unchecked; returns the reason
/// (null = cancelled).
Future<String?> showMergeOverrideDialog(
  BuildContext context,
  List<String> pending,
) => showDialog<String>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _OverrideDialog(pending: pending),
);

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.pending});

  final List<String> pending;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReviewDialogFrame(
    key: const ValueKey('review-override-dialog'),
    title: 'Critérios de aceite sem marcar',
    content: [
      Text([for (final p in widget.pending) '• $p'].join('\n'), style: _body),
      const SizedBox(height: 10),
      const Text(
        'Para mergear mesmo assim, diga o motivo (fica registrado na spec).',
        style: _body,
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('review-override-reason'),
        controller: _reason,
        autofocus: true,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'ex.: critério 3 vira spec própria',
        ),
        onChanged: (_) => setState(() {}),
      ),
    ],
    actions: [
      SmallButton(label: 'Cancelar', onTap: () => Navigator.of(context).pop()),
      AmberButton(
        key: const ValueKey('review-override-confirm'),
        label: 'Continuar',
        onTap: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_reason.text.trim()),
      ),
    ],
  );
}

/// "Marcar todos" the criteria (SPEC-018): [eligible] go to the batch,
/// [awaiting] (with a `verificar:` not confirmed yet) stay out. Enter
/// confirms, Esc cancels. Returns true when confirmed.
Future<bool> showBatchCriteriaDialog(
  BuildContext context, {
  required int eligible,
  required int awaiting,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              Navigator.of(ctx).pop(true),
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
              Navigator.of(ctx).pop(true),
        },
        child: Focus(
          autofocus: true,
          child: ReviewDialogFrame(
            key: const ValueKey('review-batch-dialog'),
            title:
                'Marcar $eligible ${eligible == 1 ? 'critério' : 'critérios'} '
                'como verificado${eligible == 1 ? '' : 's'} por você?',
            content: [
              Text(
                [
                  if (awaiting > 0)
                    '$awaiting ${awaiting == 1 ? 'fica' : 'ficam'} de fora: '
                        '${awaiting == 1 ? 'tem' : 'têm'} um comando '
                        'verificar: que a verificação ainda não confirmou '
                        '(dá para marcar um a um).',
                  'O que a verificação e o revisor já marcaram não muda, e '
                      'dá para desfazer logo depois.',
                ].join(' '),
                style: _body,
              ),
            ],
            actions: [
              SmallButton(
                key: const ValueKey('review-batch-cancel'),
                label: 'Cancelar',
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              AmberButton(
                key: const ValueKey('review-batch-confirm'),
                label: 'Marcar $eligible',
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;
