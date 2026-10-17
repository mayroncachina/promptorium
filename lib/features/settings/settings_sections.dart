import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/managed_hooks.dart';
import '../../core/claude/run_prefs.dart';
import '../../core/update/update_check.dart';
import '../../data/providers.dart';
import '../project/project_config.dart';

/// Sections of Configurações (UX v2, U9; docs/mockups/v2/Configuracoes.dc.html):
/// the App group and the Workspace group, each entry with the words that
/// find it in the search box and whether it differs from the defaults.

enum SettingsGroup { app, workspace }

enum SettingsSection {
  consumption('Modelo e consumo', SettingsGroup.app, [
    'modelo',
    'esforço',
    'effort',
    'compactação',
    'autocompact',
    'opus',
    'sonnet',
    'haiku',
    'custo',
  ]),
  sessions('Sessões', SettingsGroup.app, [
    'suspender',
    'inatividade',
    'idle',
    'memória',
    'retomar',
  ]),
  automations('Automações (hooks)', SettingsGroup.app, [
    'hook',
    'formatar',
    'bloquear',
    'comandos',
    'sessionend',
  ]),
  providers('Provedores (ACP)', SettingsGroup.app, [
    'acp',
    'gemini',
    'codex',
    'agente',
    'prompt',
  ]),
  backups('Banco e backups', SettingsGroup.app, [
    'banco',
    'backup',
    'restaurar',
    'sqlite',
  ]),
  updates('Atualizações', SettingsGroup.app, [
    'versão',
    'atualização',
    'release',
    'github',
  ]),
  project('Configuração do projeto', SettingsGroup.workspace, [
    'specs',
    'testes',
    'gate',
    'verificação',
    'lint',
    'build',
    'formatar',
    'worktree',
    'porta',
    'revisor',
    'branch',
    'agente',
    'subagentes',
    'bloquear',
    'config.yml',
  ]);

  const SettingsSection(this.label, this.group, this.keywords);

  final String label;
  final SettingsGroup group;
  final List<String> keywords;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return label.toLowerCase().contains(q) ||
        keywords.any((k) => k.contains(q));
  }
}

/// Sections whose label or keywords contain [query] (all when empty).
List<SettingsSection> filterSections(String query) => [
  for (final s in SettingsSection.values)
    if (s.matches(query)) s,
];

/// Whether [section] holds any value different from the defaults
/// ("alterado" dot). [settings] = `app_settings`; [config] = the
/// workspace's config (null = no workspace).
bool sectionChanged(
  SettingsSection section,
  Map<String, String> settings,
  ProjectConfig? config,
) => switch (section) {
  SettingsSection.consumption =>
    RunKind.values.any(
          (k) =>
              settings.containsKey(AppSettingKeys.runModel(k.name)) ||
              settings.containsKey(AppSettingKeys.runEffort(k.name)),
        ) ||
        settings.containsKey(AppSettingKeys.autocompact),
  SettingsSection.sessions => settings.containsKey(AppSettingKeys.idleMinutes),
  SettingsSection.automations => ManagedHook.values.any(
    (h) => settings[h.settingKey] == '0',
  ),
  SettingsSection.providers =>
    (settings[AppSettingKeys.acpAgents] ?? '').trim().isNotEmpty,
  SettingsSection.backups => false,
  SettingsSection.updates => settings[UpdateChecker.enabledKey] == '0',
  SettingsSection.project => config != null && !config.isDefault,
};

/// "A etapa só passa se: ✓ testes · ✓ lint · ✓ commit" from the saved
/// config (null = no gate: the marker alone finishes a step).
List<String>? gateEffect(ProjectConfig c) {
  if (!c.gateEnabled) return null;
  return [
    if (c.testCommand != null) 'testes (${c.testCommand})',
    if (c.lintCommand != null) 'lint (${c.lintCommand})',
    if (c.buildCommand != null) 'build (${c.buildCommand})',
    if (c.gate.requireCommit) 'commit da etapa',
    if (c.gate.requireCleanTree) 'árvore limpa',
  ];
}

/// Section shown; the Projeto screen can open the project one directly.
class SelectedSettingsSection extends Notifier<SettingsSection> {
  @override
  SettingsSection build() => SettingsSection.consumption;

  void select(SettingsSection s) => state = s;
}

final selectedSettingsSectionProvider =
    NotifierProvider<SelectedSettingsSection, SettingsSection>(
      SelectedSettingsSection.new,
    );

@immutable
class SettingsSearch {
  const SettingsSearch(this.query);

  final String query;
}
