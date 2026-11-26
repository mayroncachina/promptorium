import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/claude/run_prefs.dart';
import '../../../../core/claude/usage_tracker.dart';
import '../../../../core/codex/codex_probe.dart' show CodexModelInfo;
import '../../../../core/providers/agent_provider.dart';
import '../../../../core/providers/capabilities.dart';
import '../../../../core/providers/provider_preferences.dart';
import '../../../../core/providers/quota_source.dart';
import '../../../../data/providers.dart';
import '../../../../ui/providers/provider_logos.dart';
import '../../../../ui/shell/navigation.dart';
import '../../../../ui/theme/tokens.dart';
import '../../../sessions/handoff/session_summary.dart' show providerWords;
import '../../../settings/settings_sections.dart';
import '../compare_controller.dart';
import '../compare_handoff.dart';
import '../compare_run.dart';
import '../compare_weight.dart' show compareTokens;

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

/// The weight line (R4; SPEC-108 R5): the windows of each provider
/// involved, with their real durations, and the amber warnings of the ones
/// at 80% or more, with the provider's name.
({String text, String? warning}) compareUsageLine(
  Map<String, QuotaSnapshot?> quotas,
  DateTime now,
) {
  String pct(double v) => '${(v * 100).round()}%';
  final named = quotas.length > 1 || !quotas.keys.every(isClaudeCode);
  final parts = <String>[];
  final warnings = <String>[];
  for (final MapEntry(key: provider, value: snapshot) in quotas.entries) {
    final r = UsageReading.ofSnapshot(snapshot);
    final name = compareProviderLabel(provider);
    final windows = [
      if (r?.five case final v? when !planWindowExpired(r!.fiveResetsAt, now))
        (label: compareWindowLabel(r.fiveMinutes), used: v, at: r.fiveResetsAt),
      if (r?.week case final v? when !planWindowExpired(r!.weekResetsAt, now))
        (label: compareWindowLabel(r.weekMinutes), used: v, at: r.weekResetsAt),
    ];
    if (windows.isEmpty) {
      if (named) parts.add('$name · sem leitura');
      continue;
    }
    if (named) parts.add(name);
    for (final w in windows) {
      parts.add('${w.label} em ${pct(w.used)}');
      if (w.used < .8) continue;
      final at = w.at?.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      final renews = at == null
          ? ''
          : at.difference(now).inHours < 24
          ? ' e renova às ${two(at.hour)}:${two(at.minute)}'
          : ' e renova em ${two(at.day)}/${two(at.month)}';
      warnings.add('A ${w.label} do $name está em ${pct(w.used)}$renews.');
    }
  }
  const base = 'Roda dois agentes ao mesmo tempo';
  return (
    text: [base, ...parts].join(' · '),
    warning: warnings.isEmpty
        ? null
        : '${warnings.join(' ')} Comparar pode esgotá-la'
              '${warnings.length > 1 ? 's' : ''}.',
  );
}

/// The efforts a side offers: the Claude levels, or the ones `model/list`
/// says the Codex model accepts. The current one always stays listed.
List<String> compareEfforts(
  String provider,
  String model,
  CodexModelsCache? codex, {
  String? current,
}) {
  final all = isClaudeCode(provider)
      ? ProviderCapabilities.claude.efforts!
      : [defaultEffort, ...?codex?.byId(model)?.efforts];
  return [...all, if (current != null && !all.contains(current)) current];
}

/// The models a side offers: the Claude aliases of [claude], or the
/// `model/list` of the Codex (never fixed in the code, R1).
List<String> compareModels(
  String provider,
  List<String> claude,
  CodexModelsCache? codex, {
  String? current,
}) {
  final all = isClaudeCode(provider)
      ? claude
      : [
          'inherit',
          for (final m in codex?.models ?? const <CodexModelInfo>[]) m.id,
        ];
  return [...all, if (current != null && !all.contains(current)) current];
}

