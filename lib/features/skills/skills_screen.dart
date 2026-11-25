import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/capabilities.dart';
import '../../core/providers/workspace_assets.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/agent_repository.dart' show agentHomeProvider;
import '../mcp/mcp_state.dart' show mcpInventoryProvider;
import '../project/widgets/project_widgets.dart';
import '../sessions/widgets/session_style.dart';
import 'skill_catalog.dart';
import 'skill_repository.dart';
import 'skills_state.dart';
import 'widgets/catalog_view.dart';
import 'widgets/installed_view.dart';
import 'widgets/provider_badge.dart';
import 'widgets/skill_dialogs.dart';

/// Skills: the installed ones (project / global, editable; plugins and
/// built-in ones read-only) and the catalogs on GitHub (read-only: install
/// and update). Canvas "Promptorium — Skills".
class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(skillsTabProvider);
    final ws = ref.watch(activeWorkspaceProvider);
    final entries = ref.watch(skillEntriesProvider(ws?.path));
    final list = entries.value ?? const <SkillEntry>[];
    final repos = ref.watch(catalogReposProvider);
    final repo = ref.watch(selectedCatalogProvider) ?? repos.first;
    final catalogCount = ref
        .watch(catalogSnapshotProvider(repo))
        .value
        ?.skills
        .length;
    final selectedDir = ref.watch(selectedSkillProvider);
    final selected =
        list.where((e) => e.dir == selectedDir).firstOrNull ?? list.firstOrNull;
    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 280,
            decoration: const BoxDecoration(
              color: AppColors.panel,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                  child: _Tabs(
                    tab: tab,
                    installed: list.length,
                    catalog: catalogCount,
                    onChanged: (t) =>
                        ref.read(skillsTabProvider.notifier).set(t),
                  ),
                ),
                Expanded(
                  child: tab == SkillsTab.installed
                      ? _InstalledList(
                          entries: list,
                          selected: selected?.dir,
                          workspacePath: ws?.path,
                        )
                      : const CatalogRepoList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: tab == SkillsTab.catalog
                ? CatalogView(key: ValueKey('catalog-${repo.slug}'), repo: repo)
                : switch (entries) {
                    AsyncError(:final error) => StepEmpty(
                      title: 'Erro ao ler as skills',
                      text: '$error',
                    ),
                    _ when selected != null => InstalledSkillView(
                      key: ValueKey('skill-${selected.dir}'),
                      entry: selected,
                    ),
                    AsyncData() => StepEmpty(
                      key: const ValueKey('skills-empty'),
                      title: 'Nenhuma skill instalada',
                      text:
                          'Crie uma skill ou instale uma do catálogo. Skills '
                          'de projeto ficam em .claude/skills/; as globais, '
                          'em ~/.claude/skills/.',
                      action: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          SmallButton(
                            label: 'Ver o catálogo',
                            height: 34,
                            onTap: () => ref
                                .read(skillsTabProvider.notifier)
                                .set(SkillsTab.catalog),
                          ),
                          AmberButton(
                            label: 'Nova skill',
                            height: 34,
                            onTap: () => showNewSkillDialog(context),
                          ),
                        ],
                      ),
                    ),
                    _ => const SizedBox.shrink(),
                  },
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tab,
    required this.installed,
    required this.catalog,
    required this.onChanged,
  });

  final SkillsTab tab;
  final int installed;
  final int? catalog;
  final ValueChanged<SkillsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(SkillsTab t, String label) {
      final on = t == tab;
      return Expanded(
        child: Material(
          color: on ? AppColors.amberTint : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            key: ValueKey('skills-tab-${t.name}'),
            onTap: () => onChanged(t),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: on ? AppColors.amber : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          item(SkillsTab.installed, 'Instaladas · $installed'),
          item(
            SkillsTab.catalog,
            catalog == null ? 'Catálogo' : 'Catálogo · $catalog',
          ),
        ],
      ),
    );
  }
}

class _InstalledList extends ConsumerStatefulWidget {
  const _InstalledList({
    required this.entries,
    required this.selected,
    required this.workspacePath,
  });

  final List<SkillEntry> entries;
  final String? selected;
  final String? workspacePath;

  @override
  ConsumerState<_InstalledList> createState() => _InstalledListState();
}

