import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/agent_names.dart';
import '../sessions/new_session_dialog.dart';
import '../sessions/widgets/session_style.dart';
import 'agent_repository.dart';
import 'widgets/agent_editor.dart';
import 'widgets/agent_style.dart';

/// Selection of the Agentes screen: the agent file path, a "new agent" draft
/// ([isNewAgentKey]) or null (first agent of the list).
class SelectedAgent extends Notifier<String?> {
  int _drafts = 0;

  @override
  String? build() => null;

  void select(String? path) => state = path;

  /// Opens an empty editor ("Novo agente" of the title bar).
  void newDraft() => state = '<novo-${++_drafts}>';
}

bool isNewAgentKey(String? key) => key != null && key.startsWith('<novo-');

final selectedAgentProvider = NotifierProvider<SelectedAgent, String?>(
  SelectedAgent.new,
);

/// Agentes (plano, Fase 7): global / project agents and their editor.
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final async = ref.watch(agentEntriesProvider(ws?.path));
    final entries = async.value ?? const <AgentEntry>[];
    final selected = ref.watch(selectedAgentProvider);
    AgentEntry? entry;
    if (!isNewAgentKey(selected)) {
      for (final e in entries) {
        if (e.path == selected) entry = e;
      }
      entry ??= entries.isEmpty ? null : entries.first;
    }
    final editorKey = entry?.path ?? selected ?? '<vazio>';

    return LayoutBuilder(
      builder: (context, c) {
        final listWidth = c.maxWidth < 1100 ? 230.0 : 260.0;
        return ColoredBox(
          color: AppColors.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: listWidth,
                child: _AgentList(
                  entries: entries,
                  selectedPath: entry?.path,
                  workspace: ws,
                  loading: async.isLoading && async.value == null,
                  error: async.hasError ? '${async.error}' : null,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: async.value == null && async.isLoading
                    ? const SizedBox()
                    : AgentEditor(
                        // Reset the form when the selection / file changes.
                        key: ValueKey(
                          '$editorKey#${entry?.file.serialize().hashCode}',
                        ),
                        entry: entry,
                        workspace: ws,
                        onSaved: (path) {
                          ref.read(selectedAgentProvider.notifier).select(path);
                          ref.invalidate(agentListProvider(ws?.path));
                          ScaffoldMessenger.maybeOf(context)
                            ?..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text('Agente salvo em $path'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                        },
                        onDeleted: () {
                          ref.read(selectedAgentProvider.notifier).select(null);
                          ref.invalidate(agentListProvider(ws?.path));
                        },
                        onTest: (name) async {
                          final id = await showNewSessionDialog(
                            context,
                            agent: name,
                          );
                          if (id != null) {
                            ref
                                .read(navigationProvider.notifier)
                                .go(AppSection.sessions);
                          }
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AgentList extends ConsumerWidget {
  const _AgentList({
    required this.entries,
    required this.selectedPath,
    required this.workspace,
    required this.loading,
    required this.error,
  });

  final List<AgentEntry> entries;
  final String? selectedPath;
  final Workspace? workspace;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final global = [
      for (final e in entries)
        if (!e.isProject) e,
    ];
    final project = [
      for (final e in entries)
        if (e.isProject) e,
    ];
    return ColoredBox(
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text('AGENTES', style: sectionTitleStyle),
          ),
          _GroupHeader(title: 'Globais', path: '~/.claude/agents'),
          if (loading)
            const _Hint('Lendo agentes…')
          else if (error != null)
            _Hint('Falha ao ler: $error')
          else if (global.isEmpty)
            const _Hint('Nenhum agente global'),
          for (final e in global)
            _AgentTile(entry: e, selected: e.path == selectedPath),
          const SizedBox(height: 4),
          const Divider(height: 1),
          _GroupHeader(
            title: workspace == null
                ? 'Projeto'
                : 'Projeto · ${workspace!.name}',
            path: '.claude/agents',
          ),
          if (workspace == null)
            const _Hint('Selecione um workspace')
          else if (!loading && project.isEmpty)
            const _Hint('Nenhum agente de projeto'),
          for (final e in project)
            _AgentTile(entry: e, selected: e.path == selectedPath),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.path});

  final String title;
  final String path;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
    child: Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Spacer(),
        Flexible(
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    ),
  );
}

class _AgentTile extends ConsumerWidget {
  const _AgentTile({required this.entry, required this.selected});

  final AgentEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = entry.file;
    final (meta, metaColor) = entry.overridesGlobal
        ? ('sobrescreve o global', AppColors.amber)
        : entry.overriddenByProject
        ? ('sobrescrito no projeto', AppColors.textMuted)
        : (
            '${agentModelLabel(f.model)} · ${f.description ?? ''}',
            AppColors.textSecondary,
          );
    final radius = BorderRadius.circular(8);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? SessionColors.selectedBg : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? SessionColors.selectedBorder : Colors.transparent,
          ),
        ),
        child: InkWell(
          key: ValueKey(
            'agent-${entry.isProject ? 'project' : 'global'}-${entry.name}',
          ),
          borderRadius: radius,
          onTap: () =>
              ref.read(selectedAgentProvider.notifier).select(entry.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                AgentAvatar(
                  name: entry.name,
                  color: agentTint(entry.name, f.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: metaColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
