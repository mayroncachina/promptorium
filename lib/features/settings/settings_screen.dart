import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/session_style.dart';
import 'automations_view.dart';
import 'backups_view.dart';

/// Models offered as defaults (`inherit` = the CLI's default model).
const _models = [
  ('sonnet', 'Sonnet'),
  ('opus', 'Opus'),
  ('haiku', 'Haiku'),
  ('fable', 'Fable'),
  ('inherit', 'Padrão do CLI'),
];

/// Configurações → Consumo: default model and `--effort` per kind of run and
/// the `--autocompact` window ([RunPrefs], stored in `app_settings`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runPrefsProvider);
    final settings = ref.read(appSettingsProvider.notifier);
    return ColoredBox(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Configurações',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    SmallButton(
                      key: const ValueKey('settings-reset'),
                      label: 'Restaurar padrões',
                      onTap: () async {
                        for (final k in RunKind.values) {
                          await settings.remove(
                            AppSettingKeys.runModel(k.name),
                          );
                          await settings.remove(
                            AppSettingKeys.runEffort(k.name),
                          );
                        }
                        await settings.remove(AppSettingKeys.autocompact);
                        await settings.remove(AppSettingKeys.idleMinutes);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Valem para as próximas sessões, conversas e execuções do '
                  'planner. Uma sessão retomada mantém o modelo e o esforço '
                  'com que foi criada.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                AgentCard(
                  title: 'Consumo · modelo e esforço padrão',
                  children: [
                    for (final k in RunKind.values) ...[
                      if (k != RunKind.values.first)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: AppColors.border),
                        ),
                      _kindHeader(k),
                      const SizedBox(height: 8),
                      const FieldLabel('Modelo'),
                      _choices(
                        keyPrefix: 'settings-model-${k.name}',
                        values: [
                          for (final (id, label) in _models) (id, label),
                          if (!_models.any((m) => m.$1 == prefs.model(k)))
                            (prefs.model(k), prefs.model(k)),
                        ],
                        selected: prefs.model(k),
                        onTap: (v) =>
                            settings.set(AppSettingKeys.runModel(k.name), v),
                      ),
                      const SizedBox(height: 8),
                      const FieldLabel('Esforço (--effort)'),
                      _choices(
                        keyPrefix: 'settings-effort-${k.name}',
                        values: [
                          for (final e in effortChoices)
                            (e, e == defaultEffort ? 'Padrão do CLI' : e),
                        ],
                        selected: prefs.effort(k),
                        onTap: (v) =>
                            settings.set(AppSettingKeys.runEffort(k.name), v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Opus é o mais capaz e o mais caro; Sonnet resolve bem '
                      'tarefas já especificadas. Esforço menor = menos '
                      'raciocínio (tokens de saída) por resposta. Um agente com '
                      'model ou effort no arquivo usa os dele.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const AutomationsCard(),
                const SizedBox(height: 16),
                const BackupsCard(),
                const SizedBox(height: 16),
                AgentCard(
                  title: 'Sessões · suspender por inatividade',
                  children: [
                    _choices(
                      keyPrefix: 'settings-idle',
                      values: [
                        for (final m in RunPrefs.idleChoices)
                          ('$m', m == 0 ? 'Nunca' : '$m min'),
                      ],
                      selected: '${prefs.idleMinutes}',
                      onTap: (v) => settings.set(AppSettingKeys.idleMinutes, v),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'O processo do Claude de uma sessão parada, sem '
                      'resposta em andamento nem pergunta pendente, é fechado '
                      'depois deste tempo para liberar memória. A sessão '
                      'continua na lista e "Retomar" (ou enviar uma mensagem) '
                      'a reabre com todo o contexto.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AgentCard(
                  title: 'Consumo · compactação automática',
                  children: [
                    _choices(
                      keyPrefix: 'settings-autocompact',
                      values: [
                        for (final a in autocompactChoices)
                          (a, a == 'auto' ? 'Padrão do CLI' : a),
                      ],
                      selected: prefs.autocompact,
                      onTap: (v) => settings.set(AppSettingKeys.autocompact, v),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Cada resposta do Claude relê a conversa inteira. Quando '
                      'ela passa deste tamanho, o Claude Code resume o '
                      'histórico (--autocompact). Com a janela de 1M, o padrão '
                      'do CLI quase nunca compacta e as sessões longas ficam '
                      'caras; um limite menor custa menos, mas o resumo perde '
                      'detalhes da conversa.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _kindHeader(RunKind k) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        k.label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          k.hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
    ],
  );

  static Widget _choices({
    required String keyPrefix,
    required List<(String, String)> values,
    required String selected,
    required ValueChanged<String> onTap,
  }) => Row(
    children: [
      for (final (id, label) in values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ToggleBox(
              key: ValueKey('$keyPrefix-$id'),
              on: selected == id,
              height: 32,
              onTap: () => onTap(id),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: selected == id
                      ? AppColors.amber
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
