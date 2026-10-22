import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_extensions.dart';
import '../../core/claude/run_prefs.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../project/project_config.dart';
import '../project/widgets/project_config_view.dart';
import '../sessions/widgets/session_style.dart';
import 'automations_view.dart';
import 'backups_view.dart';
import 'providers_view.dart';
import 'settings_sections.dart';

/// Models offered as defaults (`inherit` = the CLI's default model).
const _models = [
  ('sonnet', 'Sonnet'),
  ('opus', 'Opus'),
  ('haiku', 'Haiku'),
  ('fable', 'Fable'),
  ('inherit', 'Padrão do CLI'),
];

/// Configurações (UX v2, U9): sections on the left (App · Workspace), the
/// chosen one on the right. The project's `config.yml` lives here too, so
/// everything the Promptorium obeys is in one place.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    final settings = ref.watch(appSettingsProvider);
    final config = ws == null
        ? null
        : ref.watch(projectConfigProvider(ws.path)).value;
    var selected = ref.watch(selectedSettingsSectionProvider);
    final visible = filterSections(_search.text);
    if (!visible.contains(selected) && visible.isNotEmpty) {
      selected = visible.first;
    }
    final groups = [
      (SettingsGroup.app, 'App', ''),
      (SettingsGroup.workspace, 'Workspace', ws?.name ?? 'nenhum'),
    ];
    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 240,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
            decoration: const BoxDecoration(
              color: AppColors.panel,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Text(
                    'Configurações',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                SizedBox(
                  height: 30,
                  child: TextField(
                    key: const ValueKey('settings-search'),
                    controller: _search,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Buscar configuração…',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 8),
                for (final (g, title, sub) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                    child: Row(
                      children: [
                        Text(title.toUpperCase(), style: sectionTitleStyle),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: ws == null
                                    ? AppColors.textMuted
                                    : AppColors.amber,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final s in visible)
                    if (s.group == g)
                      _SectionTile(
                        section: s,
                        on: s == selected,
                        changed: sectionChanged(s, settings, config),
                        enabled: g == SettingsGroup.app || ws != null,
                        onTap: () => ref
                            .read(selectedSettingsSectionProvider.notifier)
                            .select(s),
                      ),
                ],
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'Nenhuma seção com esse texto.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('settings-section-${selected.name}'),
              child: switch (selected) {
                SettingsSection.consumption => const _ConsumptionSection(),
                SettingsSection.specRuns => const _SpecRunsSection(),
                SettingsSection.sessions => const _SessionsSection(),
                SettingsSection.automations => const _Page(
                  title: 'Automações',
                  intro:
                      'Hooks que o app adiciona a cada sessão num settings.json '
                      'temporário (--settings); os do seu ~/.claude continuam '
                      'valendo.',
                  children: [AutomationsCard()],
                ),
                SettingsSection.providers => const _Page(
                  title: 'Provedores',
                  intro:
                      'Agentes que falam o Agent Client Protocol aparecem no '
                      'seletor do Prompt. O Claude Code continua por '
                      'stream-json.',
                  children: [AcpProvidersCard()],
                ),
                SettingsSection.backups => const _Page(
                  title: 'Banco e backups',
                  intro:
                      'Uma cópia do banco é guardada antes de cada atualização '
                      'de schema.',
                  children: [BackupsCard()],
                ),
                SettingsSection.updates => const _Page(
                  title: 'Atualizações',
                  intro:
                      'Verificação de versão nova no GitHub Releases, uma vez '
                      'por dia, sem instalar nada sozinha.',
                  children: [UpdatesCard()],
                ),
                SettingsSection.project =>
                  ws == null
                      ? const _Page(
                          title: 'Configuração do projeto',
                          intro:
                              'Selecione um workspace na barra de título para '
                              'ver a configuração dele.',
                          children: [],
                        )
                      : _ProjectSection(workspace: ws, config: config),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.on,
    required this.changed,
    required this.enabled,
    required this.onTap,
  });

  final SettingsSection section;
  final bool on;
  final bool changed;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: ValueKey('settings-nav-${section.name}'),
    color: on ? AppColors.amberTint : Colors.transparent,
    borderRadius: BorderRadius.circular(6),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: !enabled
                      ? AppColors.textMuted
                      : on
                      ? AppColors.amber
                      : AppColors.text,
                ),
              ),
            ),
            if (changed)
              Tooltip(
                message: 'Diferente do padrão',
                child: Dot(
                  AppColors.amber,
                  key: ValueKey('settings-changed-${section.name}'),
                  size: 6,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Title, one-line intro and the cards of a section.
class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.intro,
    required this.children,
    this.trailing,
    this.effect,
  });

  final String title;
  final String intro;
  final Widget? trailing;

  /// Plain-language effect of the current values (amber box).
  final Widget? effect;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              intro,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (effect != null) ...[const SizedBox(height: 12), effect!],
            for (final c in children) ...[const SizedBox(height: 16), c],
          ],
        ),
      ),
    ),
  );
}

