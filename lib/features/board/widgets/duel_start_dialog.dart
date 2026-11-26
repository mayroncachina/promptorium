import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/run_prefs.dart';
import '../../../core/providers/agent_registry.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../data/providers.dart';
import '../../../ui/providers/provider_logos.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../sessions/handoff/session_summary.dart' show providerWords;
import '../../sessions/widgets/session_style.dart';
import '../duel_attempt.dart';
import '../orchestrator/step_plan.dart' show runsInAuto;
import '../spec_run_provider.dart';

/// "Executar em dobro (A/B)" asks first (SPEC-108 R11): each attempt picks
/// its provider, model and effort; the default is the current configuration
/// of both. Null = cancelled.
Future<DuelAttempts?> showDuelStartDialog(BuildContext context, Spec spec) =>
    showAppDialog<DuelAttempts>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => DuelStartDialog(spec: spec),
    );

/// Provider the spec runs with now (the one a plain duel uses).
final duelCurrentProvider = FutureProvider.autoDispose.family<String, int>((
  ref,
  specId,
) async {
  final settings = ref.read(appSettingsProvider);
  final recorded = recordedSpecProvider(settings, specId);
  if (recorded != null) return recorded;
  final rows = await ref.read(specStepsRepoProvider).bySpec(specId);
  if (runsInAuto(rows)) return ProviderCapabilities.claude.providerId;
  final sessions = await ref.read(sessionsRepoProvider).bySpec(specId);
  final spec = await ref.read(specsRepoProvider).getById(specId);
  return specRunProviderFor(
    settings,
    specId,
    last: sessions.lastOrNull,
    workspaceId: spec?.workspaceId,
    flows: ref.read(providerFlowsProvider),
  );
});

/// Why [provider] cannot run an attempt (null = it can). Without the
/// sandbox the Codex still runs: the attempt has its own worktree
/// (decision 15).
final duelProviderReasonProvider = Provider.family<String?, String>((
  ref,
  provider,
) {
  final p = ref
      .watch(agentProvidersProvider)
      .where((p) => p.id == provider)
      .firstOrNull;
  final name = p?.displayName ?? providerWords(provider);
  if (p == null) return '$name não está registrado.';
  final flows = ref.watch(providerFlowsProvider);
  if (!flows.allows(provider, AppFlow.runSpec)) {
    return flows.refusal(provider, name, AppFlow.runSpec);
  }
  if (isClaudeCode(provider)) return null;
  final a = ref.watch(providerAvailabilityProvider(provider)).value;
  if (a == null) return 'Verificando o $name…';
  return switch (a.status) {
    ProviderStatus.ready => null,
    ProviderStatus.missing => '$name não está instalado.',
    ProviderStatus.loginRequired => '$name sem login: rode codex login.',
    _ => '$name: ${a.message}',
  };
});

class DuelStartDialog extends ConsumerStatefulWidget {
  const DuelStartDialog({super.key, required this.spec});

  final Spec spec;

  @override
  ConsumerState<DuelStartDialog> createState() => _DuelStartDialogState();
}

class _DuelStartDialogState extends ConsumerState<DuelStartDialog> {
  DuelAttempt? _a;
  DuelAttempt? _b;

