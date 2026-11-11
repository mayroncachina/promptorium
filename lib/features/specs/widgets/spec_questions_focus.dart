import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../board/widgets/step_decision_parts.dart' show StepKbd;
import '../spec_answers.dart';
import '../spec_file.dart';

/// Width of the question column (SPEC-059 R2, R9): [max] (720 px) centered,
/// or the [available] width minus 32 px on each side when narrower.
double questionsColumnWidth(double available, {double max = 720}) =>
    math.max(0, math.min(max, available - 64));

/// "Responder perguntas" in the center of the screen (SPEC-059 R1, R2, R4,
/// R9, R10): a dialog over the specs area with the fixed header, the
/// centered column that scrolls and the fixed footer aligned to it. The
/// content (steps, question, options, review, diff) comes from
/// `SpecQuestionsPanel`, which keeps the state of SPEC-028.
class SpecQuestionsFocus extends StatefulWidget {
  const SpecQuestionsFocus({
    super.key,
    required this.specCode,
    required this.subtitle,
    required this.body,
    required this.footer,
    required this.onClose,
    this.title = 'Responder perguntas',
    this.onKeyEvent,
    this.focusNode,
    this.maxWidth = 720,
    this.scrollable = true,
    this.turn = 0,
  });

  final String title;
  final String specCode;

  /// "código · título · pergunta x de n", announced when it changes.
  final String subtitle;

  /// The content of the column; scrolls between the header and the footer
  /// unless [scrollable] is false (the diff scrolls by itself).
  final Widget body;
  final Widget footer;

  /// "Fechar" (Esc); null while the answers are being applied.
  final VoidCallback? onClose;

  /// The keys of the session (R5), after the focused widget's own.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// The root of the trapped focus (R10).
  final FocusNode? focusNode;

  /// 720 px; the diff uses up to 1100 px (R8).
  final double maxWidth;
  final bool scrollable;

  /// Changes with the question or the stage: the new content fades in
  /// (R10) and the scroll goes back to the top.
  final Object turn;

  @override
  State<SpecQuestionsFocus> createState() => _SpecQuestionsFocusState();
}

