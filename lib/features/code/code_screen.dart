import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fs/dir_watcher.dart';
import 'code_panels.dart';

import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_icon.dart';
import '../../ui/widgets/code_editor/app_code_editor.dart';
import '../../ui/widgets/zoom_control.dart';
import '../sessions/session_manager.dart';
import '../sessions/widgets/session_style.dart';
import '../sessions/widgets/session_terminal.dart' show AppTerminalView;
import 'code_model.dart';
import 'widgets/code_dialogs.dart';
import 'widgets/file_tree.dart';
import 'worktree_files.dart';
import 'worktree_terminal.dart';

/// Code screen (plano, Fase 10; docs/mockups/Codigo.dc.html): worktree
/// selector, file tree with git marks, editor in tabs (re_editor, zoom key
/// `code`), gutter marks (agent × unsaved edit), banner of the agent working
/// in the worktree, disk watch, terminal per worktree and Ctrl+P.
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  static const editorKey = 'code';

  /// Safety net of the disk watcher (folders it could not watch).
  static const pollInterval = Duration(seconds: 30);

  /// At most this many folders are watched (inotify limits).
  static const maxWatchedDirs = 2000;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  Timer? _poll;

  /// Folders of the open worktree (F11: changes arrive as events; the poll
  /// is only a safety net).
  DirWatcher? _watcher;
  String? _watchedRoot;
  int _watchedDirs = -1;
  final Set<String> _loaded = {};
  bool _panelOpen = true;
  int _panelTab = 0; // 0 terminal, 1 problemas
  CodeWorktreeModel? _model;
  int? _workspaceId;
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(CodeScreen.pollInterval, (_) => _onTick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_watcher?.close());
    _searchFocus.dispose();
    super.dispose();
  }

  void _onTick() {
    final m = _model;
    if (m == null || !mounted) return;
    unawaited(m.checkDisk());
    unawaited(m.refresh(quiet: true));
  }

  /// Watches the folders of [m] (re-done when the tree changes).
  void _watch(CodeWorktreeModel m) {
    final dirs = m.index.dirs;
    if (_watchedRoot == m.root && _watchedDirs == dirs.length) return;
    _watchedRoot = m.root;
    _watchedDirs = dirs.length;
    final paths = [
      m.root,
      for (final d in dirs.take(CodeScreen.maxWatchedDirs)) '${m.root}/$d',
    ];
    if (_watcher == null) {
      _watcher = DirWatcher(paths, onChange: (_) => _onDisk());
    } else {
      _watcher!.update(paths);
    }
  }

  void _onDisk() {
    final m = _model;
    if (m == null || !mounted) return;
    unawaited(m.checkDisk());
    unawaited(m.refresh(quiet: true));
  }

  void _snack(String msg) {
    if (!mounted || msg.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
  }

  // --- actions ---------------------------------------------------------------------

  Future<void> _open(CodeWorktreeModel m, String path) async {
    final r = await m.open(path);
    if (r case NotOpened(:final reason)) _snack(reason);
  }

  Future<void> _save(CodeWorktreeModel m, CodeTab tab) async {
    try {
      final notified = await m.save(tab, workspaceId: _workspaceId);
      // `lint:` of the project on save → Problemas (F13).
      final root = ref.read(activeWorkspaceProvider)?.path;
      if (root != null) {
        unawaited(ref.read(problemsProvider(m.root).notifier).run(root));
      }
      if (notified.isNotEmpty) {
        _snack(
          '${tab.name} salvo · aviso enfileirado para o agente '
          '(${notified.length} sessão${notified.length == 1 ? '' : 'ões'}).',
        );
      }
    } catch (e) {
      _snack('Falha ao salvar ${tab.path}: $e');
    }
  }

  Future<void> _close(CodeWorktreeModel m, CodeTab tab) async {
    if (tab.dirty) {
      final choice = await showUnsavedDialog(context, tab.name);
      if (choice == UnsavedChoice.cancel) return;
      if (choice == UnsavedChoice.save) {
        await _save(m, tab);
        if (tab.dirty) return;
      }
    }
    m.close(tab);
  }

  Future<void> _goToFile(CodeWorktreeModel m) async {
    final path = await showGoToFileDialog(context, m.index.files);
    if (path != null) await _open(m, path);
  }

  Future<void> _treeAction(
    CodeWorktreeModel m,
    TreeAction action,
    TreeEntry? e,
  ) async {
    String dirOf(TreeEntry? e) {
      if (e == null) return '';
      if (e.isDir) return '${e.path}/';
      final i = e.path.lastIndexOf('/');
      return i < 0 ? '' : '${e.path.substring(0, i)}/';
    }

    try {
      switch (action) {
        case TreeAction.newFile:
          final name = await showPathDialog(
            context,
            title: 'Novo arquivo',
            label: 'Caminho relativo ao worktree (pastas são criadas).',
            initial: dirOf(e),
          );
          if (name == null) return;
          final p = await m.createFile(name);
          await _open(m, p);
        case TreeAction.newFolder:
          final name = await showPathDialog(
            context,
            title: 'Nova pasta',
            label: 'Caminho relativo ao worktree.',
            initial: dirOf(e),
          );
          if (name == null) return;
          await m.createFolder(name);
        case TreeAction.rename:
          if (e == null) return;
          final to = await showPathDialog(
            context,
            title: 'Renomear / mover',
            label: 'Novo caminho de ${e.path}.',
            initial: e.path,
            action: 'Renomear',
          );
          if (to == null) return;
          await m.rename(e.path, to);
        case TreeAction.delete:
          if (e == null) return;
          final dirtyOpen = m.tabs.any(
            (t) =>
                t.dirty &&
                (t.path == e.path || t.path.startsWith('${e.path}/')),
          );
          final ok = await showConfirmDialog(
            context,
            title: 'Excluir ${e.name}?',
            message:
                '${e.isDir ? 'A pasta e todo o conteúdo serão apagados' : 'O arquivo será apagado'} '
                'do disco (${e.path}).'
                '${dirtyOpen ? ' Alterações não salvas serão perdidas.' : ''}',
          );
          if (!ok) return;
          await m.delete(e.path);
      }
    } on CodeFileException catch (err) {
      _snack(err.message);
    } catch (err) {
      _snack('$err');
    }
  }

  void _select(Workspace ws, WorktreeOption o) {
    ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.codeWorktree(ws.id), o.path);
  }

  // --- build -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Selecione um workspace na barra de título.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              SizedBox(height: 16),
              ZoomControl(editorKey: CodeScreen.editorKey),
            ],
          ),
        ),
      );
    }
    _workspaceId = ws.id;
    final sessions = ref.watch(sessionsProvider(ws.id)).value ?? const [];
    final manager = ref.watch(sessionManagerProvider);
    final worktrees =
        ref.watch(gitWorktreesProvider(ws.path)).value ?? const [];
    final rootBranch = ref.watch(currentBranchProvider(ws.path)).value;
    final options = buildWorktreeOptions(
      root: ws.path,
      rootBranch: rootBranch,
      worktrees: worktrees,
      sessions: sessions,
    );
    final saved = ref.watch(
      appSettingsProvider.select((s) => s[AppSettingKeys.codeWorktree(ws.id)]),
    );
    final selected = options.firstWhere(
      (o) => o.path == saved,
      orElse: () => options.first,
    );
    final model = ref.watch(codeWorktreeModelProvider(selected.path));
    _model = model;
    _watch(model);
    model.setBaseBranch(selected.isRoot ? null : selected.session?.baseBranch);
    if (_loaded.add(selected.path)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(model.refresh());
        unawaited(model.checkDisk());
      });
    }
    bool alive(String id) => manager.isAlive(id);
    final active = sessions
        .where(
          (s) =>
              s.worktreePath == selected.path &&
              isActiveStatus(s.status) &&
              alive(s.id),
        )
        .toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            _goToFile(model),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          final t = model.activeTab;
          if (t != null) _close(model, t);
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          final t = model.activeTab;
          if (t != null) _save(model, t);
        },
        // Global search (F13).
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): () {
          setState(() {
            _panelTab = 3;
            _panelOpen = true;
          });
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _searchFocus.requestFocus(),
          );
        },
      },
      child: Focus(
        child: ColoredBox(
          color: AppColors.background,
          child: ListenableBuilder(
            listenable: model,
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 260,
                  child: _Explorer(
                    options: options,
                    selected: selected,
                    model: model,
                    isAlive: alive,
                    onSelect: (o) => _select(ws, o),
                    onOpen: (p) => _open(model, p),
                    onAction: (a, e) => _treeAction(model, a, e),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TabsBar(model: model, onClose: (t) => _close(model, t)),
                      for (final s in active.take(1))
                        _AgentBanner(
                          session: s,
                          onPause: () async {
                            await ref
                                .read(sessionManagerProvider.notifier)
                                .stop(s.id);
                            _snack(
                              'Agente pausado. Retome pela tela de Sessões.',
                            );
                          },
                          onOpen: () {
                            ref
                                .read(selectedSessionProvider.notifier)
                                .select(s.id);
                            ref
                                .read(navigationProvider.notifier)
                                .go(AppSection.sessions);
                          },
                        ),
                      if (model.activeTab?.externalChange ?? false)
                        _ExternalChangeBanner(
                          tab: model.activeTab!,
                          onReload: () => model.reload(model.activeTab!),
                          onKeep: () => model.keepMine(model.activeTab!),
                        ),
                      _Breadcrumb(
                        tab: model.activeTab,
                        rootLabel: selected.isRoot,
                      ),
                      Expanded(child: _editor(model)),
                      _BottomPanel(
                        path: selected.path,
                        root: ws.path,
                        files: model.index.files,
                        searchFocus: _searchFocus,
                        onOpenAt: (p, line) async {
                          final r = await model.openAt(p, line);
                          if (r case NotOpened(:final reason)) _snack(reason);
                        },
                        open: _panelOpen,
                        tab: _panelTab,
                        onTab: (i) => setState(() {
                          _panelTab = i;
                          _panelOpen = true;
                        }),
                        onToggle: () =>
                            setState(() => _panelOpen = !_panelOpen),
                      ),
                      _StatusBar(tab: model.activeTab),
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

  Widget _editor(CodeWorktreeModel m) {
    final tab = m.activeTab;
    if (tab == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              m.loading ? 'Carregando arquivos…' : 'Nenhum arquivo aberto',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Escolha um arquivo na árvore ou use Ctrl P.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }
    return AppCodeEditor(
      key: ObjectKey(tab),
      controller: tab.controller,
      editorKey: CodeScreen.editorKey,
      language: tab.language,
      lineMarks: tab.marks,
      onSave: () => _save(m, tab),
    );
  }
}

// --- explorer ------------------------------------------------------------------------

class _Explorer extends StatelessWidget {
  const _Explorer({
    required this.options,
    required this.selected,
    required this.model,
    required this.isAlive,
    required this.onSelect,
    required this.onOpen,
    required this.onAction,
  });

  final List<WorktreeOption> options;
  final WorktreeOption selected;
  final CodeWorktreeModel model;
  final bool Function(String) isAlive;
  final ValueChanged<WorktreeOption> onSelect;
  final ValueChanged<String> onOpen;
  final void Function(TreeAction, TreeEntry?) onAction;

  @override
  Widget build(BuildContext context) {
    Widget iconBtn(String key, String tip, AppIconData icon, TreeAction a) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: ValueKey(key),
            onTap: () => onAction(a, null),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: AppIcon(icon, size: 14, color: AppColors.textSecondary),
              ),
            ),
          ),
        );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('WORKTREE', style: sectionTitleStyle),
                const SizedBox(height: 8),
                WorktreeSelector(
                  options: options,
                  selected: selected,
                  onSelect: onSelect,
                  isAlive: isAlive,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text('ARQUIVOS', style: sectionTitleStyle),
                ),
                iconBtn(
                  'code-new-file',
                  'Novo arquivo',
                  AppIcons.plus,
                  TreeAction.newFile,
                ),
                iconBtn(
                  'code-new-folder',
                  'Nova pasta',
                  AppIcons.folder,
                  TreeAction.newFolder,
                ),
              ],
            ),
          ),
          Expanded(
            child: FileTree(model: model, onOpen: onOpen, onAction: onAction),
          ),
        ],
      ),
    );
  }
}

