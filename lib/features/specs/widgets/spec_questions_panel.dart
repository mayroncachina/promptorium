import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/line_diff.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_pressable.dart';
import '../../../ui/widgets/diff_view.dart';
import '../spec_answers.dart';
import '../spec_file.dart';
import '../../board/widgets/step_decision_parts.dart' show StepKbd;
import 'spec_questions_focus.dart';
import '../../../ui/theme/ambient.dart';

/// Before / after of "Aplicar respostas" (SPEC-028 R10), shown as a diff.
typedef AppliedAnswers = ({String before, String after, bool updated});

/// Rows of [before] → [after] with the position of each line (the old one
/// for removed lines), for [DiffView].
List<DiffRow> numberedDiff(String before, String after) {
  var oldNo = 1, newNo = 1;
  final out = <DiffRow>[];
  for (final d in lineDiff(before, after)) {
    switch (d.op) {
      case DiffOp.same:
        out.add((op: d.op, text: d.text, line: newNo++));
        oldNo++;
      case DiffOp.del:
        out.add((op: d.op, text: d.text, line: oldNo++));
      case DiffOp.add:
        out.add((op: d.op, text: d.text, line: newNo++));
    }
  }
  return out;
}

/// "Respostas aplicadas" one-line summary (R11).
String appliedSummary(
  List<OpenQuestion> questions,
  Map<String, Answer> answers, {
  required bool updated,
}) {
  final done = [
    for (final q in questions)
      if (answers[q.id]?.answered ?? false) q.id,
  ];
  final left = [
    for (final q in questions)
      if (!(answers[q.id]?.answered ?? false)) q.id,
  ];
  String list(List<String> ids) => ids.length == 1
      ? ids.single
      : '${ids.sublist(0, ids.length - 1).join(', ')} e ${ids.last}';
  return [
    if (updated) 'Requisitos e critérios atualizados pelo Claude;',
    'a seção Decisões com ${list(done)} e as respondidas fora da lista.',
    if (left.isNotEmpty)
      left.length == 1
          ? 'O ${left.single} continua em aberto.'
          : 'Continuam em aberto: ${list(left)}.',
  ].join(' ').replaceFirstMapped(RegExp('^a'), (_) => 'A');
}

enum _Stage { question, review, applying, diff }

/// "Responder perguntas" (SPEC-028 R6–R12, SPEC-059): one question at a
/// time with its options, the review of the answers, then the diff of what
/// changes in the spec before "Salvar na spec", in the center of the screen
/// ([SpecQuestionsFocus]). The answers live in [specAnswersProvider] (R8):
/// closing keeps them and nothing is written before saving.
class SpecQuestionsPanel extends ConsumerStatefulWidget {
  const SpecQuestionsPanel({
    super.key,
    required this.ws,
    required this.specId,
    required this.specCode,
    required this.specText,
    required this.questions,
    required this.onClose,
    required this.onApply,
    required this.onSave,
    this.specTitle,
  });

  final Workspace ws;
  final int specId;
  final String specCode;

  /// The title of the spec, in the header (SPEC-059 R1).
  final String? specTitle;

  /// Current text of the editor (context of the Claude's alternatives).
  final String Function() specText;
  final List<OpenQuestion> questions;
  final VoidCallback onClose;

  /// Writes the decisions (and, with [update], asks the Claude to update
  /// the requirements); null = cancelled or failed (the screen shows why).
  final Future<AppliedAnswers?> Function(
    Map<String, Answer> answers,
    bool update,
  )
  onApply;

  /// "Salvar na spec"; true = saved.
  final Future<bool> Function(String text) onSave;

  @override
  ConsumerState<SpecQuestionsPanel> createState() => _SpecQuestionsPanelState();
}

