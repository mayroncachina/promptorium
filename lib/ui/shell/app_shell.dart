import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/agents/agents_screen.dart';
import '../../features/code/code_screen.dart';
import '../../features/mcp/mcp_screen.dart';
import '../../features/prompt/conversation_manager.dart';
import '../../features/prompt/prompt_screen.dart';
import '../../features/review/review_screen.dart';
import '../../features/sessions/new_session_dialog.dart';
import '../../features/sessions/sessions_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/specs/specs_screen.dart';
import '../../features/tasks/tasks_screen.dart';
import '../theme/tokens.dart';
import 'command_palette.dart';
import 'editor_zoom.dart';
import 'navigation.dart';
import 'shell_intents.dart';
import 'side_bar.dart';
import 'status_footer.dart';
import 'title_bar.dart';
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

  void _go(AppSection s) => ref.read(navigationProvider.notifier).go(s);

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    try {
      await showCommandPalette(context, onNavigate: _go);
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

  static Widget _screenFor(AppSection s) => switch (s) {
    AppSection.sessions => const SessionsScreen(),
    AppSection.prompt => const PromptScreen(),
    AppSection.specs => const SpecsScreen(),
    AppSection.tasks => const TasksScreen(),
    AppSection.agents => const AgentsScreen(),
    AppSection.review => const ReviewScreen(),
    AppSection.code => const CodeScreen(),
    AppSection.mcp => const McpScreen(),
    AppSection.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(navigationProvider);
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
              _go(i.section);
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
                      SideBar(active: section, onSelect: _go),
                      Expanded(
                        child: KeyedSubtree(
                          key: ValueKey('screen-${section.name}'),
                          child: _screenFor(section),
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