// --- tabs / banners ------------------------------------------------------------------

class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.model, required this.onClose});

  final CodeWorktreeModel model;
  final ValueChanged<CodeTab> onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, t) in model.tabs.indexed)
            _TabChip(
              tab: t,
              active: i == model.active,
              onTap: () => model.activate(i),
              onClose: () => onClose(t),
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final CodeTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tab.path,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: ValueKey('code-tab-${tab.path}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.background : Colors.transparent,
            border: Border(
              right: const BorderSide(color: AppColors.border),
              top: BorderSide(
                color: active ? AppColors.amber : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.name,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: active ? AppColors.text : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              if (tab.dirty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Dot(
                    AppColors.amber,
                    size: 7,
                    key: ValueKey('code-tab-dirty'),
                  ),
                ),
              InkWell(
                key: ValueKey('code-tab-close-${tab.path}'),
                onTap: onClose,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon(
                    AppIcons.close,
                    size: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, required this.actions});

  final Widget text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: const BoxDecoration(
      color: SessionColors.approvalBg,
      border: Border(bottom: BorderSide(color: SessionColors.approvalBorder)),
    ),
    child: Row(
      children: [
        AppIcon(AppIcons.warning, size: 14, color: AppColors.amber),
        const SizedBox(width: 10),
        Expanded(child: text),
        for (final a in actions) ...[const SizedBox(width: 10), a],
      ],
    ),
  );
}

class _AgentBanner extends StatelessWidget {
  const _AgentBanner({
    required this.session,
    required this.onPause,
    required this.onOpen,
  });

  final Session session;
  final VoidCallback onPause;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Banner(
    key: const ValueKey('code-agent-banner'),
    text: Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'O agente da sessão '),
          TextSpan(
            text: sessionTitle(session),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const TextSpan(
            text:
                ' está trabalhando neste worktree. Ao salvar, sua alteração é '
                'avisada a ele.',
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.text),
    ),
    actions: [
      SmallButton(
        key: const ValueKey('code-pause-agent'),
        label: 'Pausar agente',
        height: 28,
        color: AppColors.amber,
        border: SessionColors.approvalBorder,
        background: Colors.transparent,
        onTap: onPause,
      ),
      InkWell(
        key: const ValueKey('code-open-session'),
        onTap: onOpen,
        child: const Text(
          'Ver sessão',
          style: TextStyle(fontSize: 12, color: AppColors.amber),
        ),
      ),
    ],
  );
}

class _ExternalChangeBanner extends StatelessWidget {
  const _ExternalChangeBanner({
    required this.tab,
    required this.onReload,
    required this.onKeep,
  });

  final CodeTab tab;
  final VoidCallback onReload;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => _Banner(
    key: const ValueKey('code-external-banner'),
    text: Text(
      '${tab.name} mudou no disco (outro processo ou o agente) e você tem '
      'alterações não salvas.',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.text),
    ),
    actions: [
      SmallButton(
        key: const ValueKey('code-external-reload'),
        label: 'Recarregar',
        height: 28,
        onTap: onReload,
      ),
      SmallButton(
        key: const ValueKey('code-external-keep'),
        label: 'Manter as minhas',
        height: 28,
        onTap: onKeep,
      ),
    ],
  );
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.tab, required this.rootLabel});

  final CodeTab? tab;

  /// Workspace root: green = changed since HEAD (no session merge-base).
  final bool rootLabel;

  @override
  Widget build(BuildContext context) {
    final parts = tab?.path.split('/') ?? const <String>[];
    const style = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11,
      color: AppColors.textSecondary,
    );
    Widget legend(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 3, height: 12, color: c),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (final (i, p) in parts.indexed) ...[
                    if (i > 0) const TextSpan(text: '  ›  '),
                    TextSpan(
                      text: p,
                      style: i == parts.length - 1
                          ? const TextStyle(color: AppColors.text)
                          : null,
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Tooltip(
            message: rootLabel
                ? 'Linhas diferentes do HEAD'
                : 'Linhas diferentes do merge-base da sessão',
            child: legend(
              CodeMarkColors.agent,
              rootLabel ? 'alterado (git)' : 'alterado pelo agente',
            ),
          ),
          const SizedBox(width: 10),
          legend(CodeMarkColors.user, 'sua edição'),
          const SizedBox(width: 12),
          const ZoomControl(editorKey: CodeScreen.editorKey),
        ],
      ),
    );
  }
}