class _SpecQuestionsPanelState extends ConsumerState<SpecQuestionsPanel> {
  var _stage = _Stage.question;
  var _index = 0;
  var _update = true;
  AppliedAnswers? _applied;
  Map<String, Answer> _appliedAnswers = const {};
  bool _saving = false;
  final _other = TextEditingController();
  final _otherFocus = FocusNode(debugLabel: 'spec-question-other-text');
  final _options = {
    for (final o in AnswerOption.values)
      o: FocusNode(debugLabel: 'spec-question-${o.name}'),
  };
  final _panelFocus = FocusNode(debugLabel: 'spec-questions');

  List<OpenQuestion> get _questions => widget.questions;

  OpenQuestion? get _current => _questions.isEmpty
      ? null
      : _questions[_index.clamp(0, _questions.length - 1)];

  Map<String, Answer> get _answers =>
      ref.read(specAnswersProvider.notifier).of(widget.specId);

  @override
  void initState() {
    super.initState();
    _enter(0, announce: false);
  }

  @override
  void didUpdateWidget(SpecQuestionsPanel old) {
    super.didUpdateWidget(old);
    if (_questions.isNotEmpty && _index >= _questions.length) {
      _index = _questions.length - 1;
    }
  }

  @override
  void dispose() {
    _other.dispose();
    _otherFocus.dispose();
    for (final f in _options.values) {
      f.dispose();
    }
    _panelFocus.dispose();
    super.dispose();
  }