/// A side on the defaults of [provider] for conversations (R1, P4): its own
/// model and effort; an effort the model does not accept becomes the
/// provider's default.
CompareChoice compareDefaultChoice(
  WidgetRef ref,
  String provider,
  PromptMode mode,
) {
  final prefs = ref.read(runPrefsProvider);
  final settings = ref.read(appSettingsProvider);
  var model = providerModelFrom(
    prefs,
    settings,
    provider,
    RunKind.conversation,
  );
  if (model.isEmpty) model = 'inherit';
  var effort = providerEffortFrom(
    prefs,
    settings,
    provider,
    RunKind.conversation,
  );
  if (effort.isEmpty ||
      (model != 'inherit' &&
          !compareEfforts(
            provider,
            model,
            codexModelsCache(settings),
          ).contains(effort))) {
    effort = defaultEffort;
  }
  return CompareChoice(
    provider: provider,
    model: model,
    effort: effort,
    mode: mode,
  );
}

/// The strip of the composer with sides A and B (R1–R4): provider, model,
/// effort and mode of each (SPEC-108 R1), ⇄, the shortcuts, what a side
/// without the session receives and the weight line.
class CompareBar extends ConsumerWidget {
  const CompareBar({
    super.key,
    required this.models,
    required this.a,
    required this.b,
    required this.onChanged,
    this.conversationProvider = 'claude',
    this.handoffLetters = const [],
    this.handoff,
    this.sameHandoff = false,
    this.onSameHandoff,
    this.onShowHandoff,
  });

  /// The models of the Claude Code.
  final List<String> models;
  final CompareChoice a;
  final CompareChoice b;
  final void Function(CompareChoice a, CompareChoice b) onChanged;

  /// Provider of the conversation (A of "Claude × Codex").
  final String conversationProvider;

  /// Sides that start from the package (R4); empty = none.
  final List<String> handoffLetters;

  /// The package (null = being built).
  final CompareHandoff? handoff;

  /// "Mesmo resumo nos dois lados" (P1); null [onSameHandoff] hides it.
  final bool sameHandoff;
  final ValueChanged<bool>? onSameHandoff;
  final VoidCallback? onShowHandoff;