class _SpecQuestionsFocusState extends State<SpecQuestionsFocus>
    with TickerProviderStateMixin {
  /// R10: the session enters with a fade and a slight shift (180 ms).
  static const enterDuration = Duration(milliseconds: 180);

  /// R10: the question changes with a crossfade (120 ms).
  static const turnDuration = AppMotion.quick;

  late final _enter = AnimationController(vsync: this, duration: enterDuration);
  late final _turn = AnimationController(
    vsync: this,
    duration: turnDuration,
    value: 1,
  );
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppMotion.animate(context)) {
        _enter.forward();
      } else {
        _enter.value = 1;
      }
    });
  }

  @override
  void didUpdateWidget(SpecQuestionsFocus old) {
    super.didUpdateWidget(old);
    if (old.turn != widget.turn) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      if (AppMotion.animate(context)) {
        _turn.forward(from: 0);
      } else {
        _turn.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _turn.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final r = widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
    if (r != KeyEventResult.ignored) return r;
    // SPEC-060 R5: Ctrl+Esc closes from any screen; Esc closes when the
    // screen did not take it (the questions). While applying neither does
    // anything (and the run is not cancelled).
    final kb = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        !kb.isAltPressed &&
        !kb.isShiftPressed &&
        !kb.isMetaPressed) {
      widget.onClose?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final enter = CurvedAnimation(parent: _enter, curve: AppMotion.enter);
    final reduced = !AppMotion.animate(context);
    return Semantics(
      role: SemanticsRole.dialog,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Responder perguntas da ${widget.specCode}',
      child: FocusScope(
        autofocus: true,
        includeSemantics: false,
        onKeyEvent: _onKey,
        child: AnimatedBuilder(
          animation: enter,
          builder: (context, child) => Opacity(
            opacity: reduced ? 1 : enter.value,
            child: Transform.translate(
              offset: Offset(0, reduced ? 0 : 8 * (1 - enter.value)),
              child: child,
            ),
          ),
          child: Focus(
            focusNode: widget.focusNode,
            includeSemantics: false,
            child: Material(
              key: const ValueKey('spec-questions-panel'),
              color: AppColors.panelSolid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, c) {
                  final width = questionsColumnWidth(
                    c.maxWidth,
                    max: widget.maxWidth,
                  );
                  Widget column(Widget child) => Center(
                    child: SizedBox(width: width, child: child),
                  );
                  final body = FadeTransition(
                    opacity: _turn,
                    child: widget.body,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      const Divider(height: 1, color: AppColors.border),
                      Expanded(
                        child: widget.scrollable
                            ? Scrollbar(
                                controller: _scroll,
                                child: SingleChildScrollView(
                                  key: const ValueKey('spec-questions-scroll'),
                                  controller: _scroll,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 28,
                                  ),
                                  child: column(
                                    KeyedSubtree(
                                      key: const ValueKey(
                                        'spec-questions-column',
                                      ),
                                      child: body,
                                    ),
                                  ),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: column(
                                  KeyedSubtree(
                                    key: const ValueKey(
                                      'spec-questions-column',
                                    ),
                                    child: body,
                                  ),
                                ),
                              ),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: column(
                          KeyedSubtree(
                            key: const ValueKey('spec-questions-footer'),
                            child: widget.footer,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
    child: Row(
      children: [
        const Icon(
          Icons.description_outlined,
          size: 16,
          color: AppColors.amber,
        ),
        const SizedBox(width: 10),
        Text(
          widget.title,
          key: const ValueKey('spec-questions-title'),
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              widget.subtitle,
              key: const ValueKey('spec-questions-subtitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Tooltip(
          message:
              'As respostas ficam guardadas enquanto o app estiver aberto. '
              'Nada é gravado na spec antes de "Salvar na spec".',
          child: Text(
            'salvo automaticamente',
            key: ValueKey('spec-questions-autosave'),
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Fechar (Ctrl+Esc). As respostas ficam guardadas.',
          child: OutlinedButton(
            key: const ValueKey('spec-questions-close'),
            onPressed: widget.onClose,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.close, size: 15),
                SizedBox(width: 6),
                Text(
                  'Fechar',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 8),
                ExcludeSemantics(child: StepKbd('Ctrl+Esc')),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The steps P1…Pn (SPEC-059 R2, SPEC-028 R6): answered with a check in
/// teal, left for later with a clock and a dashed border, the current one
/// in amber. The icon says it too, not only the color; each one can be
/// clicked.
class QuestionSteps extends StatelessWidget {
  const QuestionSteps({
    super.key,
    required this.questions,
    required this.answers,
    required this.current,
    required this.onTap,
  });

  final List<OpenQuestion> questions;
  final Map<String, Answer> answers;

  /// Index of the open question; null in the review.
  final int? current;

  /// Null while applying.
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    key: const ValueKey('spec-questions-trail'),
    alignment: WrapAlignment.center,
    spacing: 6,
    runSpacing: 6,
    children: [for (final (i, q) in questions.indexed) _step(i, q)],
  );

  Widget _step(int i, OpenQuestion q) {
    final a = answers[q.id];
    final now = i == current;
    final (state, icon, color) = now
        ? ('atual', null, AppColors.amber)
        : (a?.answered ?? false)
        ? ('respondida', Icons.check, AppColors.teal)
        : (a?.deferred ?? false)
        ? ('para depois', Icons.schedule, AppColors.textSecondary)
        : ('pendente', null, AppColors.textSecondary);
    final dashed = state == 'para depois';
    final border = now
        ? AppColors.amber
        : state == 'respondida'
        ? AppColors.teal.withValues(alpha: 0.5)
        : AppColors.border;
    final bg = now
        ? AppColors.amberTint
        : state == 'respondida'
        ? SessionColors.addBg
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: now,
      label: '${q.id}, $state',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('spec-questions-trail-${q.id}'),
        onTap: onTap == null ? null : () => onTap!(i),
        borderRadius: BorderRadius.circular(6),
        focusColor: AppColors.amberTint,
        child: CustomPaint(
          painter: dashed ? const DashedBorder(color: AppColors.border) : null,
          child: Container(
            height: 30,
            constraints: const BoxConstraints(minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: dashed ? null : Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 12, color: color),
                  const SizedBox(width: 5),
                ],
                Text(
                  q.id,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: now ? AppColors.amber : color,
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

/// One option of the question (SPEC-059 R3): a wide card with the radio,
/// the title, the description and its key (1, 2, 3…).
class QuestionOptionCard<T> extends StatelessWidget {
  const QuestionOptionCard({
    super.key,
    required this.value,
    required this.selected,
    required this.title,
    required this.number,
    required this.onTap,
    this.focusNode,
    this.badge,
    this.detail,
    this.field,
    this.trailing,
    this.radioKey,
  });

  final T value;
  final bool selected;
  final String title;

  /// The key that chooses it (1…9); null past 9.
  final int? number;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final String? badge;
  final String? detail;

  /// "Outra resposta": the text field inside the card.
  final Widget? field;

  /// Before the key, on the title line ("Ditar").
  final Widget? trailing;
  final Key? radioKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: selected ? AppColors.amberTint : AppColors.surfaceRaisedSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppColors.amber : AppColors.border),
      ),
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<T>(
                key: radioKey,
                value: value,
                focusNode: focusNode,
                activeColor: AppColors.amber,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                if (badge != null) _Badge(badge!),
                              ],
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            trailing!,
                          ],
                          if (number != null) ...[
                            const SizedBox(width: 10),
                            ExcludeSemantics(child: StepKbd('$number')),
                          ],
                        ],
                      ),
                      if (detail != null && detail!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail!,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (field != null) ...[
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.only(right: 34),
                          child: field!,
                        ),
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

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.amberTint,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.amber.withValues(alpha: 0.6)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.amber,
      ),
    ),
  );
}

/// The footer of the column (SPEC-059 R4): [left] at the start and [right]
/// at the end; stacked when they do not fit (large text).
class QuestionFooter extends StatelessWidget {
  const QuestionFooter({super.key, required this.left, required this.right});

  final List<Widget> left;
  final List<Widget> right;

  @override
  Widget build(BuildContext context) => OverflowBar(
    alignment: MainAxisAlignment.spaceBetween,
    overflowAlignment: OverflowBarAlignment.end,
    overflowSpacing: 8,
    children: [
      Row(mainAxisSize: MainAxisSize.min, children: left),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 8,
        children: right,
      ),
    ],
  );
}

/// Dashed outline of a "para depois" step (SPEC-028 R6).
class DashedBorder extends CustomPainter {
  const DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(6),
        ),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorder old) => old.color != color;
}

/// The excerpt of "Perguntas em aberto" around the question (SPEC-059 R7):
/// the line numbers, and the question's own lines marked with an amber rule
/// on the left.
class QuestionExcerpt extends StatelessWidget {
  const QuestionExcerpt({super.key, required this.excerpt});

  final QuestionExcerptLines excerpt;

  @override
  Widget build(BuildContext context) {
    final digits = '${excerpt.from + excerpt.lines.length}'.length;
    return Container(
      key: const ValueKey('spec-question-excerpt'),
      decoration: BoxDecoration(
        color: AppColors.backgroundSolid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, text) in excerpt.lines.indexed)
            _line(excerpt.from + i, text, digits),
        ],
      ),
    );
  }

  Widget _line(int no, String text, int digits) {
    final marked = excerpt.marked(no);
    const style = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12.5,
      height: 1.6,
      color: AppColors.text,
    );
    return Semantics(
      label: marked ? 'Linha $no, da pergunta: $text' : 'Linha $no: $text',
      excludeSemantics: true,
      child: Container(
        key: ValueKey(
          marked
              ? 'spec-question-excerpt-mark-$no'
              : 'spec-question-excerpt-line-$no',
        ),
        decoration: BoxDecoration(
          color: marked ? AppColors.amberTint : null,
          border: Border(
            left: BorderSide(
              color: marked ? AppColors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 10, right: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 8.0 * digits + 4,
              child: Text(
                '$no',
                textAlign: TextAlign.right,
                style: style.copyWith(color: ReviewColors.lineNumber),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text.isEmpty ? ' ' : text,
                style: marked
                    ? style
                    : style.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
