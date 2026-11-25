import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/claude/claude_event.dart' show RateLimit;
import '../../../../core/claude/usage_tracker.dart';
import '../../../../core/providers/agent_provider.dart';
import '../../../../ui/theme/tokens.dart';
import '../compare_run.dart';

/// Color of a side (A blue, B lilac), as in the canvas.
Color compareSideColor(String letter) =>
    letter == 'A' ? AppColors.blue : AppColors.lilac;

/// The letter of a side in a small square.
class CompareLetter extends StatelessWidget {
  const CompareLetter(this.letter, {super.key, this.size = 22});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: compareSideColor(letter),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontSize: size * .55,
            fontWeight: FontWeight.w700,
            color: AppColors.onAmber,
          ),
        ),
      ),
    );
  }
}

/// `Roda dois agentes ao mesmo tempo · janela de 5 h em 38% · semana em
/// 61%`, or the amber warning with the window at 80% or more (R4).
({String text, bool warn}) compareUsageLine(RateLimit? r, DateTime now) {
  const base = 'Roda dois agentes ao mesmo tempo';
  if (r == null) return (text: base, warn: false);
  final five = planWindowExpired(r.fiveHourResetsAt, now)
      ? null
      : r.fiveHourUtilization;
  final week = planWindowExpired(r.sevenDayResetsAt, now)
      ? null
      : r.sevenDayUtilization;
  String pct(double v) => '${(v * 100).round()}%';
  if (five != null && five >= .8) {
    final at = r.fiveHourResetsAt?.toLocal();
    final renews = at == null
        ? ''
        : ' e renova às ${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}';
    return (
      text:
          'A janela de 5 h está em ${pct(five)}$renews. Comparar pode '
          'esgotá-la.',
      warn: true,
    );
  }
  return (
    text: [
      base,
      if (five != null) 'janela de 5 h em ${pct(five)}',
      if (week != null) 'semana em ${pct(week)}',
    ].join(' · '),
    warn: false,
  );
}

/// The strip of the composer with sides A and B (R1–R4): model and mode
/// of each, ⇄, the shortcuts and the weight line.
class CompareBar extends ConsumerWidget {
  const CompareBar({
    super.key,
    required this.models,
    required this.a,
    required this.b,
    required this.onChanged,
  });

  /// The models of the conversation's provider.
  final List<String> models;
  final CompareChoice a;
  final CompareChoice b;
  final void Function(CompareChoice a, CompareChoice b) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = compareUsageLine(
      ref.watch(rateLimitProvider),
      DateTime.now(),
    );
    final sonnetOpus =
        a.mode == b.mode &&
        {a.model, b.model}.containsAll(const ['sonnet', 'opus']);
    final planAsk = a.model == b.model && {a.mode, b.mode}.length == 2;
    return Container(
      key: const ValueKey('compare-bar'),
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SideControls(
                letter: 'A',
                models: models,
                choice: a,
                onChanged: (c) => onChanged(c, b),
              ),
              Tooltip(
                message: 'Trocar os lados',
                child: IconButton(
                  key: const ValueKey('compare-swap'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: AppColors.textSecondary,
                  onPressed: () => onChanged(b, a),
                  icon: const Icon(Icons.swap_horiz),
                ),
              ),
              _SideControls(
                letter: 'B',
                models: models,
                choice: b,
                onChanged: (c) => onChanged(a, c),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Atalhos:',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              _Chip(
                key: const ValueKey('compare-sonnet-opus'),
                label: 'Sonnet × Opus',
                on: sonnetOpus,
                onTap: () => onChanged(
                  CompareChoice(model: 'sonnet', mode: a.mode),
                  CompareChoice(model: 'opus', mode: a.mode),
                ),
              ),
              _Chip(
                key: const ValueKey('compare-plan-ask'),
                label: 'Planejar × Perguntar',
                on: planAsk,
                onTap: () => onChanged(
                  a.copyWith(mode: PromptMode.plan),
                  a.copyWith(mode: PromptMode.ask),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    usage.warn ? Icons.warning_amber_rounded : Icons.schedule,
                    size: 13,
                    color: usage.warn
                        ? AppColors.amber
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      usage.text,
                      key: const ValueKey('compare-usage'),
                      style: TextStyle(
                        fontSize: 11,
                        color: usage.warn
                            ? AppColors.amber
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SideControls extends StatelessWidget {
  const _SideControls({
    required this.letter,
    required this.models,
    required this.choice,
    required this.onChanged,
  });

  final String letter;
  final List<String> models;
  final CompareChoice choice;
  final ValueChanged<CompareChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Lado $letter',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompareLetter(letter),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            key: ValueKey('compare-model-$letter'),
            tooltip: 'Modelo do lado $letter',
            color: AppColors.surfaceRaisedSolid,
            position: PopupMenuPosition.over,
            onSelected: (m) => onChanged(choice.copyWith(model: m)),
            itemBuilder: (_) => [
              for (final m in models)
                PopupMenuItem(
                  key: ValueKey('compare-model-$letter-$m'),
                  value: m,
                  height: 34,
                  child: Text(
                    compareModelLabel(m),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    compareModelLabel(choice.model),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.expand_more,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in PromptMode.selectable)
                  _ModeOption(
                    letter: letter,
                    mode: m,
                    on: m == choice.mode,
                    onTap: compareModes.contains(m)
                        ? () => onChanged(choice.copyWith(mode: m))
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.letter,
    required this.mode,
    required this.on,
    required this.onTap,
  });

  final String letter;
  final PromptMode mode;
  final bool on;

  /// Null = disabled (Editar, R3).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final child = Material(
      color: on ? AppColors.amberTint : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: ValueKey('compare-mode-$letter-${mode.name}'),
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            mode.label,
            style: TextStyle(
              fontSize: 12,
              decoration: off ? TextDecoration.lineThrough : null,
              color: on
                  ? AppColors.amber
                  : off
                  ? AppColors.textMuted
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
    return off
        ? Tooltip(
            key: ValueKey('compare-edit-hint-$letter'),
            message: compareEditHint,
            child: Semantics(
              enabled: false,
              label: '${mode.label}, indisponível: $compareEditHint',
              child: child,
            ),
          )
        : Semantics(selected: on, button: true, child: child);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? AppColors.amberTint : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: on ? SessionColors.approvalBorder : AppColors.border,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: on ? AppColors.amber : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