  void _openProviders(WidgetRef ref) {
    ref
        .read(selectedSettingsSectionProvider.notifier)
        .select(SettingsSection.providers);
    ref.read(navigationProvider.notifier).go(AppSection.settings);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = compareUsageLine({
      for (final p in {a.provider, b.provider})
        p: ref.watch(quotaSnapshotProvider(p)),
    }, DateTime.now());
    final codex = codexModelsCache(ref.watch(appSettingsProvider));
    final reasons = {
      for (final p in compareProviders)
        p: ref.watch(compareProviderReasonProvider(p)),
    };
    final claudeOnly = isClaudeCode(a.provider) && isClaudeCode(b.provider);
    final sonnetOpus =
        claudeOnly &&
        a.mode == b.mode &&
        {a.model, b.model}.containsAll(const ['sonnet', 'opus']);
    final planAsk =
        a.provider == b.provider &&
        a.model == b.model &&
        {a.mode, b.mode}.length == 2;
    final cross = a.provider != b.provider && a.mode == b.mode;
    final blocked = [for (final p in compareProviders) ?reasons[p]];
    Widget side(
      String letter,
      CompareChoice c,
      ValueChanged<CompareChoice> set,
    ) => _SideControls(
      letter: letter,
      models: compareModels(c.provider, models, codex, current: c.model),
      efforts: compareEfforts(c.provider, c.model, codex, current: c.effort),
      reasons: reasons,
      choice: c,
      onProvider: (p) => set(compareDefaultChoice(ref, p, c.mode)),
      onModel: (m) => set(
        c.copyWith(
          model: m,
          effort: compareEfforts(c.provider, m, codex).contains(c.effort)
              ? c.effort
              : defaultEffort,
        ),
      ),
      onChanged: set,
    );
    void claudeCodex() {
      final first = conversationProvider;
      final kept = [a, b].where((s) => s.provider == first).firstOrNull;
      onChanged(
        kept?.copyWith(mode: a.mode) ??
            compareDefaultChoice(ref, first, a.mode),
        compareDefaultChoice(ref, otherCompareProvider(first), a.mode),
      );
    }

    const small = TextStyle(fontSize: 11, color: AppColors.textSecondary);
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
              side('A', a, (c) => onChanged(c, b)),
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
              side('B', b, (c) => onChanged(a, c)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Atalhos:', style: small),
              _Chip(
                key: const ValueKey('compare-sonnet-opus'),
                label: 'Sonnet × Opus',
                on: sonnetOpus,
                onTap: () => onChanged(
                  CompareChoice(
                    model: 'sonnet',
                    effort: claudeOnly ? a.effort : defaultEffort,
                    mode: a.mode,
                  ),
                  CompareChoice(
                    model: 'opus',
                    effort: claudeOnly ? a.effort : defaultEffort,
                    mode: a.mode,
                  ),
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
              _Chip(
                key: const ValueKey('compare-claude-codex'),
                label: 'Claude × Codex',
                on: cross,
                reason: blocked.firstOrNull,
                onTap: blocked.isEmpty ? claudeCodex : null,
              ),
            ],
          ),
          if (blocked.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  blocked.first,
                  key: const ValueKey('compare-codex-reason'),
                  style: small,
                ),
                _Link(
                  key: const ValueKey('compare-open-providers'),
                  label: 'Abrir Provedores',
                  onTap: () => _openProviders(ref),
                ),
              ],
            ),
          ],
          if (handoffLetters.isNotEmpty) ...[
            const SizedBox(height: 8),
            _HandoffNotice(
              letters: handoffLetters,
              provider: conversationProvider,
              handoff: handoff,
              onShow: onShowHandoff,
            ),
          ],
          if (onSameHandoff case final toggle?) ...[
            const SizedBox(height: 4),
            MergeSemantics(
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Transform.scale(
                    scale: .7,
                    child: Switch(
                      key: const ValueKey('compare-same-handoff'),
                      value: sameHandoff,
                      onChanged: toggle,
                    ),
                  ),
                  const Text(
                    'Mesmo resumo nos dois lados',
                    style: TextStyle(fontSize: 12, color: AppColors.text),
                  ),
                  const Text(
                    'comparação mais justa; o lado da conversa também perde '
                    'a sessão',
                    style: small,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 13,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  usage.text,
                  key: const ValueKey('compare-usage'),
                  style: small.copyWith(
                    color: usage.warning == null ? null : AppColors.amber,
                  ),
                ),
              ),
            ],
          ),
          if (usage.warning case final warning?) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 13,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    warning,
                    key: const ValueKey('compare-usage-warning'),
                    style: small.copyWith(color: AppColors.amber),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "B começa sem a sessão do Claude…" (SPEC-108 R4).
class _HandoffNotice extends StatelessWidget {
  const _HandoffNotice({
    required this.letters,
    required this.provider,
    required this.handoff,
    required this.onShow,
  });

  final List<String> letters;
  final String provider;
  final CompareHandoff? handoff;
  final VoidCallback? onShow;

  @override
  Widget build(BuildContext context) {
    final both = letters.length > 1;
    final name = compareProviderLabel(provider);
    final size = handoff == null
        ? 'um resumo montado pelo app'
        : 'um resumo de ≈ ${compareTokens(handoff!.tokens)} tokens '
              '${handoff!.edited ? 'revisado por você' : 'montado pelo app'}';
    return Container(
      key: const ValueKey('compare-handoff-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.approvalBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: both
                        ? 'Os dois lados começam sem a sessão do $name: '
                        : '${letters.single} começa sem a sessão do $name: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: both
                        ? 'recebem $size.'
                        : 'recebe $size. Os dois lados não partem exatamente '
                              'do mesmo ponto.',
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 10),
          _Link(
            key: const ValueKey('compare-handoff-show'),
            label: both
                ? 'Ver o que os lados recebem'
                : 'Ver o que o ${letters.single} recebe',
            onTap: handoff == null ? null : onShow,
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            decoration: TextDecoration.underline,
            color: onTap == null ? AppColors.textMuted : AppColors.amber,
          ),
        ),
      ),
    ),
  );
}

