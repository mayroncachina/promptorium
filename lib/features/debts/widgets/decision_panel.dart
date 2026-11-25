import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../debt_actions.dart';
import '../debt_board.dart';
import '../debt_detector.dart';
import '../debt_interview.dart';
import '../debt_item.dart';
import '../debt_table.dart';
import 'debts_screen.dart' show selectedDecisionProvider;

/// The detail of a decision on the "Decisões" tab (R12, R13): a pending
/// one is answered here ("Salvar decisão"); a decided one offers "Virar
/// débito" until it generated one.
class DecisionPanel extends ConsumerStatefulWidget {
  const DecisionPanel({
    super.key,
    required this.row,
    required this.board,
    required this.workspaceId,
  });

  final DecisionRowView row;
  final DebtBoard board;
  final int workspaceId;

  @override
  ConsumerState<DecisionPanel> createState() => _DecisionPanelState();
}

class _DecisionPanelState extends ConsumerState<DecisionPanel> {
  final _answer = TextEditingController();
  bool _toSpec = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _answer.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(DecisionPanel old) {
    super.didUpdateWidget(old);
    if (old.row.item.code != widget.row.item.code) _answer.clear();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  String get _repoRoot => widget.board.snapshot.repoRoot;

  /// Where the row is: the worktree of the spec it is in, or the main
  /// checkout (R18).
  String? get _rowRoot {
    final wt = widget.row.inSpec?.worktreePath;
    return wt != null && Directory(wt).existsSync() ? wt : null;
  }

  /// "spec 33": the spec the decision came from (the link, else "Spec N"
  /// of "Origem"); null when it has none.
  String? get _originLabel {
    if (widget.row.originSpec case final s?) return specLabel(s);
    final n = widget.row.item.originSpecNumber;
    return n == null ? null : 'spec $n';
  }

  Future<void> _save() async {
    final d = widget.row.item;
    final answer = _answer.text.trim();
    if (answer.isEmpty || _saving) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    // The panel stays on this decision after it leaves "Pendentes".
    ref.read(selectedDecisionProvider.notifier).select(d.code);
    try {
      final r = await ref
          .read(debtInterviewProvider)
          .answerDecision(
            _repoRoot,
            d,
            answer,
            root: _rowRoot,
            toSpec: _toSpec && _originLabel != null,
            spec: widget.row.originSpec,
          );
      messenger?.showAppToast(
        SnackBar(
          content: Text(
            r.annotated
                ? '${d.code} decidida; a resposta foi para a '
                      '$_originLabel.'
                : '${d.code} decidida.',
          ),
        ),
      );
      if (mounted) _answer.clear();
    } on DebtRowChanged {
      messenger?.showAppToast(
        const SnackBar(
          content: Text(
            'A linha mudou no arquivo desde a leitura. Confira e tente de '
            'novo.',
          ),
        ),
      );
    } catch (e) {
      messenger?.showAppToast(
        SnackBar(content: Text('Não deu para gravar a decisão: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "Virar débito" (R12): the form with the origin "DP-04"; saving writes
  /// "(…, DP-04)" in the debt and "gerou o DT-10" in the decision.
  Future<void> _toDebt() async {
    final d = widget.row.item;
    final interview = ref.read(debtInterviewProvider);
    final root = _rowRoot;
    final leftover = _leftover(d.decision);
    await openDebtForm(
      context,
      ref,
      repoRoot: _repoRoot,
      writeRoot: root,
      initial: DebtInterview.debtDraftFromDecision(d, leftover: leftover),
      link: DebtInterview.linkOfDecision(d.code),
      write: (draft) => interview.debtFromDecision(
        _repoRoot,
        d.code,
        draft,
        writeRoot: root,
        decisionRoot: root,
      ),
    );
  }

  /// The part of the answer that stays for later ("Comprimir no servidor
  /// fica para depois"), when a sentence of it says so.
  static String? _leftover(String decision) {
    final plain = decision
        .replaceAll(RegExp(r'\*\*Decidido \([^)]*\):\*\*'), '')
        .replaceAll('**', '')
        .trim();
    for (final s in plain.split(RegExp(r'(?<=[.;])\s+'))) {
      if (detectDebtIntent(s) == DebtIntent.debt) {
        return s.replaceAll(RegExp(r'[.;]\s*$'), '').trim();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final d = row.item;
    final answer = _answer.text.trim();
    final generated = RegExp(r'gerou o DT-\d+').hasMatch(d.decision);
    return SingleChildScrollView(
      key: ValueKey('decision-panel-${d.code}'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                d.code,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 13,
                  color: AppColors.amber,
                ),
              ),
              Text(
                '· desde ${d.since} · origem',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              DebtTag(row.origin),
              if (row.originSpec case final o?) DebtTag(o.title),
              if (row.inSpec != null)
                DebtTag('na ${specLabel(row.inSpec!)}', color: AppColors.lilac),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            d.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (d.question != '**${d.title}**' && d.question != d.title) ...[
            const SizedBox(height: 6),
            Text(
              d.question.replaceAll('**', ''),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          DebtBox(label: 'RECOMENDAÇÃO', text: d.recommendation),
          if (d.decided) ...[
            const SizedBox(height: 12),
            DebtBox(
              label: 'DECISÃO',
              text: d.decision.replaceAll('**', ''),
              key: const ValueKey('decision-decided-text'),
            ),
            if (!generated) ...[
              const SizedBox(height: 14),
              _ToDebtOffer(
                code: d.code,
                leftover: _leftover(d.decision),
                onTap: _toDebt,
              ),
            ],
          ] else
            ..._answerForm(d, answer),
        ],
      ),
    );
  }

  List<Widget> _answerForm(DecisionItem d, String answer) {
    final origin = _originLabel;
    final canSpec = origin != null && d.originQuestion != null;
    final service = ref.read(debtInterviewProvider);
    final line = DebtTable.formatRow(
      service.decidedCells(d, answer.isEmpty ? '…' : answer),
    );
    return [
      const SizedBox(height: 14),
      const _Label('DECISÃO'),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('decision-answer'),
        controller: _answer,
        minLines: 2,
        maxLines: 6,
        style: const TextStyle(fontSize: 13, height: 1.45),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'O que foi decidido…',
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(),
        ),
      ),
      if (canSpec) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                key: const ValueKey('decision-to-spec'),
                value: _toSpec,
                onChanged: (v) => setState(() => _toSpec = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Levar a resposta para a $origin',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                DebtInterview.specPreview(d, _short(answer)),
                key: const ValueKey('decision-spec-preview'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 14),
      const _Label('LINHA QUE O APP GRAVA'),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSolid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          line,
          key: const ValueKey('decision-line'),
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11.5),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SmallButton(
            key: const ValueKey('decision-cancel'),
            label: 'Cancelar',
            height: 34,
            fontSize: 13,
            onTap: answer.isEmpty || _saving ? null : _answer.clear,
          ),
          const SizedBox(width: 8),
          AmberButton(
            key: const ValueKey('decision-save'),
            label: 'Salvar decisão',
            height: 34,
            fontSize: 13,
            busy: _saving,
            onTap: answer.isEmpty ? null : _save,
          ),
        ],
      ),
    ];
  }

  static String _short(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return '…';
    return t.length > 40 ? '${t.substring(0, 39)}…' : t;
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10.5,
      letterSpacing: .8,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    ),
  );
}

/// The green strip "A resposta deixa algo para depois" with "Virar débito"
/// (R12).
class _ToDebtOffer extends StatelessWidget {
  const _ToDebtOffer({required this.code, required this.onTap, this.leftover});

  final String code;
  final String? leftover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('decision-to-debt-offer'),
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    decoration: BoxDecoration(
      color: AppColors.teal.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.teal.withValues(alpha: .4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.check, size: 16, color: AppColors.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            leftover == null
                ? TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Algo ficou provisório? ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: 'Registre um débito ligado à $code.'),
                    ],
                  )
                : TextSpan(
                    children: [
                      const TextSpan(
                        text: 'A resposta deixa algo para depois. ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text:
                            '“$leftover” pode virar um débito ligado à '
                            '$code.',
                      ),
                    ],
                  ),
            style: const TextStyle(fontSize: 12.5, color: AppColors.text),
          ),
        ),
        const SizedBox(width: 8),
        SmallButton(
          key: const ValueKey('decision-to-debt'),
          label: 'Virar débito',
          color: AppColors.teal,
          border: AppColors.teal.withValues(alpha: .55),
          background: AppColors.teal.withValues(alpha: .06),
          onTap: onTap,
        ),
      ],
    ),
  );
}

/// A labelled box (RECOMENDAÇÃO, DECISÃO).
class DebtBox extends StatelessWidget {
  const DebtBox({super.key, required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            letterSpacing: .8,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text.isEmpty ? '—' : text,
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      ],
    ),
  );
}

/// A small outlined tag (origin, state).
class DebtTag extends StatelessWidget {
  const DebtTag(this.text, {super.key, this.color, this.filled = false});

  final String text;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: .12) : null,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color == null
              ? AppColors.borderHover
              : c.withValues(alpha: .6),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: c),
      ),
    );
  }
}
