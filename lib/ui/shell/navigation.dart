import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../widgets/app_icon.dart';

/// Top-level screens of the IDE, in sidebar order (see docs/mockups/Main.dc.html).
enum AppSection {
  /// "Para você": everything waiting for a human decision (UX v2, U1).
  home('Início', null),
  project('Projeto', 'Novo projeto'),
  sessions('Sessões', 'Nova sessão'),
  prompt('Prompt', 'Nova conversa'),
  specs('Specs', 'Nova spec'),

  /// Quadro: one card per spec (the enum name is kept: it is stored as the
  /// last visible screen).
  tasks('Quadro', 'Nova spec'),
  agents('Agentes', 'Novo agente'),
  skills('Skills', 'Nova skill'),
  review('Review', null),
  code('Código', null),
  mcp('Servidores MCP', 'Adicionar servidor'),

  /// Reached through the gear at the bottom of the sidebar.
  settings('Configurações', null);

  const AppSection(this.label, this.actionLabel);

  /// Name shown in the tooltip, palette and screen title.
  final String label;

  /// Contextual primary action in the title bar (null = no button).
  final String? actionLabel;

  /// Main sidebar items, in the order of the work (plano F10, UX v2):
  /// Início · Projeto · Specs · Quadro · Sessões · Review · Código · Prompt ·
  /// Ferramentas. [agents] stands for "Ferramentas" (Agentes / Skills / MCP
  /// as tabs).
  static const navItems = [
    home,
    project,
    specs,
    tasks,
    sessions,
    review,
    code,
    prompt,
    agents,
  ];

  /// Screens shown as tabs of "Ferramentas".
  static const toolTabs = [agents, skills, mcp];

  bool get isTool => toolTabs.contains(this);

  /// Ctrl+1…9 targets (same order as the sidebar).
  static const shortcutItems = navItems;

  /// Version of the shortcut layout; a change shows a one-time notice.
  static const shortcutsVersion = 3;

  /// Sidebar / palette name: the tools group is "Ferramentas".
  String get navLabel => this == agents ? 'Ferramentas' : label;

  /// `Ctrl 3` (null = no shortcut).
  String? get shortcutLabel {
    final i = shortcutItems.indexOf(this);
    return i < 0 ? null : 'Ctrl ${i + 1}';
  }

  AppIconData get icon => switch (this) {
    home => AppIcons.home,
    project => AppIcons.project,
    sessions => AppIcons.sessions,
    prompt => AppIcons.prompt,
    specs => AppIcons.specs,
    tasks => AppIcons.tasks,
    agents => AppIcons.agents,
    skills => AppIcons.skills,
    review => AppIcons.review,
    code => AppIcons.code,
    mcp => AppIcons.mcp,
    settings => AppIcons.settings,
  };

  /// Key of the editor living on this screen, used by the zoom shortcuts
  /// (null = the screen has no zoomable editor).
  String? get editorKey => switch (this) {
    specs => 'specs',
    code => 'code',
    _ => null,
  };
}

/// Currently visible section; the last one is restored from `app_settings`.
class NavigationController extends Notifier<AppSection> {
  @override
  AppSection build() {
    final saved = ref
        .read(appSettingsProvider.notifier)
        .get(AppSettingKeys.lastSection);
    return AppSection.values.asNameMap()[saved] ?? AppSection.home;
  }

  void go(AppSection section) {
    state = section;
    ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.lastSection, section.name);
  }
}

final navigationProvider = NotifierProvider<NavigationController, AppSection>(
  NavigationController.new,
);
