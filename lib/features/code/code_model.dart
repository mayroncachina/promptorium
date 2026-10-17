import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/code_editor/app_code_editor.dart';
import '../sessions/session_manager.dart';
import 'worktree_files.dart';

// --- worktrees ------------------------------------------------------------------

/// One entry of the worktree selector: the workspace root (current branch)
/// or a session worktree.
@immutable
class WorktreeOption {
  const WorktreeOption({
    required this.path,
    this.branch,
    this.isRoot = false,
    this.session,
  });

  final String path;
  final String? branch;
  final bool isRoot;

  /// Session working there (the active one first, else the most recent).
  final Session? session;

  String get label => branch ?? folderLabel(path);

  static String folderLabel(String p) => p.split('/').last;
}

/// Statuses that show the "agente trabalhando" banner (with a live process).
bool isActiveStatus(SessionStatus s) =>
    s == SessionStatus.running || s == SessionStatus.waitingApproval;

/// Root + session worktrees (`git worktree list` × `sessions`). Worktrees of
/// other tools (no session) are listed too; bare / prunable ones are not.
List<WorktreeOption> buildWorktreeOptions({
  required String root,
  String? rootBranch,
  required List<GitWorktree> worktrees,
  required List<Session> sessions,
}) {
  Session? sessionAt(String path) {
    final here = sessions.where((s) => s.worktreePath == path).toList();
    if (here.isEmpty) return null;
    return here.firstWhere(
      (s) => isActiveStatus(s.status),
      orElse: () => here.first, // repo orders by startedAt desc
    );
  }

  final out = <WorktreeOption>[
    WorktreeOption(
      path: root,
      branch: rootBranch,
      isRoot: true,
      session: sessionAt(root),
    ),
  ];
  for (final w in worktrees) {
    if (w.path == root || w.bare || w.prunable) continue;
    out.add(
      WorktreeOption(
        path: w.path,
        branch: w.branch,
        session: sessionAt(w.path),
      ),
    );
  }
  return out;
}

/// `git worktree list` of a repository root (Code screen). Invalidate to
/// refresh.
final gitWorktreesProvider = FutureProvider.autoDispose
    .family<List<GitWorktree>, String>(
      (ref, root) => ref.watch(gitServiceFactoryProvider)(root).listWorktrees(),
    );

/// Selected worktree path of a workspace (`app_settings`
/// `code.worktree.<id>`; null = the root).
String? savedCodeWorktree(Ref ref, int workspaceId) => ref
    .read(appSettingsProvider.notifier)
    .get(AppSettingKeys.codeWorktree(workspaceId));

// --- tabs -------------------------------------------------------------------------

/// Colors of the gutter marks (mockup Código: teal = agent, amber = you).
abstract final class CodeMarkColors {
  static const agent = AppColors.teal;
  static const user = AppColors.amber;
}

/// One open file.
class CodeTab {
  CodeTab({
    required this.path,
    required String text,
    required this.crlf,
    required this.stat,
  }) : controller = CodeLineEditingController.fromText(
         text,
         CodeLineOptions(
           lineBreak: crlf ? TextLineBreak.crlf : TextLineBreak.lf,
         ),
       ),
       language = CodeLanguage.forPath(path) {
    savedText = controller.text;
    _savedLines = savedText.split(_lb);
  }

  String path;
  final bool crlf;
  FileStat stat;
  CodeLanguage language;
  final CodeLineEditingController controller;

  /// Text of the file on disk as the controller renders it.
  late String savedText;
  late List<String> _savedLines;

  /// Lines (saved-file coordinates) different from the base (agent).
  Set<int> agentLines = const {};

  /// Changed on disk while there were unsaved edits (Recarregar / Manter).
  bool externalChange = false;

  final marks = ValueNotifier<Map<int, Color>>(const {});

  String get _lb => crlf ? '\r\n' : '\n';

  String get name => path.split('/').last;

  bool get dirty => controller.text != savedText;

  void setSaved(String text) {
    savedText = text;
    _savedLines = text.split(_lb);
  }

  void updateMarks() {
    marks.value = lineMarks<Color>(
      saved: _savedLines,
      current: controller.text.split(_lb),
      agentLines: agentLines,
      agent: CodeMarkColors.agent,
      user: CodeMarkColors.user,
    );
  }

  void dispose() {
    controller.dispose();
    marks.dispose();
  }
}

/// Result of [CodeWorktreeModel.open].
sealed class OpenResult {
  const OpenResult();
}

class Opened extends OpenResult {
  const Opened(this.tab);

  final CodeTab tab;
}

class NotOpened extends OpenResult {
  const NotOpened(this.reason);

  final String reason;
}

/// State of the Code screen for one worktree: file index, expanded folders,
/// open tabs and the disk watch (mtime). Kept while the app runs, so tabs
/// survive switching screens / worktrees.
class CodeWorktreeModel extends ChangeNotifier {
  CodeWorktreeModel(this._ref, this.root)
    : files = WorktreeFiles(
        root,
        git: _ref.read(gitServiceFactoryProvider)(root),
      );

