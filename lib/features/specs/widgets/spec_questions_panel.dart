import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
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
  bool _appliedUpdate = true;
  bool _saving = false;

  /// SPEC-060 R4: the first Delete arms "Descartar"; a second one within
  /// [_discardWindow] discards.
  bool _discardArmed = false;
  Timer? _discardTimer;
  static const _discardWindow = Duration(seconds: 3);
  final _other = TextEditingController();
  final _otherFocus = FocusNode(debugLabel: 'spec-question-other-text');
  final _options = {
    for (final o in AnswerOption.values)
      o: FocusNode(debugLabel: 'spec-question-${o.name}'),
  };
  final _panelFocus = FocusNode(debugLabel: 'spec-questions');

  /// "Ver na spec" (SPEC-059 R7): kept for the next questions until the
  /// session closes.
  bool _showExcerpt = false;

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
    _discardTimer?.cancel();
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

  // --- "Outras sugestões" (SPEC-061) -----------------------------------------

  /// Questions whose new set is on the way.
  final _moreBusy = <String>{};

  /// Questions whose last "Outras sugestões" failed (R5).
  final _moreFailed = <String>{};

  /// After "Outras sugestões": the index of the alternative kept (the chosen
  /// one), or -1 when every one is new (R4).
  final _kept = <String, int>{};

  String _qKey(OpenQuestion q) => '${q.id}|${q.text}';

  /// Asks the Claude for a new set of alternatives for [q]; the chosen one,
  /// if any, stays where it is.
  Future<void> _more(OpenQuestion q) async {
    final k = _qKey(q);
    // After a failed first try the list is empty: this asks again.
    final current = _loaded[k] ?? const <QuestionAlternative>[];
    if (_moreBusy.contains(k)) return;
    final a = _answers[q.id];
    final i = a == null || !a.answered
        ? -1
        : alternativeOptions.indexOf(a.option);
    final keep = i >= 0 && i < current.length ? i : null;
    // The focus on an option that is going away goes to the column.
    final f = FocusManager.instance.primaryFocus;
    final leaving = [
      for (final (j, o) in alternativeOptions.indexed)
        if (j != keep) _options[o],
    ];
    if (leaving.contains(f)) _panelFocus.requestFocus();
    setState(() {
      _moreBusy.add(k);
      _moreFailed.remove(k);
    });
    try {
      final next = await ref
          .read(specQuestionOptionsProvider)
          .more(
            widget.ws,
            widget.specId,
            widget.specText(),
            q,
            current: current,
            keep: keep,
          );
      if (!mounted) return;
      setState(() {
        _loaded[k] = next;
        _futures[k] = Future.value(next);
        _kept[k] = keep ?? -1;
      });
      final n = next.length - (keep == null ? 0 : 1);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          n == 1 ? '1 nova sugestão' : '$n novas sugestões',
          TextDirection.ltr,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _moreFailed.add(k));
    } finally {
      if (mounted) setState(() => _moreBusy.remove(k));
    }
  }

  void _prefetch(OpenQuestion q) {
    _alternatives(q).ignore();
  }

  /// The options of [q] in the order shown: the suggestion, the
  /// alternatives that arrived and "Outra resposta" (SPEC-059 R3).
  List<AnswerOption> _optionsOf(OpenQuestion q) {
    final k = _qKey(q);
    final alts = _loaded[k] ?? const [];
    final busy = _moreBusy.contains(k);
    return [
      if (q.suggestion != null) AnswerOption.suggestion,
      for (final (i, o) in alternativeOptions.indexed)
        // SPEC-061 R3: the ones being replaced are out of the keys.
        if (i < alts.length && (!busy || _isKeptWhileBusy(q, i))) o,
      AnswerOption.other,
    ];
  }

  /// While a new set comes, the chosen alternative stays.
  bool _isKeptWhileBusy(OpenQuestion q, int i) {
    final a = _answers[q.id];
    return a != null && a.answered && alternativeOptions.indexOf(a.option) == i;
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
    // Another option chosen from the field: the focus goes with it, so
    // Enter is "Próxima" again.
    if (o != AnswerOption.other && _otherFocus.hasFocus) {
      _options[o]!.requestFocus();
    }
    switch (o) {
      case AnswerOption.suggestion:
        _store(q, Answer(option: o, text: q.suggestion ?? ''));
      case AnswerOption.other:
        _store(q, Answer(option: o, text: _other.text.trim()));
        // SPEC-059 R6: straight to the field. The arrows of the radio
        // group put the focus back on the option right after.
        _otherFocus.requestFocus();
      case AnswerOption.alternative1 ||
          AnswerOption.alternative2 ||
          AnswerOption.alternative3:
        final alts = await _alternatives(q)
            .catchError((Object _) => const <QuestionAlternative>[]);
        final i = alternativeOptions.indexOf(o);
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
    // SPEC-060 R3: back from the diff with nothing changed, the diff that
    // was already made comes back without running the Claude again.
    if (_applied != null &&
        _appliedUpdate == _update &&
        mapEquals(answers, _appliedAnswers)) {
      setState(() => _stage = _Stage.diff);
      _focusPanel();
      return;
    }
    setState(() => _stage = _Stage.applying);
    final r = await widget.onApply(answers, _update);
    if (!mounted) return;
    setState(() {
      _applied = r;
      _appliedAnswers = answers;
      _appliedUpdate = _update;
      _stage = r == null ? _Stage.review : _Stage.diff;
    });
    _focusPanel();
  }

  /// "Voltar às respostas" (SPEC-060 R3: also Esc).
  void _backToReview() {
    _disarm();
    setState(() => _stage = _Stage.review);
    _focusPanel();
  }

  /// The column takes the focus, so Enter is the primary action again.
  void _focusPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panelFocus.requestFocus();
    });
  }

  void _arm() {
    _discardTimer?.cancel();
    _discardTimer = Timer(_discardWindow, _disarm);
    setState(() => _discardArmed = true);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Aperte Delete de novo em 3 segundos para descartar. '
        'As respostas continuam guardadas.',
        TextDirection.ltr,
      ),
    );
  }

  void _disarm() {
    _discardTimer?.cancel();
    _discardTimer = null;
    if (_discardArmed && mounted) setState(() => _discardArmed = false);
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
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (q != null && (_stage == _Stage.review || _stage == _Stage.diff)) {
      return _onEndKey(event);
    }
    if (_stage != _Stage.question || q == null) return KeyEventResult.ignored;
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
    // SPEC-059 R6: in the field Enter breaks the line; Ctrl+Enter goes on.
    final ctrl =
        kb.isControlPressed &&
        !kb.isAltPressed &&
        !kb.isShiftPressed &&
        !kb.isMetaPressed;
    if (enter && ctrl) {
      _next();
      return KeyEventResult.handled;
    }
    // SPEC-061 R2: "Outras sugestões", in the field too.
    if (key == LogicalKeyboardKey.keyR && ctrl) {
      unawaited(_more(q));
      return KeyEventResult.handled;
    }
    var n = _digits.indexOf(key);
    if (n < 0) n = _numpad.indexOf(key);
    if (n >= 0 && plain && !inField) {
      final options = _optionsOf(q);
      if (n < options.length) {
        final o = options[n];
        if (o != AnswerOption.other) _options[o]!.requestFocus();
        unawaited(_choose(q, o));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// SPEC-060: in the review Esc goes back to the questions and Enter
  /// applies; in "O que muda na spec" Enter saves, Esc goes back to the
  /// review and Delete (twice) discards. Ctrl+Esc is the frame's (close).
  KeyEventResult _onEndKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final plain =
        !kb.isAltPressed &&
        !kb.isControlPressed &&
        !kb.isShiftPressed &&
        !kb.isMetaPressed;
    final delete = key == LogicalKeyboardKey.delete;
    if (_discardArmed && !(delete && plain)) _disarm();
    if (!plain) return KeyEventResult.ignored;
    final esc = key == LogicalKeyboardKey.escape;
    final enter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!esc && !enter && !(delete && _stage == _Stage.diff)) {
      return KeyEventResult.ignored;
    }
    // While saving, nothing (and Esc does not close).
    if (_saving) return KeyEventResult.handled;
    if (esc) {
      _stage == _Stage.review ? _previous() : _backToReview();
      return KeyEventResult.handled;
    }
    if (enter) {
      // A focused button or checkbox takes its own Enter (SPEC-060 R2).
      if (FocusManager.instance.primaryFocus != _panelFocus) {
        return KeyEventResult.ignored;
      }
      if (_stage == _Stage.diff) {
        unawaited(_save());
      } else if (_answeredCount > 0) {
        unawaited(_apply());
      }
      return KeyEventResult.handled;
    }
    if (_discardArmed) {
      _disarm();
      widget.onClose();
    } else {
      _arm();
    }
    return KeyEventResult.handled;
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
      _Stage.applying => ('Responder perguntas', '$_prefix · revisão'),
      _Stage.diff => (
        'Responder perguntas',
        '$_prefix · o que muda na spec · nada foi salvo ainda',
      ),
    };
    // SPEC-060 R4: a click anywhere disarms "Descartar".
    return Listener(
      onPointerDown: (_) => _disarm(),
      child: SpecQuestionsFocus(
        title: title,
        specCode: widget.specCode,
        subtitle: subtitle,
        focusNode: _panelFocus,
        onKeyEvent: _onKey,
        onClose: _stage == _Stage.applying || _saving ? null : widget.onClose,
        turn: (_stage, _index),
        scrollable: _stage != _Stage.diff && _stage != _Stage.applying,
        // SPEC-059 R8: the diff takes the width of the area, up to 1100 px.
        maxWidth: _stage == _Stage.diff ? 1100 : 720,
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
      ),
    );
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
        final k = _qKey(q);
        final alts = _loaded[k] ?? snap.data ?? const <QuestionAlternative>[];
        final loading = snap.connectionState != ConnectionState.done;
        final failed = snap.hasError;
        final busy = _moreBusy.contains(k);
        final kept = _kept[k];
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
            _noteLine(q, note),
            if (_showExcerpt) ...[const SizedBox(height: 12), _excerpt(q)],
            const SizedBox(height: 16),
            _moreRow(q, enabled: !loading && !busy, busy: busy),
            if (_moreFailed.contains(k)) ...[
              const SizedBox(height: 8),
              _moreError(q),
            ],
            const SizedBox(height: 10),
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
                      if (busy && !_isKeptWhileBusy(q, i))
                        _OptionSkeleton(key: ValueKey('spec-question-wait-$i'))
                      else
                        _option(
                          q,
                          alternativeOptions[i],
                          selected,
                          number: next(),
                          title: alt.title,
                          detail: alt.consequence,
                          badge: kept == null
                              ? null
                              : kept == i
                              ? 'mantida'
                              : 'nova',
                          badgeColor: kept == i
                              ? AppColors.teal
                              : AppColors.textSecondary,
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
                      field: _otherField(
                        q,
                        selected: selected == AnswerOption.other,
                      ),
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

  /// "Outra resposta" (SPEC-059 R6): grows up to 6 lines and then
  /// scrolls; Enter breaks the line, Ctrl+Enter goes to the next question.
  Widget _otherField(OpenQuestion q, {required bool selected}) => TextField(
    key: const ValueKey('spec-question-other-text'),
    controller: _other,
    focusNode: _otherFocus,
    keyboardType: TextInputType.multiline,
    textInputAction: TextInputAction.newline,
    minLines: selected ? 3 : 1,
    maxLines: 6,
    style: const TextStyle(fontSize: 13.5, height: 1.45),
    decoration: const InputDecoration(
      isDense: true,
      hintText: 'Escreva a sua resposta…',
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(),
    ),
    onTap: () {
      if (_selected(q) != AnswerOption.other) {
        unawaited(_choose(q, AnswerOption.other));
      }
    },
    onChanged: (v) =>
        _store(q, Answer(option: AnswerOption.other, text: v.trim())),
  );

  /// Where the options come from, and "Ver na spec" / "Esconder trecho"
  /// (SPEC-059 R2, R7).
  Widget _noteLine(OpenQuestion q, String note) {
    final excerpt = _showExcerpt
        ? SpecDocument.parse(widget.specText()).questionExcerpt(q)
        : null;
    final text = !_showExcerpt
        ? note
        : excerpt == null
        ? 'A pergunta não está mais em Perguntas em aberto.'
        : excerpt.first == excerpt.last
        ? 'Linha ${excerpt.first} de Perguntas em aberto'
        : 'Linhas ${excerpt.first}–${excerpt.last} de Perguntas em aberto';
    const style = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: AppColors.textSecondary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.description_outlined,
          size: 14,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            key: const ValueKey('spec-question-note'),
            style: style,
          ),
        ),
        const Text(' · ', style: style),
        Semantics(
          button: true,
          expanded: _showExcerpt,
          child: InkWell(
            key: const ValueKey('spec-question-excerpt-toggle'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _showExcerpt = !_showExcerpt),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showExcerpt ? 'Esconder trecho' : 'Ver na spec',
                    style: style.copyWith(
                      color: AppColors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _showExcerpt ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: AppColors.amber,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _excerpt(OpenQuestion q) {
    final excerpt = SpecDocument.parse(widget.specText()).questionExcerpt(q);
    return excerpt == null
        ? const SizedBox.shrink()
        : QuestionExcerpt(excerpt: excerpt);
  }

  Widget _option(
    OpenQuestion q,
    AnswerOption o,
    AnswerOption? selected, {
    required String title,
    required int? number,
    String? badge,
    Color badgeColor = AppColors.amber,
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
    badgeColor: badgeColor,
    detail: detail,
    field: field,
    focusNode: _options[o],
    onTap: () => unawaited(_choose(q, o)),
  );

  /// "RESPOSTAS" and "Outras sugestões · Ctrl+R" (SPEC-061 R2).
  Widget _moreRow(
    OpenQuestion q, {
    required bool enabled,
    required bool busy,
  }) => Row(
    children: [
      const Expanded(
        child: Text(
          'RESPOSTAS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      Tooltip(
        message: 'Pedir outras três sugestões ao Claude (Ctrl+R)',
        child: OutlinedButton(
          key: const ValueKey('spec-question-more'),
          onPressed: enabled ? () => unawaited(_more(q)) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh, size: 15),
              const SizedBox(width: 6),
              Text(
                busy ? 'Gerando outras…' : 'Outras sugestões',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!busy) ...[
                const SizedBox(width: 8),
                const ExcludeSemantics(child: StepKbd('Ctrl+R')),
              ],
            ],
          ),
        ),
      ),
    ],
  );

  /// R5: the last set stays; "Tentar de novo" asks again.
  Widget _moreError(OpenQuestion q) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('spec-question-more-failed'),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Não deu para gerar outras sugestões. As anteriores continuam '
              'aqui.',
              style: TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ),
          TextButton(
            key: const ValueKey('spec-question-more-retry'),
            onPressed: () => unawaited(_more(q)),
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    ),
  );

  Widget _reviewView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _steps(),
      const SizedBox(height: 24),
      AnswersReview(
        questions: _questions,
        answers: _answers,
        update: _update,
        onUpdate: (v) => setState(() => _update = v),
        onEdit: (i) => setState(() => _enter(i)),
      ),
    ],
  );

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

  Widget _diffView() => AnswersDiff(
    applied: _applied!,
    summary: appliedSummary(
      _questions,
      _appliedAnswers,
      updated: _applied!.updated,
    ),
  );

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
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Voltar às perguntas', style: bold),
                SizedBox(width: 8),
                ExcludeSemantics(child: StepKbd('Esc')),
              ],
            ),
          ),
        ],
        right: [
          AppPressable(
            enabled: _stage == _Stage.review && _answeredCount > 0,
            child: FilledButton(
              key: const ValueKey('spec-questions-apply'),
              onPressed: _stage == _Stage.review && _answeredCount > 0
                  ? _apply
                  : null,
              style: primary,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _answeredCount == 1
                        ? 'Aplicar 1 resposta na spec'
                        : 'Aplicar $_answeredCount respostas na spec',
                    style: bold,
                  ),
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
      _Stage.diff => QuestionFooter(
        left: [
          _discardArmed
              ? OutlinedButton(
                  key: const ValueKey('spec-questions-discard'),
                  onPressed: _saving ? null : widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    backgroundColor: AppColors.red.withValues(alpha: .12),
                    side: BorderSide(
                      color: AppColors.red.withValues(alpha: .55),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Descartar mudanças?', style: bold),
                      SizedBox(width: 8),
                      ExcludeSemantics(child: StepKbd('Delete')),
                      SizedBox(width: 6),
                      Text('de novo'),
                    ],
                  ),
                )
              : TextButton(
                  key: const ValueKey('spec-questions-discard'),
                  onPressed: _saving ? null : widget.onClose,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Descartar'),
                      SizedBox(width: 8),
                      ExcludeSemantics(child: StepKbd('Delete')),
                    ],
                  ),
                ),
        ],
        right: [
          OutlinedButton.icon(
            key: const ValueKey('spec-questions-back'),
            onPressed: _saving ? null : _backToReview,
            style: secondary,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Voltar às respostas'),
                SizedBox(width: 8),
                ExcludeSemantics(child: StepKbd('Esc')),
              ],
            ),
          ),
          AppPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              key: const ValueKey('spec-questions-save'),
              onPressed: _saving ? null : _save,
              style: primary,
              icon: const Icon(Icons.check, size: 16),
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Salvar na spec', style: bold),
                  SizedBox(width: 8),
                  ExcludeSemantics(child: StepKbd('Enter', onAmber: true)),
                ],
              ),
            ),
          ),
        ],
      ),
    };
  }
}

