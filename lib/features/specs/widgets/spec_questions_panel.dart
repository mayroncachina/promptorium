import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/line_diff.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../dictation/dictation_controller.dart';
import '../../dictation/dictation_widgets.dart';
import '../../../ui/widgets/app_pressable.dart';
import '../../../ui/widgets/diff_view.dart';
import '../spec_answers.dart';
import '../spec_file.dart';

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

/// "Responder perguntas" (SPEC-028 R6–R12): one question at a time with its
/// options, the review of the answers, then the diff of what changes in the
/// spec before "Salvar na spec". The answers live in [specAnswersProvider]
/// (R8): closing the panel keeps them and nothing is written before saving.
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
  });

  final Workspace ws;
  final int specId;
  final String specCode;

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
  late final _dictation = DictationTarget(
    id: 'spec-question',
    controller: _other,
    focusNode: _otherFocus,
    onInserted: () {
      final q = _dictatedQuestion;
      if (q != null) {
        _store(q, Answer(option: AnswerOption.other, text: _other.text.trim()));
      }
    },
  );

  /// The question open when the field took dictation.
  OpenQuestion? _dictatedQuestion;
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

  Future<List<QuestionAlternative>> _alternatives(OpenQuestion q) =>
      _futures['${q.id}|${q.text}'] ??= ref
          .read(specQuestionOptionsProvider)
          .forQuestion(widget.ws, widget.specId, widget.specText(), q);

  void _prefetch(OpenQuestion q) {
    _alternatives(q).ignore();
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

  // --- build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.watch(specAnswersProvider);
    final q = _current;
    final (title, subtitle) = switch (_stage) {
      _ when q == null => ('Responder perguntas', widget.specCode),
      _Stage.question => (
        'Responder perguntas',
        '${widget.specCode}, pergunta ${_index + 1} de ${_questions.length}',
      ),
      _Stage.review ||
      _Stage.applying => ('Responder perguntas', _countLabel()),
      _Stage.diff => ('Respostas aplicadas', 'Nada foi salvo ainda'),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_stage != _Stage.applying) widget.onClose();
        },
      },
      child: Focus(
        focusNode: _panelFocus,
        includeSemantics: false,
        child: Container(
          key: const ValueKey('spec-questions-panel'),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(left: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(title, subtitle),
              if (q == null)
                const Expanded(
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
              else ...[
                if (_stage != _Stage.diff)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _trail(),
                  ),
                Expanded(
                  child: switch (_stage) {
                    _Stage.question => _questionView(q),
                    _Stage.review => _reviewView(),
                    _Stage.applying => _applyingView(),
                    _Stage.diff => _diffView(),
                  },
                ),
                const Divider(height: 1, color: AppColors.border),
                Padding(padding: const EdgeInsets.all(12), child: _footer(q)),
              ],
            ],
          ),
        ),
      ),
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

  Widget _header(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: const ValueKey('spec-questions-title'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  subtitle,
                  key: const ValueKey('spec-questions-subtitle'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('spec-questions-close'),
          tooltip: 'Fechar (Esc). As respostas ficam guardadas.',
          onPressed: _stage == _Stage.applying ? null : widget.onClose,
          icon: const Icon(Icons.close, size: 18),
          color: AppColors.textSecondary,
        ),
      ],
    ),
  );

  /// P1, P2… with the state of each one (R6): the icon says it too, not
  /// only the color.
  Widget _trail() => Row(
    key: const ValueKey('spec-questions-trail'),
    children: [
      for (final (i, q) in _questions.indexed) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _trailItem(i, q)),
      ],
    ],
  );

  Widget _trailItem(int i, OpenQuestion q) {
    final a = _answers[q.id];
    final current = _stage == _Stage.question && i == _index;
    final (state, icon, color) = current
        ? ('atual', null, AppColors.amber)
        : (a?.answered ?? false)
        ? ('respondida', Icons.check, AppColors.teal)
        : (a?.deferred ?? false)
        ? ('para depois', Icons.schedule, AppColors.amber)
        : ('pendente', null, AppColors.textSecondary);
    final dashed = !current && state == 'para depois';
    final border = current
        ? AppColors.amber
        : state == 'respondida'
        ? AppColors.teal.withValues(alpha: 0.5)
        : AppColors.border;
    final bg = current
        ? AppColors.amberTint
        : state == 'respondida'
        ? SessionColors.addBg
        : Colors.transparent;
    final label = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          q.id,
          style: TextStyle(
            fontSize: 12,
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            color: current ? AppColors.text : color,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      selected: current,
      label: '${q.id}, $state',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('spec-questions-trail-${q.id}'),
        onTap: _stage == _Stage.applying
            ? null
            : () => setState(() => _enter(i)),
        borderRadius: BorderRadius.circular(5),
        focusColor: AppColors.amberTint,
        child: CustomPaint(
          painter: dashed ? _DashedBorder(color: AppColors.amber) : null,
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(5),
              border: dashed ? null : Border.all(color: border),
            ),
            child: label,
          ),
        ),
      ),
    );
  }

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
            : 'A primeira opção é a sugestão escrita na spec; as seguintes '
                  'foram propostas pelo Claude.';
        return ListView(
          key: const ValueKey('spec-questions-body'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
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
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              note,
              key: const ValueKey('spec-question-note'),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _next,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): _next,
              },
              child: RadioGroup<AnswerOption>(
                groupValue: selected,
                onChanged: (o) {
                  if (o != null) unawaited(_choose(q, o));
                },
                child: Column(
                  key: const ValueKey('spec-question-options'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (q.suggestion != null)
                      _option(
                        q,
                        AnswerOption.suggestion,
                        selected,
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
                      title: 'Outra resposta',
                      field: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DictationLock(
                            id: _dictation.id,
                            builder: (locked) => TextField(
                              key: const ValueKey('spec-question-other-text'),
                              controller: _other,
                              focusNode: _otherFocus,
                              readOnly: locked,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'Escreva a sua resposta',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => _store(
                                q,
                                Answer(
                                  option: AnswerOption.other,
                                  text: v.trim(),
                                ),
                              ),
                              onSubmitted: (_) => _next(),
                            ),
                          ),
                          Builder(
                            builder: (_) {
                              _dictatedQuestion = q;
                              return DictationBar(target: _dictation);
                            },
                          ),
                        ],
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

  Widget _option(
    OpenQuestion q,
    AnswerOption o,
    AnswerOption? selected, {
    required String title,
    String? badge,
    String? detail,
    Widget? field,
  }) {
    final on = selected == o;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? AppColors.amberTint : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: on ? AppColors.amber : AppColors.border),
        ),
        child: InkWell(
          key: ValueKey('spec-question-option-${o.name}'),
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(8),
          onTap: () => unawaited(_choose(q, o)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Radio<AnswerOption>(
                  key: ValueKey('spec-question-radio-${o.name}'),
                  value: o,
                  focusNode: _options[o],
                  activeColor: AppColors.amber,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                            if (badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.amber.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  badge,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.amber,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (detail != null && detail.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            detail,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        if (field != null) ...[
                          const SizedBox(height: 8),
                          field,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewView() {
    final answers = _answers;
    return ListView(
      key: const ValueKey('spec-questions-review'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
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
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
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
    );
    final primary = FilledButton.styleFrom(
      backgroundColor: AppColors.amber,
      foregroundColor: AppColors.onAmber,
    ).copyWith(overlayColor: AppTheme.filledOverlay);
    const bold = TextStyle(fontWeight: FontWeight.w600);
    return switch (_stage) {
      _Stage.question => _bar(
        [
          TextButton.icon(
            key: const ValueKey('spec-questions-previous'),
            onPressed: _index > 0 ? _previous : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Anterior'),
          ),
        ],
        [
          OutlinedButton.icon(
            key: const ValueKey('spec-questions-defer'),
            onPressed: _defer,
            style: secondary,
            icon: const Icon(Icons.schedule, size: 16),
            label: const Text('Deixar para depois'),
          ),
          AppPressable(
            child: FilledButton.icon(
              key: const ValueKey('spec-questions-next'),
              onPressed: _next,
              style: primary,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Próxima', style: bold),
            ),
          ),
        ],
      ),
      _Stage.review || _Stage.applying => _bar(
        [
          TextButton.icon(
            key: const ValueKey('spec-questions-previous'),
            onPressed: _stage == _Stage.review ? _previous : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Anterior'),
          ),
        ],
        [
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
      _Stage.diff => _bar(
        [
          TextButton(
            key: const ValueKey('spec-questions-discard'),
            onPressed: _saving ? null : widget.onClose,
            child: const Text('Descartar'),
          ),
        ],
        [
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

  /// The footer (R6, R9, R11): [left] at the start and [right] at the end;
  /// stacked when they do not fit (large text).
  Widget _bar(List<Widget> left, List<Widget> right) => OverflowBar(
    alignment: MainAxisAlignment.spaceBetween,
    overflowAlignment: OverflowBarAlignment.end,
    overflowSpacing: 8,
    children: [
      Row(mainAxisSize: MainAxisSize.min, children: left),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: right,
      ),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.text, this.spinner = false});

  final String text;
  final bool spinner;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
    child: Row(
      children: [
        if (spinner) ...[
          const SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Dashed outline of a "para depois" step of the trail (R6).
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(5),
        ),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}
