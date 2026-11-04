import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../board_rules.dart';
import '../step_decision.dart';
import '../step_gate.dart';
import 'spec_canvas.dart' show DashedBorderPainter;

/// Most options shown, and the row of "Outra resposta" after them.
const stepDecisionOtherRow = stepDecisionMaxOptions;

/// Most lines of the output of a failed check (R14).
const _gateLines = 3;

/// `n` of "Etapa n": `3` for `R3`, `3.1` for `R3.1`, the id itself for the
/// steps out of the requirements (`REV1`).
String stepNumber(String id) =>
    RegExp(r'^R(\d+(?:\.\d+)?)$').firstMatch(id)?.group(1) ?? id;

/// Icon of each kind of option: the label beside it says the same.
IconData stepDecisionKindIcon(StepDecisionKind kind) => switch (kind) {
  StepDecisionKind.answer => Icons.reply,
  StepDecisionKind.amend => Icons.edit_outlined,
  StepDecisionKind.split => Icons.call_split,
  StepDecisionKind.defer => Icons.schedule,
};

/// What a screen reader says of an option (R15).
String stepDecisionOptionLabel(
  int number,
  int total,
  StepDecisionOption option,
) {
  String clean(String text) =>
      text.endsWith('.') ? text.substring(0, text.length - 1) : text;
  return [
    'Opção $number de $total: ${clean(option.title)}',
    option.kind.label,
    if (option.consequence.isNotEmpty) clean(option.consequence),
    if (option.suggested) 'sugerida',
  ].join('. ');
}

/// A key in a text: `Esc`, `Ctrl+O`.
class StepKbd extends StatelessWidget {
  const StepKbd(this.text, {super.key, this.onAmber = false});

  final String text;

  /// Inside the primary button.
  final bool onAmber;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: onAmber
          ? AppColors.onAmber.withValues(alpha: .12)
          : AppColors.background,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: onAmber
            ? AppColors.onAmber.withValues(alpha: .35)
            : AppColors.border,
      ),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        height: 1.5,
        color: onAmber ? AppColors.onAmber : AppColors.textSecondary,
      ),
    ),
  );
}

/// One line of the opening sequence (R2): it rises 6 px and appears in
/// [AppMotion.base], starting [startMs] after the modal does.
class StepDecisionEnter extends StatelessWidget {
  const StepDecisionEnter({
    super.key,
    required this.sequence,
    required this.startMs,
    required this.totalMs,
    required this.child,
  });

  /// Runs from 0 to 1 in [totalMs]; at 1 from the start without animations.
  final Animation<double> sequence;
  final int startMs;
  final int totalMs;
  final Widget child;

  static const _rise = 6.0;

  @override
  Widget build(BuildContext context) {
    final end = startMs + AppMotion.base.inMilliseconds;
    final t = sequence.drive(
      CurveTween(
        curve: Interval(
          startMs / totalMs,
          end / totalMs,
          curve: AppMotion.enter,
        ),
      ),
    );
    return FadeTransition(
      opacity: t,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: t,
        child: child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _rise * (1 - t.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Number of an option row.
class _RowKey extends StatelessWidget {
  const _RowKey(this.number);

  final int number;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      '$number',
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.text,
      ),
    ),
  );
}

/// The confirmation of a chosen row (R5): icon and text, not only colour.
class _Chosen extends StatelessWidget {
  const _Chosen();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.check_circle, size: 14, color: AppColors.teal),
      SizedBox(width: 4),
      Text(
        'Escolhida',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.teal,
        ),
      ),
    ],
  );
}

/// A line of the list of options (R5), a radio of the group (R15).
class StepDecisionOptionRow extends StatelessWidget {
  const StepDecisionOptionRow({
    super.key,
    required this.number,
    required this.total,
    required this.option,
    required this.focusNode,
    required this.chosen,
    required this.onTap,
    required this.onFocusChange,
  });

