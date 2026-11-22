import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/workspace_assets.dart';
import '../../data/providers.dart';
import 'skill_catalog.dart';
import 'skill_repository.dart';

/// UI state of the Skills screen.

enum SkillsTab { installed, catalog }

class SkillsTabController extends Notifier<SkillsTab> {
  @override
  SkillsTab build() => SkillsTab.installed;

  void set(SkillsTab t) => state = t;
}

final skillsTabProvider = NotifierProvider<SkillsTabController, SkillsTab>(
  SkillsTabController.new,
);

/// Folder of the installed skill shown in the editor (null = first).
class SelectedSkill extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? dir) => state = dir;
}

final selectedSkillProvider = NotifierProvider<SelectedSkill, String?>(
  SelectedSkill.new,
);

/// Catalog shown in the Catálogo tab (null = the default one).
class SelectedCatalog extends Notifier<CatalogRepo?> {
  @override
  CatalogRepo? build() => null;

  void select(CatalogRepo r) => state = r;
}

final selectedCatalogProvider = NotifierProvider<SelectedCatalog, CatalogRepo?>(
  SelectedCatalog.new,
);

/// Skill of the catalog shown on the right (null = first).
class SelectedCatalogSkill extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? name) => state = name;
}

final selectedCatalogSkillProvider =
    NotifierProvider<SelectedCatalogSkill, String?>(SelectedCatalogSkill.new);

/// Sessions that loaded a skill (the `Skill` tool with `"skill":"<name>"`).
@immutable
class SkillUsage {
  const SkillUsage({required this.sessions, this.last});

  final int sessions;
  final DateTime? last;
}

final skillUsageProvider = FutureProvider.autoDispose.family<SkillUsage, String>(
  (ref, name) async {
    final db = ref.watch(appDatabaseProvider);
    final row = await db
        .customSelect(
          'SELECT COUNT(DISTINCT session_id) AS n, MAX(created_at) AS last '
          'FROM session_events WHERE type = ? AND json LIKE ? AND json LIKE ?',
          variables: [
            Variable.withString('assistant'),
            Variable.withString('%"name":"Skill"%'),
            Variable.withString('%"skill":"${name.replaceAll('"', '')}"%'),
          ],
          readsFrom: {db.sessionEvents},
        )
        .getSingle();
    final last = row.data['last'];
    return SkillUsage(
      sessions: (row.data['n'] as int?) ?? 0,
      last: last is int
          ? DateTime.fromMillisecondsSinceEpoch(last * 1000)
          : null,
    );
  },
);

/// What the Codex says of an installed Claude skill (SPEC-104 R7, R10):
/// from the `skills/list` of [result]; without the extra roots, "Só Claude
/// Code" unless the skill was linked into `.agents/skills` (plano B).
CodexSkillStatus? codexStatusFor(
  SkillEntry e,
  CodexSkillsResult? result, {
  required bool extraRoots,
  String? workspacePath,
}) {
  // The link only matters in plano B (sync IO: one stat per skill).
  final linked = !extraRoots && e.isProject && workspacePath != null
      ? linkedSkillDir(workspacePath, e.name)
      : null;
  if (!extraRoots && linked == null) {
    return const CodexSkillStatus(
      CodexSkillState.claudeOnly,
      'Só Claude Code: o Codex não recebe as pastas do Claude nesta versão',
    );
  }
  return switch (result) {
    null => null,
    CodexSkillsUnavailable(:final reason) => CodexSkillStatus(
      CodexSkillState.unavailable,
      reason,
    ),
    CodexSkillsReady(:final inventory) => inventory.statusOf(
      e.dir,
      linkedDir: linked,
    ),
  };
}

/// The Codex skills of [workspacePath], queried only once the workspaces
/// have loaded: before that the active one reads as null, and a query for
/// "no workspace" would start one App Server too many (R12).
AsyncValue<CodexSkillsResult> watchCodexSkills(
  WidgetRef ref,
  String? workspacePath,
) {
  if (!ref.watch(workspacesProvider.select((a) => a.hasValue))) {
    return const AsyncLoading();
  }
  return ref.watch(codexSkillsProvider(workspacePath));
}
