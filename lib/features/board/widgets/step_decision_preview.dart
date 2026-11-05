import 'package:flutter/material.dart';

import '../../../core/text/line_diff.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../board_rules.dart';
import '../step_decision.dart';
import 'spec_canvas.dart' show CanvasStepDot;

const _caption = TextStyle(fontSize: 12, color: AppColors.textSecondary);
const _body = TextStyle(fontSize: 13, height: 1.55, color: AppColors.text);

/// Ids that a split of [id] puts in the queue, in order (SPEC-033 R16): a
/// step that is already a sub-step goes on from its own number.
List<String> stepDecisionSplitIds(String id, int count) {
  final parent = parentOf(id);
  final first = isSubStep(id) ? int.parse(id.split('.').last) : 1;
  return [for (var i = 0; i < count; i++) '$parent.${first + i}'];
}

/// The proposed text of the requirement and the new criteria of `change`
/// (the lines `- [ ] …`).
({String text, List<String> criteria}) stepDecisionChange(String change) {
  final lines = change.split('\n').map((l) => l.trim());
  bool isCriterion(String line) => line.startsWith('- [');
  return (
    text: lines.where((l) => l.isNotEmpty && !isCriterion(l)).join(' '),
    criteria: lines.where(isCriterion).toList(),
  );
}

/// "Como a etapa fica" (SPEC-033 R7) for [option]; null is "Outra resposta",
/// with [answer] as the message to the agent.
class StepDecisionPreview extends StatelessWidget {
  const StepDecisionPreview(
    this.option, {
    super.key,
    required this.step,
    required this.steps,
    this.answer = '',
  });

  final StepDecisionOption? option;
  final StepView step;

  /// The queue of the card, as it is now.
  final List<StepView> steps;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final children = switch (o?.kind) {
      StepDecisionKind.amend => _amend(o!),
      StepDecisionKind.split => _split(o!),
      StepDecisionKind.defer => _defer(),
      StepDecisionKind.answer => _answer(o!.title),
      null => _answer(answer.trim()),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          child,
        ],
      ],
    );
  }

  String get _requirement => '${step.id} · ${step.text}';

  Widget _message(String text) => Text(
    'O agente retoma o ${step.id} com a mensagem: “$text”',
    key: const ValueKey('step-preview-message'),
    style: _caption,
  );

  List<Widget> _amend(StepDecisionOption o) {
    final change = stepDecisionChange(o.change);
    return [
      if (change.text.isEmpty)
        Text(_requirement, style: _body)
      else
        _AmendedRequirement(step: step, text: change.text),
      if (change.criteria.isNotEmpty) ...[
        Text(
          change.criteria.length == 1 ? 'Critério novo' : 'Critérios novos',
          style: _caption,
        ),
        _Added(
          child: Text(
            change.criteria.join('\n'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              height: 1.5,
              color: AppColors.bubble,
            ),
          ),
        ),
      ],
      const Text('Fila de etapas: não muda', style: _caption),
      _Queue(items: [for (final s in steps) (s.id, s.status, false)]),
      _message(o.title),
    ];
  }

  List<Widget> _split(StepDecisionOption o) {
    final ids = stepDecisionSplitIds(step.id, o.split.length);
    final parent = parentOf(step.id);
    return [
      const Text('Requisito: não muda', style: _caption),
      Text(_requirement, style: _body),
      const Text('Subetapas na fila', style: _caption),
      for (final (i, text) in o.split.indexed)
        _Added(
          child: Row(
            key: ValueKey('step-preview-sub-${ids[i]}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ids[i],
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.bubble,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.bubble,
                  ),
                ),
              ),
            ],
          ),
        ),
      _Queue(
        items: [
          for (final s in steps)
            if (s.id == step.id)
              for (final id in ids) (id, StepStatus.pending, true)
            else
              (s.id, s.status, false),
        ],
      ),
      Text(
        'Critérios do $parent verificados ao fim do ${ids.last}. '
        'O agente retoma pelo ${ids.first}.',
        key: const ValueKey('step-preview-split-note'),
        style: _caption,
      ),
    ];
  }

  List<Widget> _defer() => [
    const Text('Requisito: não muda', style: _caption),
    Text(_requirement, style: _body),
    Text('Fila de etapas: o ${step.id} vai para o fim', style: _caption),
    _Queue(
      items: [
        for (final s in steps)
          if (s.id != step.id) (s.id, s.status, false),
        (step.id, StepStatus.pending, true),
      ],
    ),
    const Text(
      'A etapa volta para “pendente” e roda depois das outras.',
      key: ValueKey('step-preview-defer-note'),
      style: _caption,
    ),
  ];

  List<Widget> _answer(String message) => [
    const Text('O agente vai receber', style: _caption),
    Text(
      message.isEmpty ? 'Escreva o que o agente deve fazer.' : '“$message”',
      key: const ValueKey('step-preview-answer'),
      style: message.isEmpty ? _caption : _body,
    ),
    const Text(
      'O requisito não muda',
      key: ValueKey('step-preview-unchanged'),
      style: _caption,
    ),
    const Text('Fila de etapas: não muda', style: _caption),
    _Queue(items: [for (final s in steps) (s.id, s.status, false)]),
  ];
}

/// The requirement with the swaps marked: what goes in is underlined and
/// what leaves is crossed out, so the mark does not depend on the colour.
class _AmendedRequirement extends StatelessWidget {
  const _AmendedRequirement({required this.step, required this.text});

  final StepView step;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = wordDiff(step.text, text);
    return Text.rich(
      TextSpan(
        style: _body,
        children: [
          TextSpan(text: '${step.id} · '),
          for (final t in tokens)
            TextSpan(
              text: t.text,
              style: switch (t.op) {
                DiffOp.same => null,
                DiffOp.add => const TextStyle(
                  color: AppColors.bubble,
                  backgroundColor: SessionColors.addBg,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.bubble,
                ),
                DiffOp.del => const TextStyle(
                  color: AppColors.red,
                  backgroundColor: SessionColors.delBg,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: AppColors.red,
                ),
              },
            ),
        ],
      ),
      key: const ValueKey('step-preview-amended'),
      semanticsLabel: 'Requisito alterado: ${step.id} · $text',
    );
  }
}

class _Added extends StatelessWidget {
  const _Added({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: SessionColors.addBg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
}

/// The queue of the card, drawn with the dots of the canvas: (id, status,
/// whether the option changes it).
class _Queue extends StatelessWidget {
  const _Queue({required this.items});

  final List<(String, StepStatus, bool)> items;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Fila de etapas: ${items.map((i) => i.$1).join(', ')}',
    child: ExcludeSemantics(
      child: Container(
        key: const ValueKey('step-preview-queue'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final (id, status, changed) in items)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 14,
                    child: Center(
                      child: CanvasStepDot(status: status, animate: false),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    id,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: changed
                          ? AppColors.bubble
                          : status == StepStatus.needsInput
                          ? AppColors.amber
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
