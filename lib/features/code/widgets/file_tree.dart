import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../sessions/session_manager.dart' show sessionTitle;
import '../../sessions/widgets/session_style.dart';
import '../code_model.dart';
import '../worktree_files.dart';

Color markColor(FileMark m) => switch (m) {
  FileMark.added => AppColors.teal,
  FileMark.modified => AppColors.amber,
  FileMark.deleted => AppColors.red,
  FileMark.untracked => AppColors.textSecondary,
};

/// Actions of a tree row (context menu).
enum TreeAction { newFile, newFolder, rename, delete }

/// Worktree selector (mockup: card of the selected one + "Outros:").
class WorktreeSelector extends StatelessWidget {
  const WorktreeSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.isAlive,
  });

  final List<WorktreeOption> options;
  final WorktreeOption selected;
  final ValueChanged<WorktreeOption> onSelect;
  final bool Function(String sessionId) isAlive;

  String _subtitle(WorktreeOption o) {
    final s = o.session;
    final where = o.isRoot ? 'raiz do workspace' : 'worktree';
    if (s == null) return where;
    final look = SessionLook.of(s.status, alive: isAlive(s.id));
    return 'sessão ${sessionTitle(s)} · ${look.label.toLowerCase()}';
  }

  Color _dot(WorktreeOption o) {
    final s = o.session;
    if (s == null) return o.isRoot ? AppColors.blue : AppColors.textMuted;
    return SessionLook.of(s.status, alive: isAlive(s.id)).color;
  }

  @override
  Widget build(BuildContext context) {
    final others = options.where((o) => o.path != selected.path).toList();
    final active =
        selected.session != null &&
        isActiveStatus(selected.session!.status) &&
        isAlive(selected.session!.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopupMenuButton<String>(
          key: const ValueKey('code-worktree-button'),
          tooltip: selected.path,
          color: AppColors.panel,
          position: PopupMenuPosition.under,
          onSelected: (p) => onSelect(options.firstWhere((o) => o.path == p)),
          itemBuilder: (_) => [
            for (final o in options)
              PopupMenuItem<String>(
                value: o.path,
                height: 40,
                child: Row(
                  children: [
                    Dot(_dot(o)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            o.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 12,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            _subtitle(o),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: active ? ReviewColors.acceptBg : AppColors.surfaceRaised,
              border: Border.all(
                color: active ? ReviewColors.acceptBorder : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Dot(_dot(selected)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        _subtitle(selected),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                AppIcon(
                  AppIcons.chevronDown,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              const Text(
                'Outros:',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              for (final o in others)
                InkWell(
                  key: ValueKey('code-worktree-${o.path}'),
                  onTap: () => onSelect(o),
                  child: Text(
                    o.label,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.border,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Lazily expanded file tree of a [CodeWorktreeModel].
class FileTree extends StatelessWidget {
  const FileTree({
    super.key,
    required this.model,
    required this.onOpen,
    required this.onAction,
  });

  final CodeWorktreeModel model;
  final ValueChanged<String> onOpen;
  final void Function(TreeAction action, TreeEntry? entry) onAction;

  List<TreeEntry> _visible() {
    final out = <TreeEntry>[];
    void walk(String dir) {
      for (final e in model.index.children(dir)) {
        out.add(e);
        if (e.isDir && model.expanded.contains(e.path)) walk(e.path);
      }
    }

    walk('');
    return out;
  }

  Future<void> _menu(BuildContext context, Offset at, TreeEntry e) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<TreeAction>(
      context: context,
      color: AppColors.panel,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (e.isDir) ...[
          const PopupMenuItem(
            value: TreeAction.newFile,
            child: Text('Novo arquivo aqui', style: TextStyle(fontSize: 12)),
          ),
          const PopupMenuItem(
            value: TreeAction.newFolder,
            child: Text('Nova pasta aqui', style: TextStyle(fontSize: 12)),
          ),
        ],
        const PopupMenuItem(
          value: TreeAction.rename,
          child: Text('Renomear / mover…', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem(
          value: TreeAction.delete,
          child: Text(
            'Excluir…',
            style: TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ),
      ],
    );
    if (choice != null) onAction(choice, e);
  }

  @override
  Widget build(BuildContext context) {
    if (model.error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          model.error!,
          style: const TextStyle(fontSize: 12, color: AppColors.red),
        ),
      );
    }
    final rows = _visible();
    final activePath = model.activeTab?.path;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          model.loading ? 'Carregando…' : 'Nenhum arquivo.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('code-file-tree'),
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      itemCount: rows.length,
      itemExtent: 26,
      itemBuilder: (context, i) {
        final e = rows[i];
        final open = model.expanded.contains(e.path);
        final mark = e.mark;
        final color = e.isDir
            ? (e.changedInside ? AppColors.text : AppColors.textSecondary)
            : mark != null
            ? markColor(mark)
            : AppColors.text;
        return GestureDetector(
          onSecondaryTapDown: (d) => _menu(context, d.globalPosition, e),
          onLongPressStart: (d) => _menu(context, d.globalPosition, e),
          child: InkWell(
            key: ValueKey('code-tree-${e.path}'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => e.isDir ? model.toggle(e.path) : onOpen(e.path),
            child: Container(
              padding: EdgeInsets.only(left: 8.0 + e.depth * 14, right: 8),
              decoration: BoxDecoration(
                color: e.path == activePath
                    ? SessionColors.selectedBg
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: e.isDir
                        ? AppIcon(
                            open ? AppIcons.chevronDown : AppIcons.chevronRight,
                            size: 10,
                            color: AppColors.textMuted,
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        color: color,
                        decoration: mark == FileMark.deleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (mark != null)
                    Text(
                      mark.letter,
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: markColor(mark),
                      ),
                    )
                  else if (e.changedInside)
                    const Dot(AppColors.amber, size: 5),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
