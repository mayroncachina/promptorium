import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fs/dir_watcher.dart';
import '../../data/providers.dart';
import '../agents/agent_repository.dart';
import '../project/project_config.dart';
import '../project/project_memory.dart';
import '../sessions/agent_names.dart';
import '../skills/skill_repository.dart';
import 'spec_service.dart';

/// Watches the active workspace's specs folder, `.claude/agents`,
/// `.claude/skills` and `.promptorium` (F11; no polling): the lists reload
/// when their files change. State = specs whose file changed while they
/// ran: the card asks to confirm and no new step starts until then.
class WorkspaceWatcher extends Notifier<Set<int>> {
  DirWatcher? _watcher;
  Workspace? _ws;

  /// Text of each spec file when its last step session started.
  final Map<int, int> _started = {};

  @override
  Set<int> build() {
    ref.onDispose(() => _watcher?.close());
    ref.listen(
      activeWorkspaceProvider,
      (_, ws) => _watch(ws),
      fireImmediately: true,
    );
    return const {};
  }

  void _watch(Workspace? ws) {
    if (ws?.path == _ws?.path) return;
    _ws = ws;
    unawaited(_watcher?.close());
    _watcher = null;
    if (ws == null) return;
    _watcher = DirWatcher(_dirs(ws), onChange: (p) => _changed(ws, p));
  }

  static List<String> _dirs(Workspace ws) {
    final root = ws.path;
    final skills = Directory('$root/.claude/skills');
    return [
      '$root/${ProjectConfig.loadSync(root).specsDir}',
      '$root/.claude/agents',
      skills.path,
      if (skills.existsSync())
        for (final e in skills.listSync())
          if (e is Directory) e.path,
      '$root/.promptorium',
      '$root/.claude',
      root,
    ];
  }

  Future<void> _changed(Workspace ws, Set<String> paths) async {
    if (!ref.mounted) return;
    final root = ws.path;
    final specsDir = '$root/${ProjectConfig.loadSync(root).specsDir}';
    bool under(String dir) => paths.any((p) => p.startsWith('$dir/'));
    // Folders created after the start (e.g. the first agent).
    _watcher?.update(_dirs(ws));
    if (under('$root/.claude/agents') || under('$root/.claude')) {
      ref
        ..invalidate(agentListProvider(root))
        ..invalidate(agentEntriesProvider(root));
    }
    if (under('$root/.claude/skills')) {
      ref.invalidate(skillEntriesProvider(root));
    }
    if (under('$root/.promptorium')) {
      ref
        ..invalidate(projectConfigProvider(root))
        ..invalidate(projectMemoryProvider(root));
    }
    if (!under(specsDir)) return;
    try {
      await ref.read(specServiceProvider).sync(ws);
      await _checkRunning(ws, paths);
    } catch (e) {
      debugPrint('watch de specs: $e');
    }
  }

  /// A running spec whose file is not what its session got.
  Future<void> _checkRunning(Workspace ws, Set<String> paths) async {
    final specs = await ref
        .read(specsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final changed = <int>{};
    for (final s in specs) {
      final baseline = _started[s.id];
      if (baseline == null || s.stage != SpecStage.running) continue;
      if (!paths.contains('${ws.path}/${s.path}')) continue;
      final text = await ref.read(specServiceProvider).read(ws, s);
      if (text != null && text.hashCode != baseline) changed.add(s.id);
    }
    if (changed.isNotEmpty && ref.mounted) state = {...state, ...changed};
  }

  /// A step session starts with [text] as the spec.
  void markStart(int specId, String text) => _started[specId] = text.hashCode;

  bool changedOnDisk(int specId) => state.contains(specId);

  /// "Confirmar alteração": the next steps use the new text.
  void confirm(int specId) {
    _started.remove(specId);
    state = {...state}..remove(specId);
  }
}

final workspaceWatcherProvider = NotifierProvider<WorkspaceWatcher, Set<int>>(
  WorkspaceWatcher.new,
);
