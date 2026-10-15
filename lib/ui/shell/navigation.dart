import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../widgets/app_icon.dart';

/// Top-level screens of the IDE, in sidebar order (see docs/mockups/Main.dc.html).
enum AppSection {
  sessions('Sessões', 'Nova sessão'),
  prompt('Prompt', 'Nova conversa'),
  specs('Specs', 'Nova spec'),
  tasks('Tarefas', 'Nova tarefa'),
  agents('Agentes', 'Novo agente'),
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

  /// Sections shown as the main sidebar items (everything except settings).
  static const navItems = [
    sessions,
    prompt,
    specs,
    tasks,
    agents,
    review,
    code,
    mcp,
  ];

  AppIconData get icon => switch (this) {
    sessions => AppIcons.sessions,
    prompt => AppIcons.prompt,
    specs => AppIcons.specs,
    tasks => AppIcons.tasks,
    agents => AppIcons.agents,
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
    return AppSection.values.asNameMap()[saved] ?? AppSection.sessions;
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
