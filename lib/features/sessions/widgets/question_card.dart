import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import 'session_style.dart';

/// One question of the `AskUserQuestion` tool.
class AskQuestion {
  const AskQuestion({
    required this.question,
    required this.options,
    this.header,
    this.multiSelect = false,
  });

  final String question;
  final String? header;
  final bool multiSelect;
  final List<({String label, String? description})> options;
}

/// Questions of an `AskUserQuestion` request input (null = not a question or
/// malformed, so the generic approval card is used).
List<AskQuestion>? parseAskQuestions(Map<String, dynamic> input) {
  final raw = input['questions'];
  if (raw is! List || raw.isEmpty) return null;
  final out = <AskQuestion>[];
  for (final q in raw) {
    if (q is! Map) return null;
    final text = '${q['question'] ?? ''}'.trim();
    final opts = q['options'];
    if (text.isEmpty || opts is! List) return null;
    out.add(
      AskQuestion(
        question: text,
        header: q['header'] == null ? null : '${q['header']}',
        multiSelect: q['multiSelect'] == true,
        options: [
          for (final o in opts)
            if (o is Map && '${o['label'] ?? ''}'.trim().isNotEmpty)
              (
                label: '${o['label']}'.trim(),
                description: o['description'] == null
                    ? null
                    : '${o['description']}'.trim(),
              ),
        ],
      ),
    );
  }
  return out;
}

/// `updatedInput` that answers the tool: the original input plus
/// `answers` (question text → chosen label; several choices are joined by
/// ", "; free text for "Outro").
Map<String, dynamic> askAnswerInput(
  Map<String, dynamic> input,
  Map<String, String> answers,
) => {...input, 'answers': answers};

/// Choices of an `AskUserQuestion`: one block per question (single or
/// multiple choice, plus "Outro" with free text) and "Enviar respostas".
class QuestionCard extends StatefulWidget {
  const QuestionCard({
    super.key,
    required this.questions,
    required this.onSubmit,
    required this.onDecline,
    this.busy = false,
  });

  final List<AskQuestion> questions;
  final void Function(Map<String, String> answers) onSubmit;
  final VoidCallback onDecline;
  final bool busy;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  /// Selected option indexes by question; [_other] = the "Outro" choice.
  late final List<Set<int>> _picked = [for (final _ in widget.questions) {}];
  late final List<bool> _other = [for (final _ in widget.questions) false];
  late final List<TextEditingController> _text = [
    for (final _ in widget.questions) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final c in _text) {
      c.dispose();
    }
    super.dispose();
  }

  /// The answer of question [i] (null = not answered yet).
  String? _answer(int i) {
    final q = widget.questions[i];
    final parts = [
      for (final n in _picked[i].toList()..sort()) q.options[n].label,
      if (_other[i] && _text[i].text.trim().isNotEmpty) _text[i].text.trim(),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  bool get _complete =>
      List.generate(widget.questions.length, _answer).every((a) => a != null);

  void _toggle(int qi, int oi) {
    final q = widget.questions[qi];
    setState(() {
      if (q.multiSelect) {
        _picked[qi].contains(oi) ? _picked[qi].remove(oi) : _picked[qi].add(oi);
      } else {
        _picked[qi]
          ..clear()
          ..add(oi);
        _other[qi] = false;
      }
    });
  }

  void _toggleOther(int qi) {
    final q = widget.questions[qi];
    setState(() {
      if (q.multiSelect) {
        _other[qi] = !_other[qi];
      } else {
        _picked[qi].clear();
        _other[qi] = true;
      }
    });
  }

  void _submit() {
    widget.onSubmit({
      for (var i = 0; i < widget.questions.length; i++)
        widget.questions[i].question: _answer(i)!,
    });
  }

  Widget _choice({
    required Key key,
    required bool selected,
    required bool multi,
    required String label,
    String? description,
    required VoidCallback onTap,
  }) => InkWell(
    key: key,
    onTap: widget.busy ? null : onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.amberTint : AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppColors.amber : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            multi
                ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                : (selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
            size: 16,
            color: selected ? AppColors.amber : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                if (description != null && description.isNotEmpty)
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('question-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var qi = 0; qi < widget.questions.length; qi++) ...[
                  if (qi > 0) const SizedBox(height: 10),
                  if (widget.questions[qi].header != null)
                    Text(
                      widget.questions[qi].header!.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Text(
                      widget.questions[qi].question,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  if (widget.questions[qi].multiSelect)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Pode marcar mais de uma',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  for (
                    var oi = 0;
                    oi < widget.questions[qi].options.length;
                    oi++
                  )
                    _choice(
                      key: ValueKey('question-$qi-option-$oi'),
                      selected: _picked[qi].contains(oi),
                      multi: widget.questions[qi].multiSelect,
                      label: widget.questions[qi].options[oi].label,
                      description: widget.questions[qi].options[oi].description,
                      onTap: () => _toggle(qi, oi),
                    ),
                  _choice(
                    key: ValueKey('question-$qi-other'),
                    selected: _other[qi],
                    multi: widget.questions[qi].multiSelect,
                    label: 'Outro…',
                    onTap: () => _toggleOther(qi),
                  ),
                  if (_other[qi])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TextField(
                        key: ValueKey('question-$qi-other-text'),
                        controller: _text[qi],
                        autofocus: true,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Escreva a sua resposta',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SmallButton(
                key: const ValueKey('question-decline'),
                label: 'Recusar',
                expand: true,
                onTap: widget.busy ? null : widget.onDecline,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AmberButton(
                key: const ValueKey('question-submit'),
                label: 'Enviar respostas',
                expand: true,
                onTap: widget.busy || !_complete ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
