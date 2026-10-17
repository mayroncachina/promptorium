import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/agents/agents_screen.dart';
import '../../features/code/code_screen.dart';
import '../../features/mcp/mcp_screen.dart';
import '../../features/mcp/widgets/add_server_dialog.dart';
import '../../features/project/new_project_dialog.dart';
import '../../features/project/project_screen.dart';
import '../../features/prompt/conversation_manager.dart';
import '../../features/prompt/prompt_screen.dart';
import '../../features/review/review_screen.dart';
import '../../features/sessions/new_session_dialog.dart';
import '../../features/sessions/sessions_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/skills/skills_screen.dart';
import '../../features/skills/widgets/skill_dialogs.dart';
import '../../features/specs/new_spec_dialog.dart';
import '../../features/specs/specs_screen.dart';
import '../../features/specs/workspace_watcher.dart';
import '../../features/board/board_screen.dart';
import '../../data/providers.dart';
import '../theme/tokens.dart';
import 'command_palette.dart';
import 'editor_zoom.dart';
import 'global_approvals.dart';
import 'navigation.dart';
import 'shell_intents.dart';
import 'side_bar.dart';
import 'status_footer.dart';
import 'title_bar.dart';
import 'tools_tabs.dart';
import 'workspace_picker.dart';

/// IDE shell (docs/mockups/Main.dc.html): title bar, sidebar, content, footer.
///
/// The shell never scrolls: it always fills the window and only inner panels
/// of each screen scroll.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _paletteOpen = false;

  /// Last tab of "Ferramentas" (Ctrl+8 / the sidebar go back to it).
  AppSection _lastTool = AppSection.agents;

  void _go(AppSection s) {
    if (s.isTool) _lastTool = s;
    ref.read(navigationProvider.notifier).go(s);
  }

  /// Sidebar / Ctrl+8: "Ferramentas" opens its last tab.
  void _goNav(AppSection s) {
    if (s == AppSection.agents) {
      final current = ref.read(navigationProvider);
      if (current.isTool) return;
      return _go(_lastTool);
    }
    _go(s);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _shortcutsNotice());
  }

  /// Once, after the menus were reordered (F10): the old digits moved.
  void _shortcutsNotice() {
    if (!mounted) return;
    final settings = ref.read(appSettingsProvider.notifier);
    final seen = settings.getInt(AppSettingKeys.shortcutsVersion) ?? 0;
    if (seen >= AppSection.shortcutsVersion) return;
    settings.set(
      AppSettingKeys.shortcutsVersion,
      '${AppSection.shortcutsVersion}',
    );
    // A first run has nothing to unlearn.
    if (settings.get(AppSettingKeys.lastSection) == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        key: const ValueKey('shortcuts-changed'),
        duration: const Duration(seconds: 10),
        content: Text(
          'Os atalhos mudaram com a nova ordem dos menus: '
          '${[for (final s in AppSection.shortcutItems) '${s.shortcutLabel} ${s.navLabel}'].join(' · ')}.',
        ),
      ),
    );
  }

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    try {
      await showCommandPalette(context, ref: ref, onNavigate: _go);
    } finally {
      _paletteOpen = false;
    }
  }

  void _zoom(ZoomOp op) {
    final key = ref.read(navigationProvider).editorKey;
    if (key == null) return; // no editor on this screen
    final z = ref.read(editorZoomProvider(key).notifier);
    switch (op) {
      case ZoomOp.zoomIn:
        z.zoomIn();
      case ZoomOp.zoomOut:
        z.zoomOut();
      case ZoomOp.reset:
        z.reset();
    }
  }

  bool _newSessionOpen = false;

  Future<void> _newSession() async {
    if (_newSessionOpen) return;
    _newSessionOpen = true;
    _go(AppSection.sessions);
    try {
      await showNewSessionDialog(context);
    } finally {
      _newSessionOpen = false;
    }
  }

  void _onAction(AppSection section) {
    if (section == AppSection.sessions) {
      _newSession();
    } else if (section == AppSection.prompt) {
      // Draft of a new conversation (the composer creates it on send).
      ref.read(selectedConversationProvider.notifier).select(null);
    } else if (section == AppSection.agents) {
      ref.read(selectedAgentProvider.notifier).newDraft();
    } else if (section == AppSection.specs) {
      showNewSpecDialog(context);
    } else if (section == AppSection.tasks) {
      showNewSpecDialog(context);
    } else if (section == AppSection.mcp) {
      showAddMcpServerDialog(context);
    } else if (section == AppSection.project) {
      showNewProjectDialog(context);
    } else if (section == AppSection.skills) {
      showNewSkillDialog(context);
    } else {
      _notImplemented(section.actionLabel ?? '');
    }
  }

  void _notImplemented(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$what — em construção'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Widget _screenFor(AppSection s) => s.isTool
      ? ToolsTabs(active: s, onSelect: _go, child: _screen(s))
      : _screen(s);

  static Widget _screen(AppSection s) => switch (s) {
    AppSection.project => const ProjectScreen(),
    AppSection.sessions => const SessionsScreen(),
    AppSection.prompt => const PromptScreen(),
    AppSection.specs => const SpecsScreen(),
    AppSection.tasks => const BoardScreen(),
    AppSection.agents => const AgentsScreen(),
    AppSection.skills => const SkillsScreen(),
    AppSection.review => const ReviewScreen(),
    AppSection.code => const CodeScreen(),
    AppSection.mcp => const McpScreen(),
    AppSection.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(navigationProvider);
    // Watches the workspace's specs / agents / skills / config (F11).
    ref.watch(workspaceWatcherProvider);
    return Shortcuts(
      shortcuts: shellShortcuts,
      child: Actions(
        actions: {
          OpenPaletteIntent: CallbackAction<OpenPaletteIntent>(
            onInvoke: (_) {
              _openPalette();
              return null;
            },
          ),
          ZoomIntent: CallbackAction<ZoomIntent>(
            onInvoke: (i) {
              _zoom(i.op);
              return null;
            },
          ),
          NewSessionIntent: CallbackAction<NewSessionIntent>(
            onInvoke: (_) {
              _newSession();
              return null;
            },
          ),
          GoToSectionIntent: CallbackAction<GoToSectionIntent>(
            onInvoke: (i) {
              _goNav(i.section);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: Column(
              children: [
                TitleBar(
                  section: section,
                  onOpenPalette: _openPalette,
                  onAction: () => _onAction(section),
                  onWorkspace: () => showWorkspacePicker(context),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SideBar(active: section, onSelect: _goNav),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: KeyedSubtree(
                                key: ValueKey('screen-${section.name}'),
                                child: _screenFor(section),
                              ),
                            ),
                            // Approvals of sessions / conversations that are
                            // not on screen, answerable from anywhere.
                            const Positioned.fill(child: GlobalApprovals()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const StatusFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
