import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  Text(
                    e.description,
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
        if (widget.workspacePath != null)
          group('Projeto', '.claude/skills', [
            if (project.isEmpty) const _Hint('Nenhuma.'),
            ...project,
          ]),
        group('Global', '~/.claude/skills', [
          if (global.isEmpty) const _Hint('Nenhuma.'),
          ...global,
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
            'Skills de plugins e as embutidas vêm do Claude Code e são só '
            'para leitura.',
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