// --- bottom panel / status -----------------------------------------------------------

class _BottomPanel extends ConsumerWidget {
  const _BottomPanel({
    required this.path,
    required this.root,
    required this.files,
    required this.open,
    required this.tab,
    required this.onTab,
    required this.onToggle,
    required this.onOpenAt,
    this.searchFocus,
  });

  final String path;

  /// Workspace root (its config has `lint:`).
  final String root;
  final List<String> files;
  final bool open;

  /// 0 terminal, 1 problemas, 2 git, 3 busca.
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onToggle;
  final void Function(String path, int line) onOpenAt;
  final FocusNode? searchFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget tabBtn(int i, String label) => InkWell(
      key: ValueKey('code-panel-tab-$i'),
      onTap: () => onTab(i),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: open && tab == i ? AppColors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: open && tab == i ? AppColors.text : AppColors.textSecondary,
          ),
        ),
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        color: SessionColors.terminalPanel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: open
                ? const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  )
                : null,
            child: Row(
              children: [
                tabBtn(0, 'Terminal'),
                tabBtn(
                  1,
                  'Problemas · ${ref.watch(problemsProvider(path).select((s) => s.problems.length))}',
                ),
                tabBtn(2, 'Git'),
                tabBtn(3, 'Busca'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  key: const ValueKey('code-panel-toggle'),
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AppIcon(
                      open ? AppIcons.chevronDown : AppIcons.chevronUp,
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (open)
            SizedBox(
              height: 180,
              child: switch (tab) {
                0 => _TerminalBody(path: path),
                1 => ProblemsBody(worktree: path, root: root, onOpen: onOpenAt),
                2 => GitBody(worktree: path, onOpen: (p) => onOpenAt(p, 1)),
                _ => SearchBody(
                  root: path,
                  files: files,
                  onOpen: onOpenAt,
                  focus: searchFocus,
                ),
              },
            ),
        ],
      ),
    );
  }
}