class _InstalledListState extends ConsumerState<_InstalledList> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _match(String name, String description) {
    final q = _filter.text.trim().toLowerCase();
    return q.isEmpty ||
        name.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final e in widget.entries)
        if (_match(e.name, e.description)) e,
    ];
    final installedNames = {for (final e in widget.entries) e.name};
    // Skills the CLI sees besides these folders (plugins, built-in): from
    // the free `system/init` probe of the MCP screen.
    // Same key as the MCP screen (shared cache: one probe per workspace).
    final inventory = ref.watch(
      mcpInventoryProvider(
        widget.workspacePath ?? ref.watch(agentHomeProvider),
      ),
    );
    final others = [
      for (final s in inventory.value?.skills ?? const <String>[])
        if (!installedNames.contains(s) && _match(s, '')) s,
    ];
    // SPEC-104 R7, R12: one `skills/list` when the tab opens and on
    // "Atualizar" — the filter never queries.
    final codex = watchCodexSkills(ref, widget.workspacePath);
    final extraRoots = ref
        .watch(codexCapabilitiesProvider)
        .supports(ProviderCapability.skillsExtraRoots);
    final codexOwn = switch (codex.value) {
      CodexSkillsReady(:final inventory) => [
        for (final s in inventory.own)
          if (_match(s.name, s.description)) s,
      ],
      _ => const <CodexSkill>[],
    };
    final orphanErrors = switch (codex.value) {
      CodexSkillsReady(:final inventory) => [
        for (final err in inventory.errors)
          if (!widget.entries.any(
                (e) =>
                    err.path == e.skillMdPath ||
                    err.path.startsWith('${e.dir}/'),
              ) &&
              err.path.contains('/'))
            err,
      ],
      _ => const <CodexSkillError>[],
    };
    final repos = ref.watch(catalogReposProvider);
    final snapshots = {
      for (final r in repos) r: ref.watch(catalogSnapshotProvider(r)).value,
    };
    String badge(SkillEntry e) {
      final o = e.origin;
      if (o == null) return 'local';
      final repo = CatalogRepo.parse(o.repo);
      final latest = snapshots[repo]?.skills
          .where((s) => s.path == o.path)
          .firstOrNull;
      if (latest != null && latest.hash != o.hash) return 'atualizar';
      return e.hasLocalChanges ? 'alterada' : 'catálogo';
    }

    Widget group(String title, String where, List<Widget> items) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Row(
              children: [
                Text(title.toUpperCase(), style: sectionTitleStyle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...items,
        ],
      ),
    );

    Widget item(SkillEntry e) {
      final on = e.dir == widget.selected;
      final b = badge(e);
      final status = codexStatusFor(
        e,
        codex.value,
        extraRoots: extraRoots,
        workspacePath: widget.workspacePath,
      );
      final radius = BorderRadius.circular(8);
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: on ? SessionColors.selectedBg : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: on ? SessionColors.selectedBorder : Colors.transparent,
            ),
          ),
          child: InkWell(
            key: ValueKey('skill-item-${e.scope.name}-${e.name}'),
            onTap: () => ref.read(selectedSkillProvider.notifier).select(e.dir),
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      const ProviderBadge('Claude'),
                      if (status != null) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: ProviderBadge(
                            status.badge,
                            key: ValueKey(
                              'skill-codex-${e.scope.name}-${e.name}',
                            ),
                            tone: codexBadgeTone(status.state),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        b,
                        style: TextStyle(
                          fontSize: 11,
                          color: switch (b) {
                            'atualizar' => AppColors.amber,
                            'catálogo' => AppColors.teal,
                            _ => AppColors.textSecondary,
                          },
                        ),
                      ),
                    ],
                  ),
                  // R9: the error of `skills/list` on its skill.
                  if (status?.state == CodexSkillState.error)
                    Text(
                      'skills/list: ${status!.detail}',
                      key: ValueKey('skill-codex-error-${e.name}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.red,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final project = [
      for (final e in entries)
        if (e.isProject) item(e),
    ];
    final global = [
      for (final e in entries)
        if (!e.isProject) item(e),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('skills-filter'),
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Filtrar skills…',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message:
                    'Relê as pastas e consulta o skills/list do Codex '
                    '(sem prompt ao modelo)',
                child: SmallButton(
                  key: const ValueKey('skills-refresh'),
                  label: 'Atualizar',
                  height: 34,
                  onTap: () {
                    ref.invalidate(skillEntriesProvider(widget.workspacePath));
                    ref.read(codexSkillsReloadProvider.notifier).bump();
                  },
                ),
              ),
            ],
          ),
        ),
        if (widget.workspacePath != null)
          group('Projeto', '.claude/skills', [
            if (project.isEmpty) const _Hint('Nenhuma.'),
            ...project,
          ]),
        group('Global', '~/.claude/skills', [
          if (global.isEmpty) const _Hint('Nenhuma.'),
          ...global,
        ]),
        // R8: the Codex's own skills, read-only.
        group('Do Codex', 'só leitura', [
          if (codex.isLoading) const _Hint('Consultando o Codex…'),
          if (codex.value case CodexSkillsUnavailable(:final reason))
            _Hint('Não foi possível listar ($reason).'),
          if (codex.value is CodexSkillsReady && codexOwn.isEmpty)
            const _Hint('Nenhuma.'),
          // R9: errors of folders the app does not list (no frontmatter).
          for (final err in orphanErrors)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
              child: Text(
                '${err.path.split('/').reversed.skip(1).first}: '
                'skills/list: ${err.message}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.red),
              ),
            ),
          for (final s in codexOwn)
            Padding(
              key: ValueKey('skill-codex-own-${s.name}'),
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      ProviderBadge(
                        s.enabled ? 'Codex' : 'Codex · desligada',
                        tone: s.enabled ? BadgeTone.codex : BadgeTone.muted,
                      ),
                    ],
                  ),
                  Text(
                    s.origin,
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
        ]),
        group('Plugins e embutidas', '${others.length}', [
          if (inventory.isLoading) const _Hint('Consultando o Claude Code…'),
          if (inventory.hasError)
            const _Hint('Não foi possível listar (Claude Code indisponível).'),
          for (final s in others)
            Padding(
              key: ValueKey('skill-builtin-$s'),
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              child: Text(
                s,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ]),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Skills de plugins e as embutidas vêm do Claude Code; as do '
            'grupo Do Codex vêm do skills/list. Todas são só para leitura.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    ),
  );
}