  final int number;
  final int total;
  final StepDecisionOption option;
  final FocusNode focusNode;
  final bool chosen;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocusChange;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return Semantics(
          container: true,
          excludeSemantics: true,
          inMutuallyExclusiveGroup: true,
          checked: chosen,
          focusable: true,
          focused: focused,
          label: stepDecisionOptionLabel(number, total, option),
          onTap: onTap,
          child: Material(
            color: focused ? SessionColors.selectedBg : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: chosen
                    ? AppColors.teal
                    : focused
                    ? ReviewColors.lineNumber
                    : AppColors.border,
              ),
            ),
            child: InkWell(
              focusNode: focusNode,
              onFocusChange: onFocusChange,
              onTap: onTap,
              borderRadius: radius,
              focusColor: Colors.transparent,
              hoverColor: SessionColors.selectedBg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RowKey(number),
                    const SizedBox(width: 10),
                    Expanded(child: _text()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _text() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            option.title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          if (option.suggested) const _Suggested(),
          if (chosen) const _Chosen(),
        ],
      ),
      const SizedBox(height: 3),
      Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  stepDecisionKindIcon(option.kind),
                  size: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextSpan(text: option.kind.label),
            if (option.consequence.isNotEmpty) ...[
              const TextSpan(
                text: '  ·  ',
                style: TextStyle(color: AppColors.textDisabled),
              ),
              TextSpan(text: option.consequence),
            ],
          ],
        ),
      ),
    ],
  );
}

class _Suggested extends StatelessWidget {
  const _Suggested();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.amber),
    ),
    child: const Text(
      'Sugerida',
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: AppColors.amber,
      ),
    ),
  );
}

/// "Outra resposta" (R5): the row of key `5`, which opens a free text field.
class StepDecisionOtherRow extends StatelessWidget {
  const StepDecisionOtherRow({
    super.key,
    required this.focusNode,
    required this.fieldFocus,
    required this.controller,
    required this.open,
    required this.chosen,
    required this.onOpen,
    required this.onChanged,
    required this.onFocusChange,
  });

  final FocusNode focusNode;
  final FocusNode fieldFocus;
  final TextEditingController controller;
  final bool open;
  final bool chosen;
  final VoidCallback onOpen;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onFocusChange;