  final Ref _ref;
  final String root;
  final WorktreeFiles files;

  WorktreeIndex index = WorktreeIndex.empty;
  bool loading = false;
  String? error;
  final Set<String> expanded = {};

  /// Folders created in the app (git does not list empty folders).
  final Set<String> _extraDirs = {};
  final List<CodeTab> tabs = [];
  int active = -1;

  /// Base of the green marks (resolved once per [refresh]).
  String? _marksBase;
  String? baseBranch;

  bool _disposed = false;

  CodeTab? get activeTab =>
      active >= 0 && active < tabs.length ? tabs[active] : null;

  CodeTab? tabFor(String path) {
    for (final t in tabs) {
      if (t.path == path) return t;
    }
    return null;
  }

  void _changed() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  /// Reloads files + marks (git). [baseBranch] = session base for the marks.
  Future<void> refresh({bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      _changed();
    }
    try {
      index = await files.index(extraDirs: _extraDirs);
      error = null;
    } catch (e) {
      error = '$e';
    }
    loading = false;
    _changed();
  }

  void setBaseBranch(String? branch) {
    if (branch == baseBranch) return;
    baseBranch = branch;
    _marksBase = null;
    for (final t in tabs) {
      unawaited(_loadAgentLines(t));
    }
  }

  void toggle(String dir) {
    if (!expanded.remove(dir)) expanded.add(dir);
    _changed();
  }

  /// Expands every parent folder of [path].
  void reveal(String path) {
    var i = path.indexOf('/');
    while (i > 0) {
      expanded.add(path.substring(0, i));
      i = path.indexOf('/', i + 1);
    }
    _changed();
  }

  /// Opens [path] with the cursor on [line] (1-based; Problemas, Busca).
  Future<OpenResult> openAt(String path, int line) async {
    final r = await open(path);
    if (r case Opened(:final tab)) {
      final i = (line - 1).clamp(0, tab.controller.lineCount - 1);
      try {
        tab.controller.selection = CodeLineSelection.collapsed(
          index: i,
          offset: 0,
        );
        tab.controller.makeCursorVisible();
      } catch (_) {
        // not laid out yet: the file still opens
      }
    }
    return r;
  }

  Future<OpenResult> open(String path) async {
    final existing = tabFor(path);
    if (existing != null) {
      active = tabs.indexOf(existing);
      _changed();
      unawaited(checkDisk());
      return Opened(existing);
    }
    final FileContent content;
    try {
      content = await files.read(path);
    } on CodeFileException catch (e) {
      return NotOpened(e.message);
    } on FileSystemException catch (e) {
      return NotOpened('Falha ao abrir $path: ${e.message}');
    }
    if (_disposed) return const NotOpened('');
    switch (content) {
      case UnsupportedFileContent(:final reason):
        return NotOpened(reason);
      case TextFileContent(:final text, :final crlf, :final stat):
        final again = tabFor(path); // opened meanwhile
        if (again != null) return Opened(again);
        final tab = CodeTab(path: path, text: text, crlf: crlf, stat: stat);
        _lastText[tab] = tab.controller.text;
        tab.controller.addListener(() => _onEdit(tab));
        tabs.add(tab);
        active = tabs.length - 1;
        reveal(path);
        _changed();
        unawaited(_loadAgentLines(tab));
        return Opened(tab);
    }
  }

  final Map<CodeTab, Timer> _markTimers = {};
  final Map<CodeTab, bool> _lastDirty = {};

  /// Last text seen per tab (the controller also notifies cursor moves).
  final Map<CodeTab, String> _lastText = {};

  void _onEdit(CodeTab tab) {
    final text = tab.controller.text;
    if (_lastText[tab] == text) return;
    _lastText[tab] = text;
    final d = text != tab.savedText;
    if (_lastDirty[tab] != d) {
      _lastDirty[tab] = d;
      _changed();
    }
    _markTimers[tab]?.cancel();
    _markTimers[tab] = Timer(const Duration(milliseconds: 120), () {
      if (!_disposed && tabs.contains(tab)) tab.updateMarks();
    });
  }

  Future<void> _loadAgentLines(CodeTab tab) async {
    _marksBase ??= await files.marksBase(baseBranch);
    final lines = await files.changedLines(tab.path, base: _marksBase!);
    if (_disposed || !tabs.contains(tab)) return;
    tab.agentLines = lines;
    tab.updateMarks();
  }

  void activate(int i) {
    if (i < 0 || i >= tabs.length) return;
    active = i;
    _changed();
    unawaited(checkDisk());
  }

  void close(CodeTab tab) {
    final i = tabs.indexOf(tab);
    if (i < 0) return;
    tabs.removeAt(i);
    _markTimers.remove(tab)?.cancel();
    _lastDirty.remove(tab);
    _lastText.remove(tab);
    tab.dispose();
    if (active >= tabs.length) active = tabs.length - 1;
    if (i < active) active--;
    _changed();
  }