class _TerminalBody extends ConsumerWidget {
  const _TerminalBody({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = ref.watch(worktreeTerminalsProvider)[path];
    final auto = ref.watch(codeTerminalAutoStartProvider);
    if (term == null && auto) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(worktreeTerminalsProvider.notifier).open(path);
        }
      });
    }
    if (term == null || !term.running) {
      return Center(
        child: SmallButton(
          key: const ValueKey('code-terminal-open'),
          label: term == null ? 'Abrir terminal' : 'Reabrir terminal',
          onTap: () => ref.read(worktreeTerminalsProvider.notifier).open(path),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: AppTerminalView(term: term, autofocus: false, fontSize: 12),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.tab});

  final CodeTab? tab;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11,
      color: AppColors.textSecondary,
    );
    final t = tab;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (t != null)
            ListenableBuilder(
              listenable: t.controller,
              builder: (context, _) {
                final sel = t.controller.selection;
                return Text(
                  'Ln ${sel.extentIndex + 1}, Col ${sel.extentOffset + 1}'
                  '  ·  ${t.language.label}  ·  UTF-8  ·  '
                  '${t.crlf ? 'CRLF' : 'LF'}',
                  key: const ValueKey('code-status-position'),
                  style: style,
                );
              },
            ),
          const Spacer(),
          const Flexible(
            child: Text(
              'Ctrl S salvar · Ctrl W fechar · Ctrl P arquivo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