  static const _providers = ['claude', 'codex'];

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(duelCurrentProvider(widget.spec.id)).value;
    final reasons = {
      for (final p in _providers) p: ref.watch(duelProviderReasonProvider(p)),
    };
    final base = DuelAttempt(provider: current ?? 'claude');
    final a = _a ?? base, b = _b ?? base;
    final same = a == base && b == base;
    final cross = a.provider != b.provider;
    final blocked = [for (final p in _providers) ?reasons[p]];
    final problem = [
      for (final p in {a.provider, b.provider}) ?reasons[p],
    ].firstOrNull;
    const muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Dialog(
      key: const ValueKey('duel-start-dialog'),
      backgroundColor: AppColors.panelSolid,
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Comparar A/B · ${widget.spec.code}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Duas tentativas da próxima etapa, cada uma na sua worktree '
                'temporária.',
                style: muted,
              ),
              const SizedBox(height: 12),
              _attempt('A', a, base, reasons, (v) => setState(() => _a = v)),
              const SizedBox(height: 8),
              _attempt('B', b, base, reasons, (v) => setState(() => _b = v)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip(
                    'Configuração atual',
                    keyName: 'duel-same',
                    on: same,
                    onTap: () => setState(() => _a = _b = null),
                  ),
                  _chip(
                    'Claude × Codex',
                    keyName: 'duel-claude-codex',
                    on: cross,
                    reason: blocked.firstOrNull,
                    onTap: blocked.isNotEmpty
                        ? null
                        : () => setState(() {
                            _a = const DuelAttempt(provider: 'claude');
                            _b = const DuelAttempt(provider: 'codex');
                          }),
                  ),
                ],
              ),
              if (blocked.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  blocked.first,
                  key: const ValueKey('duel-codex-reason'),
                  style: muted.copyWith(fontSize: 11),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallButton(
                    key: const ValueKey('duel-start-cancel'),
                    label: 'Cancelar',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: problem ?? '',
                    child: AmberButton(
                      key: const ValueKey('duel-start'),
                      label: 'Começar as duas',
                      onTap: problem != null || current == null
                          ? null
                          : () => Navigator.of(context).pop((a: a, b: b)),
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

  Widget _attempt(
    String letter,
    DuelAttempt v,
    DuelAttempt base,
    Map<String, String?> reasons,
    ValueChanged<DuelAttempt> set,
  ) {
    final settings = ref.watch(appSettingsProvider);
    final codex = !isClaudeCode(v.provider);
    final claude = ref
        .watch(agentProvidersProvider)
        .where((p) => p.id == ProviderCapabilities.claude.providerId)
        .firstOrNull;
    final models = codex
        ? codexCatalogModels(settings)
        : [
            for (final m in claude?.models ?? const <String>[])
              if (m != 'inherit') m,
          ];
    final efforts = codex
        ? codexModelEfforts(
            settings,
            codexRunModel(settings, requested: v.model),
          )
        : ProviderCapabilities.claude.efforts!;
    final noSandbox =
        codex &&
        ref
                .watch(providerAvailabilityProvider(v.provider))
                .value
                ?.sandboxWarning !=
            null;
    String modelLabel(String? m) => m == null
        ? (v.provider == base.provider
              ? 'modelo da etapa'
              : codex
              ? '${codexRunModel(settings)} (padrão)'
              : 'modelo padrão')
        : codex
        ? m
        : m[0].toUpperCase() + m.substring(1);
    String effortLabelOf(String? e) => e != null && e != defaultEffort
        ? e
        : e == null && v.provider == base.provider
        ? 'esforço da etapa'
        : 'esforço padrão';
    Widget menu<T>(
      String keyName,
      String tooltip,
      List<T> values,
      String Function(T v) label,
      String shown,
      ValueChanged<T> pick,
    ) => PopupMenuButton<int>(
      key: ValueKey('$keyName-$letter'),
      tooltip: tooltip,
      color: AppColors.surfaceRaisedSolid,
      onSelected: (i) => pick(values[i]),
      itemBuilder: (_) => [
        for (var i = 0; i < values.length; i++)
          PopupMenuItem(
            key: ValueKey('$keyName-$letter-${values[i] ?? 'atual'}'),
            value: i,
            height: 34,
            child: Text(label(values[i]), style: const TextStyle(fontSize: 12)),
          ),
      ],
      child: Container(
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
            Text(shown, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Tentativa $letter, ${providerWords(v.provider)}',
      child: Container(
        key: ValueKey('duel-attempt-$letter'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              letter,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: letter == 'A' ? AppColors.blue : AppColors.lilac,
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('duel-provider-$letter'),
              tooltip: 'Provedor da tentativa $letter',
              color: AppColors.surfaceRaisedSolid,
              onSelected: (p) {
                if (p != v.provider) set(DuelAttempt(provider: p));
              },
              itemBuilder: (_) => [
                for (final p in _providers)
                  PopupMenuItem(
                    key: ValueKey('duel-provider-$letter-$p'),
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
                  ProviderChip(v.provider, name: providerWords(v.provider)),
                  const Icon(
                    Icons.expand_more,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            menu<String?>(
              'duel-model',
              'Modelo da tentativa $letter',
              [null, ...models],
              modelLabel,
              modelLabel(v.model),
              (m) => set(DuelAttempt(provider: v.provider, model: m)),
            ),
            menu<String?>(
              'duel-effort',
              'Esforço da tentativa $letter',
              [
                null,
                for (final e in efforts)
                  if (e != defaultEffort) e,
              ],
              effortLabelOf,
              effortLabelOf(v.effort),
              (e) => set(
                DuelAttempt(provider: v.provider, model: v.model, effort: e),
              ),
            ),
            Text(
              !codex
                  ? 'modo da etapa'
                  : noSandbox
                  ? 'sem sandbox: YOLO, só no worktree da tentativa'
                  : 'modo da etapa · escreve só no worktree',
              key: ValueKey('duel-access-$letter'),
              style: TextStyle(
                fontSize: 11,
                color: noSandbox ? AppColors.amber : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    String label, {
    required String keyName,
    required bool on,
    required VoidCallback? onTap,
    String? reason,
  }) => Tooltip(
    message: onTap == null ? reason ?? '' : '',
    child: SmallButton(
      key: ValueKey(keyName),
      label: label,
      height: 28,
      color: onTap == null
          ? AppColors.textMuted
          : on
          ? AppColors.amber
          : AppColors.text,
      border: on ? AppColors.amber : AppColors.border,
      background: on ? AppColors.amberTint : AppColors.panel,
      onTap: onTap,
    ),
  );
}
