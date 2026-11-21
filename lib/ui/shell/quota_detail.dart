import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/usage_poller.dart';
import '../../core/claude/usage_tracker.dart' show planWindowExpired;
import '../../core/codex/codex_cli.dart';
import '../../core/providers/agent_event.dart' show QuotaWindow;
import '../../core/providers/provider_preferences.dart';
import '../../core/providers/quota_source.dart';
import '../providers/provider_logos.dart';
import '../theme/tokens.dart';
import '../widgets/app_dialog.dart';
import '../../features/sessions/widgets/session_style.dart' show SmallButton;

/// "Cota dos planos" (SPEC-097 R6): Claude Code and Codex side by side —
/// plan, windows with the renewal, credits, other buckets and when each was
/// read, with "Atualizar". Only the providers found on the machine (P4).
Future<void> showQuotaDetail(BuildContext context) => showAppDialog<void>(
  context: context,
  barrierColor: Colors.black26,
  builder: (context) => const Align(
    alignment: Alignment.bottomRight,
    child: Padding(
      padding: EdgeInsets.only(right: 12, bottom: 36),
      child: QuotaDetail(),
    ),
  ),
);

String _two(int v) => v.toString().padLeft(2, '0');

/// "às 16:40" today; "seg. 09:00" on another day.
String quotaWhen(DateTime t, DateTime now) {
  final l = t.toLocal(), n = now.toLocal();
  final hm = '${_two(l.hour)}:${_two(l.minute)}';
  if (l.year == n.year && l.month == n.month && l.day == n.day) {
    return 'às $hm';
  }
  const days = ['seg.', 'ter.', 'qua.', 'qui.', 'sex.', 'sáb.', 'dom.'];
  return '${days[l.weekday - 1]} $hm';
}

class QuotaDetail extends ConsumerWidget {
  const QuotaDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeAgentProvider);
    // P4: the Codex only when installed (or already read once).
    final codexFound =
        ref.watch(codexCliInfoProvider).value != null ||
        ref.watch(quotaSnapshotProvider('codex')) != null;
    final providers = ['claude', if (codexFound) 'codex'];
    return Material(
      key: const ValueKey('quota-detail'),
      color: AppColors.panelSolid,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: providers.length == 1 ? 360 : 720,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Cota dos planos',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  'nenhuma leitura gasta turno',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < providers.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _ProviderCard(
                        provider: providers[i],
                        active: providers[i] == active,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends ConsumerStatefulWidget {
  const _ProviderCard({required this.provider, required this.active});

  final String provider;
  final bool active;

  @override
  ConsumerState<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends ConsumerState<_ProviderCard> {
  bool _reading = false;

  Future<void> _refresh() async {
    setState(() => _reading = true);
    try {
      if (widget.provider == 'codex') {
        await ref.read(codexQuotaProvider.notifier).refresh();
      } else {
        await ref.read(usagePollerProvider).refresh();
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  static const _muted = TextStyle(fontSize: 11, color: AppColors.textMuted);
  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    color: AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final s = ref.watch(quotaSnapshotProvider(p));
    final now = DateTime.now();
    final codex = p == 'codex';
    final plan = quotaPlanName(s?.main.plan);
    final limit = codex ? s?.limit(now) : null;
    final read = s?.readAt;
    return Container(
      key: ValueKey('quota-card-$p'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(
          color: limit != null ? AppColors.red : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            spacing: 6,
            children: [
              ProviderChip(p, dense: true),
              Flexible(
                child: Text(
                  codex ? 'Codex' : 'Claude Code',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.active) const _Pill('ativo', color: AppColors.teal),
              const Spacer(),
              if (plan != null)
                Flexible(
                  flex: 2,
                  child: _Pill(plan, key: ValueKey('quota-plan-$p')),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (s == null || !s.hasReading)
            Text(
              'sem leitura ainda',
              key: ValueKey('quota-empty-$p'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            )
          else ...[
            if (limit != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  [
                    'limite atingido · ${limit.words}',
                    if (limit.resetsAt != null)
                      'renova ${quotaWhen(limit.resetsAt!, now)}',
                  ].join(' · '),
                  key: const ValueKey('quota-limit'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final w in s.main.windows) _window(p, w, now),
            if (s.main.credits case final c?) ...[
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Créditos',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    _credits(c),
                    key: ValueKey('quota-credits-$p'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            for (final o in s.others)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  key: ValueKey('quota-bucket-${o.id}'),
                  children: [
                    Expanded(
                      child: Text(
                        '${o.label} · limite próprio',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mono.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    Text(
                      o.windows.firstOrNull?.usedPercent == null
                          ? '—'
                          : '${o.windows.first.usedPercent!.round()}%',
                      style: _mono,
                    ),
                  ],
                ),
              ),
          ],
          if (s?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'cota indisponível: ${s!.error}',
                key: ValueKey('quota-error-$p'),
                style: const TextStyle(fontSize: 11, color: AppColors.red),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  read == null
                      ? 'nunca lido'
                      : 'lido ${quotaWhen(read, now)}${_via(s?.via)}',
                  key: ValueKey('quota-read-$p'),
                  style: _muted,
                ),
              ),
              SmallButton(
                key: ValueKey('quota-refresh-$p'),
                label: _reading ? 'Lendo…' : 'Atualizar',
                height: 26,
                onTap: _reading ? null : _refresh,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _via(QuotaVia? v) => switch (v) {
    QuotaVia.usage => ' por /usage',
    QuotaVia.update => ' · atualizado durante a execução',
    QuotaVia.reply => ' · na resposta do Claude',
    QuotaVia.read || null => '',
  };

  static String _credits(QuotaCredits c) {
    if (c.unlimited == true) return 'ilimitados';
    if (c.hasCredits == true) {
      return c.balance == null ? 'com créditos' : 'saldo ${c.balance}';
    }
    return 'sem créditos extras';
  }

  Widget _window(String p, QuotaWindow w, DateTime now) {
    final expired = planWindowExpired(w.resetsAt, now);
    final pct = expired ? null : w.usedPercent;
    final v = ((pct ?? 0) / 100).clamp(0.0, 1.0);
    final color = pct == null
        ? AppColors.border
        : pct >= 100
        ? AppColors.red
        : pct >= 80
        ? AppColors.amber
        : (w.minutes == 10080 ? AppColors.blue : AppColors.teal);
    final title = quotaWindowTitle(w.minutes);
    return Padding(
      key: ValueKey('quota-window-$p-${w.minutes ?? w.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 12)),
              ),
              Text(pct == null ? '—' : '${pct.round()}%', style: _mono),
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            label: pct == null
                ? '$title: sem dados'
                : '$title: ${pct.round()}% usado',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.border),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: v,
                      child: ColoredBox(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            expired
                ? 'renovada · atualiza na próxima leitura'
                : w.resetsAt == null
                ? ''
                : 'renova ${quotaWhen(w.resetsAt!, now)}',
            style: _muted,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color ?? AppColors.border),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: color ?? AppColors.textSecondary),
    ),
  );
}