class _ConsumptionSection extends ConsumerWidget {
  const _ConsumptionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runPrefsProvider);
    final settings = ref.read(appSettingsProvider.notifier);
    return _Page(
      title: 'Modelo e consumo',
      intro:
          'Valem para as próximas sessões, conversas e execuções do planner. '
          'Uma sessão retomada mantém o modelo e o esforço com que foi '
          'criada.',
      trailing: SmallButton(
        key: const ValueKey('settings-reset'),
        label: 'Restaurar padrões da seção',
        onTap: () async {
          for (final k in RunKind.values) {
            await settings.remove(AppSettingKeys.runModel(k.name));
            await settings.remove(AppSettingKeys.runEffort(k.name));
          }
          await settings.remove(AppSettingKeys.autocompact);
        },
      ),
      effect: _Effect(
        'Com estes valores: sessões em ${_modelLabel(prefs.model(RunKind.session))}'
        ' (${prefs.effort(RunKind.session)}) · conversas em '
        '${_modelLabel(prefs.model(RunKind.conversation))} · planner em '
        '${_modelLabel(prefs.model(RunKind.planner))} · compacta em '
        '${prefs.autocompact == 'auto' ? 'padrão do CLI' : prefs.autocompact}.',
      ),
      children: [
        AgentCard(
          title: 'Modelo e esforço padrão',
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
              choices(
                keyPrefix: 'settings-model-${k.name}',
                values: [
                  for (final (id, label) in _models) (id, label),
                  if (!_models.any((m) => m.$1 == prefs.model(k)))
                    (prefs.model(k), prefs.model(k)),
                ],
                selected: prefs.model(k),
                onTap: (v) => settings.set(AppSettingKeys.runModel(k.name), v),
              ),
              const SizedBox(height: 8),
              const FieldLabel('Esforço (--effort)'),
              choices(
                keyPrefix: 'settings-effort-${k.name}',
                values: [
                  for (final e in effortChoices)
                    (e, e == defaultEffort ? 'Padrão do CLI' : e),
                ],
                selected: prefs.effort(k),
                onTap: (v) => settings.set(AppSettingKeys.runEffort(k.name), v),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Opus é o mais capaz e o mais caro; Sonnet resolve bem tarefas '
              'já especificadas. Esforço menor = menos raciocínio (tokens de '
              'saída) por resposta. Um agente com model ou effort no arquivo '
              'usa os dele.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        AgentCard(
          title: 'Compactação automática',
          children: [
            choices(
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
              'Cada resposta do Claude relê a conversa inteira. Quando ela '
              'passa deste tamanho, o Claude Code resume o histórico '
              '(--autocompact). Com a janela de 1M, o padrão do CLI quase '
              'nunca compacta e as sessões longas ficam caras; um limite menor '
              'custa menos, mas o resumo perde detalhes da conversa.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  static String _modelLabel(String id) =>
      _models.where((m) => m.$1 == id).firstOrNull?.$2 ?? id;

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
}

class _SessionsSection extends ConsumerWidget {
  const _SessionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runPrefsProvider);
    final settings = ref.read(appSettingsProvider.notifier);
    return _Page(
      title: 'Sessões',
      intro: 'Como o app trata uma sessão parada.',
      trailing: SmallButton(
        key: const ValueKey('settings-reset-sessions'),
        label: 'Restaurar padrões da seção',
        onTap: () => settings.remove(AppSettingKeys.idleMinutes),
      ),
      effect: _Effect(
        prefs.idleMinutes == 0
            ? 'O processo de uma sessão parada nunca é fechado sozinho.'
            : 'Uma sessão parada há ${prefs.idleMinutes} min tem o processo '
                  'fechado; "Retomar" ou uma mensagem a reabre com o contexto.',
      ),
      children: [
        AgentCard(
          title: 'Suspender por inatividade',
          children: [
            choices(
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
              'O processo do Claude de uma sessão parada, sem resposta em '
              'andamento nem pergunta pendente, é fechado depois deste tempo '
              'para liberar memória. A sessão continua na lista.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

/// How many sessions a spec opens and what the app's Claude runs load
/// (SPEC-017 R2, R4, R5).
class _SpecRunsSection extends ConsumerWidget {
  const _SpecRunsSection();

  static const _steps = [1, 2, 3, 4, 6];
  static const _contexts = [0, 40, 60, 80, 120];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runPrefsProvider);
    final off = ref.watch(runExtensionsProvider);
    final known = decodeKnownExtensions(
      ref.watch(appSettingsProvider)[AppSettingKeys.knownExtensions],
    );
    final settings = ref.read(appSettingsProvider.notifier);
    final limitK = prefs.continueContextTokens ~/ 1000;
    Future<void> toggle(String key, Set<String> now, String id, bool on) =>
        settings.set(
          key,
          jsonEncode(
            on ? (now.toSet()..remove(id)).toList() : [...now, id]
              ..sort(),
          ),
        );
    TextStyle sub = const TextStyle(
      fontSize: 11,
      color: AppColors.textSecondary,
    );
    return _Page(
      title: 'Execução de specs',
      intro:
          'Quantas sessões uma spec abre e o que cada execução do app '
          'carrega. Valem para as próximas sessões.',
      trailing: SmallButton(
        key: const ValueKey('settings-reset-spec-runs'),
        label: 'Restaurar padrões da seção',
        onTap: () async {
          for (final k in [
            AppSettingKeys.singleSessionSteps,
            AppSettingKeys.continueContextTokens,
            AppSettingKeys.disabledPlugins,
            AppSettingKeys.disabledMcpServers,
          ]) {
            await settings.remove(k);
          }
        },
      ),
      effect: _Effect(
        key: const ValueKey('settings-spec-runs-effect'),
        'Spec com até ${prefs.singleSessionMaxSteps} '
        '${prefs.singleSessionMaxSteps == 1 ? 'requisito roda' : 'requisitos roda'} '
        'numa sessão só; acima disso, uma por etapa'
        '${limitK == 0 ? '.' : ', e a próxima continua na mesma sessão enquanto '
                  'o contexto dela estiver abaixo de $limitK mil tokens.'}',
      ),
      children: [
        AgentCard(
          title: 'Etapas numa sessão só',
          children: [
            choices(
              keyPrefix: 'settings-single-steps',
              values: [for (final n in _steps) ('$n', '$n')],
              selected: '${prefs.singleSessionMaxSteps}',
              onTap: (v) => settings.set(AppSettingKeys.singleSessionSteps, v),
            ),
            const SizedBox(height: 12),
            Text(
              'Spec com até este número de requisitos roda inteira numa '
              'sessão. Acima disso, cada etapa começa numa sessão própria.',
              style: sub,
            ),
          ],
        ),
        AgentCard(
          title: 'Continuar na mesma sessão até',
          children: [
            choices(
              keyPrefix: 'settings-continue-context',
              values: [
                for (final k in _contexts)
                  ('$k', k == 0 ? 'Desligado' : '$k mil tokens'),
              ],
              selected: '$limitK',
              onTap: (v) =>
                  settings.set(AppSettingKeys.continueContextTokens, v),
            ),
            const SizedBox(height: 12),
            Text(
              'Depois que o gate aprova uma etapa de primeira, a próxima vai '
              'na mesma sessão enquanto o contexto medido dela estiver abaixo '
              'disto. Uma sessão que precisou de reenvio do gate não '
              'continua.',
              style: sub,
            ),
          ],
        ),
        AgentCard(
          title: 'Plugins nas execuções do app',
          children: [
            Text(
              'Desligado aqui, o plugin não carrega quando o Promptorium abre '
              'o Claude Code (sessões, conversas, "Gerar design" e revisor). '
              'O Claude Code no seu terminal não muda.',
              style: sub,
            ),
            if (known.plugins.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Nenhum plugin visto ainda: a lista vem da última vez que '
                  'o app abriu o Claude Code. Rode uma sessão ou uma conversa '
                  'e volte aqui.',
                  key: const ValueKey('settings-plugins-empty'),
                  style: sub,
                ),
              ),
            for (final p in known.plugins)
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  key: ValueKey('settings-plugin-${p.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: !off.plugins.contains(p.id),
                  onChanged: (on) => toggle(
                    AppSettingKeys.disabledPlugins,
                    off.plugins,
                    p.id,
                    on,
                  ),
                  title: Text(
                    '${p.name}  ${p.id.substring(p.name.length)}'
                    '${p.version == null ? '' : ' · ${p.version}'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    p.tools == 0
                        ? 'sem ferramentas MCP'
                        : '${p.tools} ferramentas MCP em toda chamada',
                    style: sub,
                  ),
                ),
              ),
          ],
        ),
        AgentCard(
          title: 'Servidores MCP nas execuções do app',
          children: [
            Text(
              'Os do usuário, do projeto (.mcp.json) e os conectores do '
              'claude.ai. Os de plugin seguem o plugin.',
              style: sub,
            ),
            if (known.servers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Nenhum servidor visto ainda.',
                  key: const ValueKey('settings-mcp-empty'),
                  style: sub,
                ),
              ),
            for (final s in known.servers)
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  key: ValueKey('settings-mcp-${s.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: !off.mcpServers.contains(s.name),
                  onChanged: (on) => toggle(
                    AppSettingKeys.disabledMcpServers,
                    off.mcpServers,
                    s.name,
                    on,
                  ),
                  title: Text(s.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(switch (s.source) {
                    'user' => 'usuário',
                    'project' => 'projeto (.mcp.json)',
                    _ => 'conector do claude.ai',
                  }, style: sub),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({required this.workspace, required this.config});

  final Workspace workspace;
  final ProjectConfig? config;

  @override
  Widget build(BuildContext context) {
    final gate = config == null ? null : gateEffect(config!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _Effect(
                gate == null
                    ? 'Sem gate: o marcador ETAPA CONCLUÍDA basta para fechar '
                          'uma etapa. Preencha o comando de testes (ou use '
                          '"Analisar repositório" no Projeto) para ligar.'
                    : 'A etapa só passa se: ${gate.map((g) => '✓ $g').join(' · ')}'
                          '${config!.gate.attempts > 0 ? ' · ${config!.gate.attempts} reenvio(s) automático(s) antes de pedir você' : ''}.',
                key: const ValueKey('settings-gate-effect'),
              ),
            ),
          ),
        ),
        Expanded(
          child: ProjectConfigView(
            key: ValueKey('settings-project-config-${workspace.id}'),
            workspace: workspace,
            intro:
                'Fica em ${ProjectConfig.filePath}, dentro do repositório: '
                'faça commit para o time usar o mesmo.',
          ),
        ),
      ],
    );
  }
}

/// Amber box with the plain-language effect of a section's values.
class _Effect extends StatelessWidget {
  const _Effect(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: SessionColors.runningToolBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: SessionColors.runningToolBorder),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12)),
  );
}

/// Row of toggles (one per value).
Widget choices({
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