  /// Saves [tab]; returns the session ids notified (active sessions in this
  /// worktree, see [SessionManager.notifyUserEdit]).
  Future<List<String>> save(CodeTab tab, {int? workspaceId}) async {
    final text = tab.controller.text;
    tab.stat = await files.write(tab.path, text);
    tab
      ..setSaved(text)
      ..externalChange = false;
    _lastDirty[tab] = false;
    tab.updateMarks();
    _changed();
    unawaited(refresh(quiet: true));
    unawaited(_loadAgentLines(tab));
    return _notifyAgents(tab.path, workspaceId);
  }

  Future<List<String>> _notifyAgents(String path, int? workspaceId) async {
    if (workspaceId == null) return const [];
    final manager = _ref.read(sessionManagerProvider.notifier);
    final sessions = await _ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(workspaceId)
        .first;
    final notified = <String>[];
    for (final s in sessions) {
      if (s.worktreePath != root || !isActiveStatus(s.status)) continue;
      if (!manager.isAlive(s.id)) continue;
      await manager.notifyUserEdit(s.id, path);
      notified.add(s.id);
    }
    return notified;
  }

  /// Re-reads [tab] from disk (drops unsaved edits), keeping the cursor line.
  Future<void> reload(CodeTab tab) async {
    final FileContent c;
    try {
      c = await files.read(tab.path);
    } catch (e) {
      debugPrint('recarregar ${tab.path}: $e');
      return;
    }
    if (c is! TextFileContent || _disposed || !tabs.contains(tab)) return;
    final sel = tab.controller.selection;
    final text = c.crlf == tab.crlf
        ? c.text
        : c.text
              .replaceAll('\r\n', '\n')
              .replaceAll('\n', tab.crlf ? '\r\n' : '\n');
    tab.controller.text = text;
    tab
      ..stat = c.stat
      ..setSaved(tab.controller.text)
      ..externalChange = false;
    final line = sel.extentIndex.clamp(0, tab.controller.lineCount - 1);
    try {
      tab.controller.selection = CodeLineSelection.collapsed(
        index: line,
        offset: 0,
      );
    } catch (_) {}
    _lastDirty[tab] = false;
    _changed();
    await _loadAgentLines(tab);
  }

  /// "Manter as minhas": stop asking for this disk version.
  Future<void> keepMine(CodeTab tab) async {
    try {
      tab.stat = await files.stat(tab.path);
    } catch (_) {}
    tab.externalChange = false;
    _changed();
  }

  /// Compares mtime / size of every tab with the disk: unchanged tab →
  /// reloaded; tab with unsaved edits → [CodeTab.externalChange].
  Future<void> checkDisk() async {
    for (final tab in tabs.toList()) {
      FileStat st;
      try {
        st = await files.stat(tab.path);
      } catch (_) {
        continue;
      }
      if (st.type == FileSystemEntityType.notFound) continue;
      final changed =
          st.modified != tab.stat.modified || st.size != tab.stat.size;
      if (!changed || tab.externalChange) continue;
      if (tab.dirty) {
        tab.externalChange = true;
        _changed();
      } else {
        await reload(tab);
      }
    }
  }

  // --- tree operations -------------------------------------------------------------

  Future<String> createFile(String rel) async {
    final p = await files.createFile(rel);
    await refresh(quiet: true);
    return p;
  }

  Future<String> createFolder(String rel) async {
    final p = await files.createFolder(rel);
    _extraDirs.add(p);
    expanded.add(p);
    reveal(p);
    await refresh(quiet: true);
    return p;
  }

  Future<String> rename(String from, String to) async {
    final p = await files.rename(from, to);
    for (final t in tabs) {
      if (t.path == from) {
        t
          ..path = p
          ..language = CodeLanguage.forPath(p);
      } else if (t.path.startsWith('$from/')) {
        t.path = '$p/${t.path.substring(from.length + 1)}';
      }
    }
    if (_extraDirs.remove(from)) _extraDirs.add(p);
    await refresh(quiet: true);
    return p;
  }

  Future<void> delete(String rel) async {
    await files.delete(rel);
    for (final t in tabs.toList()) {
      if (t.path == rel || t.path.startsWith('$rel/')) close(t);
    }
    _extraDirs.removeWhere((d) => d == rel || d.startsWith('$rel/'));
    await refresh(quiet: true);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _markTimers.values) {
      t.cancel();
    }
    for (final t in tabs) {
      t.dispose();
    }
    super.dispose();
  }
}

/// One model per worktree path (kept alive; disposed with the container).
final codeWorktreeModelProvider = Provider.family<CodeWorktreeModel, String>((
  ref,
  root,
) {
  final m = CodeWorktreeModel(ref, root);
  ref.onDispose(m.dispose);
  return m;
});