  static const _number = stepDecisionOtherRow + 1;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(
        radius: 10,
        color: AppColors.border,
      ),
      child: open ? _field() : _closed(radius),
    );
  }

  Widget _closed(BorderRadius radius) => ListenableBuilder(
    listenable: focusNode,
    builder: (context, _) => Semantics(
      container: true,
      excludeSemantics: true,
      inMutuallyExclusiveGroup: true,
      checked: false,
      focusable: true,
      focused: focusNode.hasFocus,
      label: 'Opção $_number: outra resposta',
      onTap: onOpen,
      child: Material(
        color: focusNode.hasFocus
            ? SessionColors.selectedBg
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          focusNode: focusNode,
          onFocusChange: onFocusChange,
          onTap: onOpen,
          borderRadius: radius,
          focusColor: Colors.transparent,
          hoverColor: SessionColors.selectedBg,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RowKey(_number),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Outra resposta',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Escreva o que o agente deve fazer.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _field() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.amber),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RowKey(_number),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      'Outra resposta',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    if (chosen) ...[const SizedBox(width: 8), const _Chosen()],
                  ],
                ),
                const SizedBox(height: 6),
                Focus(
                  skipTraversal: true,
                  canRequestFocus: false,
                  onFocusChange: onFocusChange,
                  child: Semantics(
                    label: 'Outra resposta',
                    child: TextField(
                      key: const ValueKey('step-decision-other-input'),
                      controller: controller,
                      focusNode: fieldFocus,
                      onChanged: onChanged,
                      minLines: 2,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Escreva o que o agente deve fazer.',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        enabledBorder: border,
                        focusedBorder: border,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Breathes while the options are generated: the only continuous motion of
/// the modal, and it stands still when the system asks for less (R13, R14).
class StepDecisionShimmer extends StatefulWidget {
  const StepDecisionShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<StepDecisionShimmer> createState() => _StepDecisionShimmerState();
}

class _StepDecisionShimmerState extends State<StepDecisionShimmer>
    with SingleTickerProviderStateMixin {
  static const _half = Duration(milliseconds: 700);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _half,
    value: 1,
  );
  late final Animation<double> _opacity = _c.drive(
    Tween<double>(
      begin: .55,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeInOut)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.animate(context)) {
      _c
        ..stop()
        ..value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FadeTransition(opacity: _opacity, child: widget.child),
  );
}

class _Bone extends StatelessWidget {
  const _Bone({required this.width, this.height = 8});

  /// Share of the width of the parent.
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: width,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: SessionColors.selectedBorder,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

/// The summary while it is generated.
class StepDecisionSummarySkeleton extends StatelessWidget {
  const StepDecisionSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) => const StepDecisionShimmer(
    key: ValueKey('step-decision-skeleton-summary'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 4),
        _Bone(width: .9),
        SizedBox(height: 8),
        _Bone(width: .65),
        SizedBox(height: 4),
      ],
    ),
  );
}

/// The option rows while they are generated.
class StepDecisionRowsSkeleton extends StatelessWidget {
  const StepDecisionRowsSkeleton({super.key});

  static const _rows = [(.82, .57), (.7, .45), (.76, .51)];

  @override
  Widget build(BuildContext context) => StepDecisionShimmer(
    key: const ValueKey('step-decision-skeleton-rows'),
    child: Column(
      children: [
        for (final (title, line) in _rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: SessionColors.selectedBorder,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bone(width: title),
                      const SizedBox(height: 6),
                      _Bone(width: line, height: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// "A IA está lendo a sessão…" with the time since it was mounted (R14).
class StepDecisionGenerating extends StatefulWidget {
  const StepDecisionGenerating({super.key});

  @override
  State<StepDecisionGenerating> createState() => _StepDecisionGeneratingState();
}

class _StepDecisionGeneratingState extends State<StepDecisionGenerating> {
  late final Timer _timer;
  var _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.auto_awesome, size: 14, color: AppColors.lilac),
      const SizedBox(width: 8),
      Semantics(
        liveRegion: true,
        child: const Text(
          'A IA está lendo a sessão…',
          key: ValueKey('step-decision-generating'),
          style: TextStyle(fontSize: 13, color: AppColors.text),
        ),
      ),
      const SizedBox(width: 6),
      ExcludeSemantics(
        child: Text(
          '$_seconds s',
          key: const ValueKey('step-decision-elapsed'),
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      const Flexible(
        child: Text(
          ' · fechar cancela',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    ],
  );
}

/// "Falha ao gerar" (R14).
class StepDecisionFailure extends StatelessWidget {
  const StepDecisionFailure({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SessionColors.delBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.stopBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Não consegui propor opções: $reason',
              key: const ValueKey('step-decision-failure'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// "O que aconteceu" (R3): the summary of the AI, or its skeleton.
class StepDecisionSummary extends StatelessWidget {
  const StepDecisionSummary({
    super.key,
    required this.summary,
    required this.loading,
  });

  final String summary;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: const BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.all(Radius.circular(8)),
      border: Border(left: BorderSide(color: AppColors.amber, width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'O que aconteceu',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        if (loading)
          const StepDecisionSummarySkeleton()
        else
          Text(
            summary,
            key: const ValueKey('step-decision-summary'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
          ),
      ],
    ),
  );
}

/// "Verificação falhou" (R14): the report itself, so it needs no generation.
class StepDecisionGateSummary extends StatelessWidget {
  const StepDecisionGateSummary({
    super.key,
    required this.stepId,
    required this.report,
  });

  final String stepId;
  final GateReport report;

  @override
  Widget build(BuildContext context) {
    final check = report.failures.firstOrNull;
    final attempts = report.attempt + 1;
    final tail = check == null ? '' : tailLines(check.output, _gateLines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verificação do ${parentOf(stepId)} falhou · '
          '$attempts de $attempts tentativas',
          key: const ValueKey('step-decision-gate-title'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          key: const ValueKey('step-decision-gate'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: SessionColors.terminalPanel,
            borderRadius: BorderRadius.all(Radius.circular(6)),
            border: Border(left: BorderSide(color: AppColors.red, width: 3)),
          ),
          child: Text(
            [
              if (check != null) '\$ ${check.command ?? check.label}',
              if (tail.trim().isNotEmpty) tail.trimRight(),
            ].join('\n'),
            // The command, the "…" of a cut output and the lines.
            maxLines: _gateLines + 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              height: 1.5,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}
