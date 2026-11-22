import 'package:flutter/material.dart';

import '../../core/providers/quota_source.dart';
import '../../features/sessions/widgets/session_style.dart' show SmallButton;
import '../shell/quota_detail.dart' show quotaWhen;
import '../theme/tokens.dart';

/// The Codex hit its limit (SPEC-097 R7): a new run warns before it starts,
/// with the explicit choice of the Claude Code. The app never switches by
/// itself (decisão 4).
class QuotaLimitNotice extends StatelessWidget {
  const QuotaLimitNotice({
    super.key,
    required this.limit,
    required this.onUseClaude,
    required this.onWait,
    required this.onStartAnyway,
    this.plan,
    this.what = 'sessão',
  });

  final QuotaLimit limit;
  final String? plan;

  /// "sessão", "conversa"…
  final String what;
  final VoidCallback onUseClaude;
  final VoidCallback onWait;
  final VoidCallback onStartAnyway;

  @override
  Widget build(BuildContext context) {
    final w = limit.window;
    final at = limit.resetsAt;
    final window = switch (w?.minutes) {
      10080 => 'Semana',
      300 => 'Janela de 5 h',
      _ => quotaWindowTitle(w?.minutes),
    };
    final planName = quotaPlanName(plan);
    final detail = [
      if (w?.usedPercent != null)
        '$window em ${w!.usedPercent!.round()}% (${limit.words}'
            '${planName == null ? '' : ' $planName'}).'
      else
        '${limit.words[0].toUpperCase()}${limit.words.substring(1)}.',
      if (at != null) 'Renova ${quotaWhen(at, DateTime.now())}.',
      'Uma $what agora falharia no primeiro turno.',
    ].join(' ');
    return Padding(
      key: const ValueKey('quota-limit-notice'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.highlight_off, size: 16, color: AppColors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'O Codex atingiu o ${limit.words}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              SmallButton(
                key: const ValueKey('quota-limit-use-claude'),
                label: 'Usar o Claude Code nesta $what',
                onTap: onUseClaude,
              ),
              SmallButton(
                key: const ValueKey('quota-limit-wait'),
                label: 'Esperar a renovação',
                onTap: onWait,
              ),
              SmallButton(
                key: const ValueKey('quota-limit-start'),
                label: 'Iniciar mesmo assim',
                onTap: onStartAnyway,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'O app não troca de provedor sozinho: a escolha é sua e vale só '
            'para esta $what.',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