/// One selector of a side (provider, model, effort).
class _Picker extends StatelessWidget {
  const _Picker({
    super.key,
    required this.tooltip,
    required this.itemKey,
    required this.values,
    required this.labelOf,
    required this.onSelected,
    required this.child,
  });

  final String tooltip;
  final String itemKey;
  final List<String> values;
  final String Function(String v) labelOf;
  final ValueChanged<String> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tooltip,
    color: AppColors.surfaceRaisedSolid,
    position: PopupMenuPosition.over,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final v in values)
        PopupMenuItem(
          key: ValueKey('$itemKey-$v'),
          value: v,
          height: 34,
          child: Text(labelOf(v), style: const TextStyle(fontSize: 12)),
        ),
    ],
    child: _PickerBox(child: child),
  );
}

class _PickerBox extends StatelessWidget {
  const _PickerBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(width: 4),
        const Icon(Icons.expand_more, size: 14, color: AppColors.textSecondary),
      ],
    ),
  );
}

class _SideControls extends StatelessWidget {
  const _SideControls({
    required this.letter,
    required this.models,
    required this.efforts,
    required this.reasons,
    required this.choice,
    required this.onProvider,
    required this.onModel,
    required this.onChanged,
  });

  final String letter;
  final List<String> models;
  final List<String> efforts;

  /// Why each provider cannot run (null = it can).
  final Map<String, String?> reasons;
  final CompareChoice choice;
  final ValueChanged<String> onProvider;
  final ValueChanged<String> onModel;
  final ValueChanged<CompareChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    const value = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    );
    return Semantics(
      container: true,
      label:
          'Lado $letter, ${compareProviderLabel(choice.provider)}, '
          '${compareModelLabel(choice.model, choice.provider)}',
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CompareLetter(letter),
          PopupMenuButton<String>(
            key: ValueKey('compare-provider-$letter'),
            tooltip: 'Provedor do lado $letter',
            color: AppColors.surfaceRaisedSolid,
            position: PopupMenuPosition.over,
            onSelected: (p) {
              if (p != choice.provider) onProvider(p);
            },
            itemBuilder: (_) => [
              for (final p in compareProviders)
                PopupMenuItem(
                  key: ValueKey('compare-provider-$letter-$p'),
                  value: p,
                  enabled: reasons[p] == null,
                  height: 36,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProviderChip(p, name: providerWords(p), dense: true),
                      if (reasons[p] case final reason?)
                        Text(
                          reason,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProviderChip(
                  choice.provider,
                  name: providerWords(choice.provider),
                ),
                const Icon(
                  Icons.expand_more,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          _Picker(
            key: ValueKey('compare-model-$letter'),
            tooltip: 'Modelo do lado $letter',
            itemKey: 'compare-model-$letter',
            values: models,
            labelOf: (m) => compareModelLabel(m, choice.provider),
            onSelected: onModel,
            child: Text(
              compareModelLabel(choice.model, choice.provider),
              style: value,
            ),
          ),
          _Picker(
            key: ValueKey('compare-effort-$letter'),
            tooltip: 'Esforço do lado $letter',
            itemKey: 'compare-effort-$letter',
            values: efforts,
            labelOf: _effortLabel,
            onSelected: (e) => onChanged(choice.copyWith(effort: e)),
            child: Text(_effortLabel(choice.effort), style: value),
          ),
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

/// `esforço padrão`, `medium`.
String _effortLabel(String e) =>
    e.isEmpty || e == defaultEffort ? 'esforço padrão' : e;

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
    this.reason,
  });

  final String label;
  final bool on;

  /// Null = disabled, for [reason] (SPEC-108 R2).
  final VoidCallback? onTap;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final chip = Material(
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
              color: on
                  ? AppColors.amber
                  : off
                  ? AppColors.textMuted
                  : AppColors.text,
            ),
          ),
        ),
      ),
    );
    if (!off) return Semantics(button: true, selected: on, child: chip);
    return Tooltip(
      message: reason ?? '',
      child: Semantics(
        button: true,
        enabled: false,
        label: '$label, indisponível${reason == null ? '' : ': $reason'}',
        child: ExcludeSemantics(child: chip),
      ),
    );
  }
}