  /// Opens question [i] (R6): the "Outra resposta" text, the focus on the
  /// chosen option, the alternatives of this one and the next (P1) and the
  /// announcement (R12).
  void _enter(int i, {bool announce = true}) {
    if (_questions.isEmpty) return;
    _index = i.clamp(0, _questions.length - 1);
    _stage = _Stage.question;
    final q = _questions[_index];
    final a = _answers[q.id];
    _other.text = a?.option == AnswerOption.other ? a!.text : '';
    _prefetch(q);
    if (_index + 1 < _questions.length) _prefetch(_questions[_index + 1]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stage != _Stage.question) return;
      final o = _selected(q);
      (o == null ? _panelFocus : _options[o]!).requestFocus();
      if (announce) {
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Pergunta ${_index + 1} de ${_questions.length}',
            TextDirection.ltr,
          ),
        );
      }
    });
  }

  final _futures = <String, Future<List<QuestionAlternative>>>{};

  /// The alternatives that already arrived, by question (the keys 1–9 count
  /// them, SPEC-059 R5).
  final _loaded = <String, List<QuestionAlternative>>{};

  Future<List<QuestionAlternative>> _alternatives(OpenQuestion q) {
    final k = '${q.id}|${q.text}';
    return _futures[k] ??= ref
        .read(specQuestionOptionsProvider)
        .forQuestion(widget.ws, widget.specId, widget.specText(), q)
        .then((v) => _loaded[k] = v);
  }

  void _prefetch(OpenQuestion q) {
    _alternatives(q).ignore();
  }

  /// The options of [q] in the order shown: the suggestion, the
  /// alternatives that arrived and "Outra resposta" (SPEC-059 R3).
  List<AnswerOption> _optionsOf(OpenQuestion q) {
    final alts = _loaded['${q.id}|${q.text}'] ?? const [];
    return [
      if (q.suggestion != null) AnswerOption.suggestion,
      if (alts.isNotEmpty) AnswerOption.alternative1,
      if (alts.length > 1) AnswerOption.alternative2,
      AnswerOption.other,
    ];
  }

  /// The option shown as chosen: the stored answer, else the suggestion of
  /// the spec (pre-selected, R7).
  AnswerOption? _selected(OpenQuestion q) {
    final a = _answers[q.id];
    if (a != null && !a.deferred) return a.option;
    return q.suggestion == null ? null : AnswerOption.suggestion;
  }

  void _store(OpenQuestion q, Answer a) {
    ref.read(specAnswersProvider.notifier).set(widget.specId, q.id, a);
  }

  Future<void> _choose(OpenQuestion q, AnswerOption o) async {
    switch (o) {
      case AnswerOption.suggestion:
        _store(q, Answer(option: o, text: q.suggestion ?? ''));
      case AnswerOption.other:
        _store(q, Answer(option: o, text: _other.text.trim()));
      case AnswerOption.alternative1 || AnswerOption.alternative2:
        final alts = await _alternatives(q)
            .catchError((Object _) => const <QuestionAlternative>[]);
        final i = o == AnswerOption.alternative1 ? 0 : 1;
        if (i < alts.length) _store(q, Answer(option: o, text: alts[i].title));
    }
    if (mounted) setState(() {});
  }

  /// "Próxima" (R6): the chosen option is kept (the pre-selected suggestion
  /// too); without an answer the question is left for later.
  void _next() {
    final q = _current;
    if (q == null) return;
    final a = _answers[q.id];
    if (a != null && a.answered) {
      // Kept as chosen.
    } else if (_selected(q) == AnswerOption.suggestion) {
      _store(q, Answer(option: AnswerOption.suggestion, text: q.suggestion!));
    } else {
      _store(q, const Answer.deferred());
    }
    _advance();
  }

  void _defer() {
    final q = _current;
    if (q == null) return;
    _store(q, const Answer.deferred());
    _advance();
  }

  void _advance() {
    setState(() {
      if (_index + 1 < _questions.length) {
        _enter(_index + 1);
      } else {
        _stage = _Stage.review;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _panelFocus.requestFocus();
        });
      }
    });
  }

  void _previous() {
    setState(() {
      if (_stage == _Stage.review) {
        _enter(_questions.length - 1);
      } else if (_index > 0) {
        _enter(_index - 1);
      }
    });
  }

  /// ←/→ (SPEC-059 R5): another question, like a click on its step; the
  /// answer chosen stays as it is.
  void _goTo(int i) {
    if (i < 0 || i >= _questions.length || i == _index) return;
    setState(() => _enter(i));
  }

  int get _answeredCount => [
    for (final q in _questions)
      if (_answers[q.id]?.answered ?? false) q,
  ].length;

  Future<void> _apply() async {
    final answers = {for (final q in _questions) q.id: ?_answers[q.id]};
    setState(() => _stage = _Stage.applying);
    final r = await widget.onApply(answers, _update);
    if (!mounted) return;
    setState(() {
      _applied = r;
      _appliedAnswers = answers;
      _stage = r == null ? _Stage.review : _Stage.diff;
    });
  }

  Future<void> _save() async {
    final r = _applied;
    if (r == null || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.onSave(r.after);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) widget.onClose();
  }

  // --- keys (SPEC-059 R5) -------------------------------------------------------

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const _numpad = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  /// The focus is on the question itself (an option or the column), not on
  /// a button or the text field: Enter is "Próxima" there.
  bool get _focusOnQuestion {
    final f = FocusManager.instance.primaryFocus;
    return f == _panelFocus || _options.values.contains(f);
  }

  /// 1…9 choose (outside the text field), Enter goes to the next one, ←/→
  /// or Alt+←/→ change the question. Esc is the frame's.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final q = _current;
    if (_stage != _Stage.question || q == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final kb = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final inField = _otherFocus.hasFocus;
    final plain =
        !kb.isAltPressed &&
        !kb.isControlPressed &&
        !kb.isShiftPressed &&
        !kb.isMetaPressed;
    final alt =
        kb.isAltPressed &&
        !kb.isControlPressed &&
        !kb.isShiftPressed &&
        !kb.isMetaPressed;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (alt || (plain && !inField)) {
        _goTo(_index + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final enter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (enter && plain && !inField && _focusOnQuestion) {
      _next();
      return KeyEventResult.handled;
    }
    var n = _digits.indexOf(key);
    if (n < 0) n = _numpad.indexOf(key);
    if (n >= 0 && plain && !inField) {
      final options = _optionsOf(q);
      if (n < options.length) {
        final o = options[n];
        unawaited(_choose(q, o));
        _options[o]!.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Left / right on a focused option: the radio group would take them to
  /// move between the options, which ↑/↓ already do.
  KeyEventResult _onOptionsKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (_otherFocus.hasFocus) return KeyEventResult.ignored;
    return _onKey(node, event);
  }

  // --- build -------------------------------------------------------------------

  String get _prefix => [
    widget.specCode,
    if (widget.specTitle case final t? when t.trim().isNotEmpty) t.trim(),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    ref.watch(specAnswersProvider);
    final q = _current;
    final (title, subtitle) = switch (_stage) {
      _ when q == null => ('Responder perguntas', _prefix),
      _Stage.question => (
        'Responder perguntas',
        '$_prefix · pergunta ${_index + 1} de ${_questions.length}',
      ),
      _Stage.review ||
      _Stage.applying => ('Responder perguntas', '$_prefix · ${_countLabel()}'),
      _Stage.diff => ('Respostas aplicadas', '$_prefix · nada foi salvo ainda'),
    };
    return SpecQuestionsFocus(
      title: title,
      specCode: widget.specCode,
      subtitle: subtitle,
      focusNode: _panelFocus,
      onKeyEvent: _onKey,
      onClose: _stage == _Stage.applying ? null : widget.onClose,
      turn: (_stage, _index),
      scrollable: _stage != _Stage.diff && _stage != _Stage.applying,
      maxWidth: 720,
      body: q == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'A spec não tem perguntas em aberto.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          : switch (_stage) {
              _Stage.question => _questionView(q),
              _Stage.review => _reviewView(),
              _Stage.applying => _applyingView(),
              _Stage.diff => _diffView(),
            },
      footer: q == null
          ? QuestionFooter(
              left: const [],
              right: [
                OutlinedButton(
                  onPressed: widget.onClose,
                  child: const Text('Fechar'),
                ),
              ],
            )
          : _footer(q),
    );
  }

  String _countLabel() {
    final answered = _answeredCount;
    final later = _questions.length - answered;
    return [
      answered == 1 ? '1 respondida' : '$answered respondidas',
      if (later > 0) '$later para depois',
    ].join(', ');
  }

  Widget _steps() => QuestionSteps(
    questions: _questions,
    answers: _answers,
    current: _stage == _Stage.question ? _index : null,
    onTap: _stage == _Stage.applying ? null : (i) => setState(() => _enter(i)),
  );

  Widget _questionView(OpenQuestion q) {
    final selected = _selected(q);
    return FutureBuilder<List<QuestionAlternative>>(
      future: _alternatives(q),
      builder: (context, snap) {
        final alts = snap.data ?? const <QuestionAlternative>[];
        final loading = snap.connectionState != ConnectionState.done;
        final failed = snap.hasError;
        final note = q.suggestion == null
            ? 'A spec não traz sugestão; as opções foram propostas pelo '
                  'Claude.'
            : 'A primeira opção é a sugestão escrita na spec; as outras '
                  'foram propostas pelo Claude.';
        var number = 0;
        int? next() => ++number <= 9 ? number : null;
        return Column(
          key: const ValueKey('spec-questions-body'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _steps(),
            const SizedBox(height: 24),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${q.id} ',
                    style: const TextStyle(color: AppColors.amber),
                  ),
                  TextSpan(text: q.text),
                ],
              ),
              key: const ValueKey('spec-question-text'),
              style: const TextStyle(
                fontSize: 22,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note,
                    key: const ValueKey('spec-question-note'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            RadioGroup<AnswerOption>(
              groupValue: selected,
              onChanged: (o) {
                if (o != null) unawaited(_choose(q, o));
              },
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                includeSemantics: false,
                onKeyEvent: _onOptionsKey,
                child: Column(
                  key: const ValueKey('spec-question-options'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (q.suggestion != null)
                      _option(
                        q,
                        AnswerOption.suggestion,
                        selected,
                        number: next(),
                        title: q.suggestion!,
                        badge: 'Sugestão da spec',
                      ),
                    for (final (i, alt) in alts.indexed)
                      _option(
                        q,
                        i == 0
                            ? AnswerOption.alternative1
                            : AnswerOption.alternative2,
                        selected,
                        number: next(),
                        title: alt.title,
                        detail: alt.consequence,
                      ),
                    if (loading)
                      const _Hint(
                        key: ValueKey('spec-question-loading'),
                        text: 'O Claude está propondo alternativas…',
                        spinner: true,
                      )
                    else if (failed)
                      const _Hint(
                        key: ValueKey('spec-question-failed'),
                        text:
                            'Não foi possível gerar alternativas. Use a '
                            'sugestão ou escreva a sua resposta.',
                      ),
                    _option(
                      q,
                      AnswerOption.other,
                      selected,
                      number: next(),
                      title: 'Outra resposta',
                      field: _otherField(q),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _otherField(OpenQuestion q) => TextField(
    key: const ValueKey('spec-question-other-text'),
    controller: _other,
    focusNode: _otherFocus,
    textInputAction: TextInputAction.next,
    style: const TextStyle(fontSize: 13.5, height: 1.45),
    decoration: const InputDecoration(
      isDense: true,
      hintText: 'Escreva a sua resposta…',
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(),
    ),
    onChanged: (v) =>
        _store(q, Answer(option: AnswerOption.other, text: v.trim())),
    onSubmitted: (_) => _next(),
  );

  Widget _option(
    OpenQuestion q,
    AnswerOption o,
    AnswerOption? selected, {
    required String title,
    required int? number,
    String? badge,
    String? detail,
    Widget? field,
  }) => QuestionOptionCard<AnswerOption>(
    key: ValueKey('spec-question-option-${o.name}'),
    radioKey: ValueKey('spec-question-radio-${o.name}'),
    value: o,
    selected: selected == o,
    title: title,
    number: number,
    badge: badge,
    detail: detail,
    field: field,
    focusNode: _options[o],
    onTap: () => unawaited(_choose(q, o)),
  );

  Widget _reviewView() {
    final answers = _answers;
    return Column(
      key: const ValueKey('spec-questions-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _steps(),
        const SizedBox(height: 24),
        const Text(
          'Revise antes de aplicar',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        for (final (i, q) in _questions.indexed) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.border),
          _reviewRow(i, q, answers[q.id]),
        ],
        const SizedBox(height: 12),
        Material(
          color: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: const ValueKey('spec-questions-update'),
            value: _update,
            onChanged: (v) => setState(() => _update = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.amber,
            checkColor: AppColors.onAmber,
            dense: true,
            title: const Text(
              'Atualizar requisitos e critérios com as respostas',
              style: TextStyle(fontSize: 13, color: AppColors.text),
            ),
            subtitle: const Text(
              'O Claude edita só esta spec. Você revisa o resultado antes de '
              'salvar.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(int i, OpenQuestion q, Answer? a) {
    final answered = a?.answered ?? false;
    return Padding(
      key: ValueKey('spec-questions-review-${q.id}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              q.id,
              style: const TextStyle(fontSize: 12, color: AppColors.amber),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  answered
                      ? a!.text
                      : 'Sem resposta; continua em "Perguntas em aberto".',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: answered ? AppColors.text : AppColors.textSecondary,
                  ),
                ),
                if (!answered) ...[
                  const SizedBox(height: 6),
                  Container(
                    key: ValueKey('spec-questions-later-${q.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.amberTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.amber.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      'Para depois',
                      style: TextStyle(fontSize: 11, color: AppColors.amber),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: ValueKey('spec-questions-change-${q.id}'),
            onPressed: () => setState(() => _enter(i)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.border),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              'Mudar',
              semanticsLabel: 'Mudar a resposta de ${q.id}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _applyingView() => Center(
    key: const ValueKey('spec-questions-applying'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AmbientSpinner(size: 18, strokeWidth: 2),
        const SizedBox(height: 10),
        Text(
          _update
              ? 'O Claude está atualizando requisitos e critérios…'
              : 'Aplicando as respostas…',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _diffView() {
    final r = _applied!;
    final rows = numberedDiff(r.before, r.after);
    final added = rows.where((x) => x.op == DiffOp.add).length;
    final removed = rows.where((x) => x.op == DiffOp.del).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Alterações na spec',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              Text(
                '+$added',
                key: const ValueKey('spec-questions-added'),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '−$removed',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            appliedSummary(_questions, _appliedAnswers, updated: r.updated),
            key: const ValueKey('spec-questions-summary'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: DiffView(
                  key: const ValueKey('spec-questions-diff'),
                  rows: rows,
                  collapseSame: 4,
                  scrollable: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(OpenQuestion q) {
    const secondary = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(AppColors.text),
      side: WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
    final primary = FilledButton.styleFrom(
      backgroundColor: AppColors.amber,
      foregroundColor: AppColors.onAmber,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).copyWith(overlayColor: AppTheme.filledOverlay);
    const bold = TextStyle(fontWeight: FontWeight.w600);
    final last = _index + 1 >= _questions.length;
    return switch (_stage) {
      _Stage.question => QuestionFooter(
        left: [
          OutlinedButton.icon(
            key: const ValueKey('spec-questions-previous'),
            onPressed: _index > 0 ? _previous : null,
            style: secondary,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Anterior', style: bold),
          ),
        ],
        right: [
          OutlinedButton.icon(
            key: const ValueKey('spec-questions-defer'),
            onPressed: _defer,
            style: secondary,
            icon: const Icon(Icons.schedule, size: 16),
            label: const Text('Deixar para depois', style: bold),
          ),
          AppPressable(
            child: FilledButton(
              key: const ValueKey('spec-questions-next'),
              onPressed: _next,
              style: primary,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(last ? 'Revisar respostas' : 'Próxima', style: bold),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 18),
                  const SizedBox(width: 8),
                  const ExcludeSemantics(
                    child: StepKbd('Enter', onAmber: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      _Stage.review || _Stage.applying => QuestionFooter(
        left: [
          OutlinedButton.icon(
            key: const ValueKey('spec-questions-previous'),
            onPressed: _stage == _Stage.review ? _previous : null,
            style: secondary,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Anterior', style: bold),
          ),
        ],
        right: [
          AppPressable(
            enabled: _stage == _Stage.review && _answeredCount > 0,
            child: FilledButton.icon(
              key: const ValueKey('spec-questions-apply'),
              onPressed: _stage == _Stage.review && _answeredCount > 0
                  ? _apply
                  : null,
              style: primary,
              icon: const Icon(Icons.check, size: 16),
              label: Text(
                _answeredCount == 1
                    ? 'Aplicar 1 resposta'
                    : 'Aplicar $_answeredCount respostas',
                style: bold,
              ),
            ),
          ),
        ],
      ),
      _Stage.diff => QuestionFooter(
        left: [
          TextButton(
            key: const ValueKey('spec-questions-discard'),
            onPressed: _saving ? null : widget.onClose,
            child: const Text('Descartar'),
          ),
        ],
        right: [
          OutlinedButton.icon(
            key: const ValueKey('spec-questions-back'),
            onPressed: _saving
                ? null
                : () => setState(() => _stage = _Stage.review),
            style: secondary,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Voltar às respostas'),
          ),
          AppPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              key: const ValueKey('spec-questions-save'),
              onPressed: _saving ? null : _save,
              style: primary,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Salvar na spec', style: bold),
            ),
          ),
        ],
      ),
    };
  }
}

class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.text, this.spinner = false});

  final String text;
  final bool spinner;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
    child: Row(
      children: [
        if (spinner) ...[
          const AmbientSpinner(strokeWidth: 1.5),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