/// An alternative on the way (SPEC-061 R3): no text, out of the keys and
/// of the focus.
class _OptionSkeleton extends StatelessWidget {
  const _OptionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar(double f, double h) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: f,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: .6)),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(.38, 11),
                  const SizedBox(height: 9),
                  bar(.82, 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

/// "Revise as respostas" (SPEC-059 R8, SPEC-028 R9): each question with
/// the answer given and **Editar**, the ones left for later marked, and the
/// box to update the requirements.
class AnswersReview extends StatelessWidget {
  const AnswersReview({
    super.key,
    required this.questions,
    required this.answers,
    required this.update,
    required this.onUpdate,
    required this.onEdit,
  });

  final List<OpenQuestion> questions;
  final Map<String, Answer> answers;
  final bool update;
  final ValueChanged<bool> onUpdate;

  /// Back to question [i].
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final answered = [
      for (final q in questions)
        if (answers[q.id]?.answered ?? false) q,
    ].length;
    final later = questions.length - answered;
    final count = [
      answered == 1 ? '1 respondida' : '$answered respondidas',
      if (later > 0) '$later para depois',
    ].join(', ');
    return Column(
      key: const ValueKey('spec-questions-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Revise as respostas',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$count. Ao aplicar, as respostas vão para Decisões'
          '${update ? ', o Claude atualiza requisitos e critérios' : ''} '
          'e você vê o que muda antes de salvar.',
          key: const ValueKey('spec-questions-count'),
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        for (final (i, q) in questions.indexed) _row(i, q, answers[q.id]),
        const SizedBox(height: 4),
        Material(
          color: AppColors.surfaceRaisedSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: const ValueKey('spec-questions-update'),
            value: update,
            onChanged: (v) => onUpdate(v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.amber,
            checkColor: AppColors.onAmber,
            dense: true,
            title: const Text(
              'Atualizar requisitos e critérios com as respostas',
              style: TextStyle(fontSize: 13.5, color: AppColors.text),
            ),
            subtitle: const Text(
              'O Claude edita só esta spec. Você revisa o resultado antes de '
              'salvar.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(int i, OpenQuestion q, Answer? a) {
    final answered = a?.answered ?? false;
    return Padding(
      key: ValueKey('spec-questions-review-${q.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaisedSolid,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: Text(
                q.id,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.amber,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.text,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          answered ? Icons.check : Icons.schedule,
                          size: 14,
                          color: answered
                              ? AppColors.teal
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!answered) ...[
                        Container(
                          key: ValueKey('spec-questions-later-${q.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Text(
                            'Para depois',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          answered
                              ? a!.text
                              : 'Continua em Perguntas em aberto.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: answered
                                ? AppColors.text
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: ValueKey('spec-questions-change-${q.id}'),
              onPressed: () => onEdit(i),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amber,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Editar',
                semanticsLabel: 'Editar a resposta de ${q.id}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "O que muda na spec" (SPEC-059 R8, SPEC-028 R11): the summary and the
/// diff with line numbers, in the width of the area (up to 1100 px).
class AnswersDiff extends StatelessWidget {
  const AnswersDiff({super.key, required this.applied, required this.summary});

  final AppliedAnswers applied;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final rows = numberedDiff(applied.before, applied.after);
    final added = rows.where((x) => x.op == DiffOp.add).length;
    final removed = rows.where((x) => x.op == DiffOp.del).length;
    return Column(
      key: const ValueKey('spec-questions-diff-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'O que muda na spec',
                style: TextStyle(
                  fontSize: 20,
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
                fontSize: 13,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '−$removed',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 13,
                color: AppColors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          summary,
          key: const ValueKey('spec-questions-summary'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
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
    );
  }
}
