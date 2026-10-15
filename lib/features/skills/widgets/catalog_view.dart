import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../project/widgets/project_widgets.dart';
import '../../sessions/widgets/session_style.dart';
import '../skill_catalog.dart';
import '../skill_repository.dart';
import '../skills_state.dart';
import 'installed_view.dart' show formatDay;
import 'skill_dialogs.dart';

/// How a catalog skill relates to the installed ones.
enum CatalogState { notInstalled, installed, update }

/// Installed copy of [s] (same repository and folder), if any.
SkillEntry? installedCopy(
  CatalogSkill s,
  CatalogRepo repo,
  List<SkillEntry> installed,
) {
  for (final e in installed) {
    final o = e.origin;
    if (o != null && CatalogRepo.parse(o.repo) == repo && o.path == s.path) {
      return e;
    }
  }
  return null;
}

CatalogState catalogState(SkillEntry? copy, CatalogSkill s) => copy == null
    ? CatalogState.notInstalled
    : copy.origin!.hash == s.hash
    ? CatalogState.installed
    : CatalogState.update;

/// Catálogo: skills of the selected repository (center) and the selected
/// one with "Instalar" (right). Syncs once when the clone does not exist.
class CatalogView extends ConsumerStatefulWidget {
  const CatalogView({super.key, required this.repo});

  final CatalogRepo repo;

  @override
  ConsumerState<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends ConsumerState<CatalogView> {
  final _search = TextEditingController();
  bool _syncing = false;
  String? _error;
  final Set<CatalogRepo> _autoSynced = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      await ref.read(skillCatalogProvider).sync(widget.repo);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      ref.invalidate(catalogSnapshotProvider(widget.repo));
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(catalogSnapshotProvider(widget.repo));
    final ws = ref.watch(activeWorkspaceProvider);
    final installed =
        ref.watch(skillEntriesProvider(ws?.path)).value ?? const [];
    final s = snap.value;
    if (s != null && !s.cloned && !_syncing && _autoSynced.add(widget.repo)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
    final q = _search.text.trim().toLowerCase();
    final skills = [
      for (final x in s?.skills ?? const <CatalogSkill>[])
        if (q.isEmpty ||
            x.name.contains(q) ||
            x.description.toLowerCase().contains(q))
          x,
    ];
    final selectedName = ref.watch(selectedCatalogSkillProvider);
    final selected =
        skills.where((x) => x.name == selectedName).firstOrNull ??
        skills.firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepHeader(
                title: 'Catálogo',
                subtitle: widget.repo.slug,
                actions: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      key: const ValueKey('catalog-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Buscar no catálogo…',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SmallButton(
                    key: const ValueKey('catalog-sync'),
                    label: _syncing ? 'Sincronizando…' : 'Sincronizar',
                    onTap: _syncing ? null : _sync,
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: NoticeBox.error(text: _error!),
                ),
              Expanded(
                child: switch (s) {
                  null || CatalogSnapshot(cloned: false) => StepEmpty(
                    title: _syncing
                        ? 'Baixando o catálogo…'
                        : 'Não sincronizado',
                    text: _syncing
                        ? 'git clone ${widget.repo.webUrl}'
                        : 'Clique em Sincronizar para baixar o repositório.',
                  ),
                  CatalogSnapshot(empty: true) => StepEmpty(
                    key: const ValueKey('catalog-empty'),
                    title: 'O repositório ainda está vazio',
                    text:
                        'Quando ele tiver pastas <nome>/SKILL.md, elas '
                        'aparecem aqui depois de Sincronizar. Enquanto isso, '
                        'dá para criar skills locais.',
                    action: AmberButton(
                      label: 'Nova skill',
                      height: 34,
                      onTap: () => showNewSkillDialog(context),
                    ),
                  ),
                  _ when skills.isEmpty => StepEmpty(
                    title: q.isEmpty ? 'Nenhuma skill' : 'Nada encontrado',
                    text: q.isEmpty
                        ? 'O repositório não tem pastas <nome>/SKILL.md '
                              '(na raiz ou em skills/).'
                        : 'Nenhuma skill com “$q”.',
                  ),
                  _ => _Grid(
                    skills: skills,
                    repo: widget.repo,
                    installed: installed,
                    selected: selected?.name,
                  ),
                },
              ),
            ],
          ),
        ),
        SidePanel(
          title: 'Skill',
          width: 340,
          child: selected == null
              ? const SizedBox.shrink()
              : _Detail(
                  key: ValueKey('catalog-detail-${selected.name}'),
                  skill: selected,
                  repo: widget.repo,
                  installed: installed,
                ),
        ),
      ],
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.skills,
    required this.repo,
    required this.installed,
    required this.selected,
  });

  final List<CatalogSkill> skills;
  final CatalogRepo repo;
  final List<SkillEntry> installed;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GridView.extent(
    maxCrossAxisExtent: 320,
    childAspectRatio: 1.9,
    padding: const EdgeInsets.all(20),
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    children: [
      for (final s in skills)
        _Card(
          skill: s,
          state: catalogState(installedCopy(s, repo, installed), s),
          scope: installedCopy(s, repo, installed)?.scope,
          selected: s.name == selected,
          onTap: () =>
              ref.read(selectedCatalogSkillProvider.notifier).select(s.name),
        ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.skill,
    required this.state,
    required this.scope,
    required this.selected,
    required this.onTap,
  });

  final CatalogSkill skill;
  final CatalogState state;
  final AgentScope? scope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      CatalogState.update => ('atualização', AppColors.amber),
      CatalogState.installed => (
        'instalada · ${scope == AgentScope.global ? 'global' : 'projeto'}',
        AppColors.teal,
      ),
      CatalogState.notInstalled => ('não instalada', AppColors.textSecondary),
    };
    final radius = BorderRadius.circular(10);
    return Material(
      color: selected ? SessionColors.selectedBg : AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected ? SessionColors.selectedBorder : AppColors.border,
        ),
      ),
      child: InkWell(
        key: ValueKey('catalog-card-${skill.name}'),
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      skill.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  skill.description,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '${skill.files.length} '
                '${skill.files.length == 1 ? 'arquivo' : 'arquivos'} · '
                '${skill.commit}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({
    super.key,
    required this.skill,
    required this.repo,
    required this.installed,
  });

  final CatalogSkill skill;
  final CatalogRepo repo;
  final List<SkillEntry> installed;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  late AgentScope _scope = ref.read(activeWorkspaceProvider) == null
      ? AgentScope.global
      : AgentScope.project;
  bool _busy = false;
  String? _error;

  Future<void> _install(SkillEntry? copy) async {
    if (_busy) return;
    final ws = ref.read(activeWorkspaceProvider);
    final scope = copy?.scope ?? _scope;
    if (copy != null && copy.hasLocalChanges) {
      final ok = await confirmDialog(
        context,
        title: 'Substituir as mudanças locais?',
        text:
            'A cópia instalada de ${widget.skill.name} foi alterada aqui. '
            'Atualizar troca tudo pela versão do catálogo.',
        action: 'Atualizar mesmo assim',
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dir = await ref
          .read(skillCatalogProvider)
          .install(
            widget.skill,
            widget.repo,
            ref.read(skillRepositoryProvider(ws?.path)),
            scope,
            overwrite: copy != null,
          );
      ref.invalidate(skillEntriesProvider(ws?.path));
      ref.read(selectedSkillProvider.notifier).select(dir);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.skill;
    final ws = ref.watch(activeWorkspaceProvider);
    final copy = installedCopy(s, widget.repo, widget.installed);
    final state = catalogState(copy, s);
    String text;
    try {
      text = File('${s.dir}/SKILL.md').readAsStringSync();
    } on FileSystemException {
      text = '';
    }
    final sameName = copy == null
        ? widget.installed
              .where((e) => e.name == s.name && e.scope == _scope)
              .firstOrNull
        : null;
    final (action, enabled) = switch (state) {
      CatalogState.update => ('Atualizar a cópia instalada', true),
      CatalogState.installed => ('Já instalada', false),
      CatalogState.notInstalled =>
        sameName != null
            ? ('Já existe uma skill com esse nome', false)
            : ('Instalar', true),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                s.name,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
              Text(
                '${s.path} · ${s.commit}',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                s.description,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SessionColors.terminalPanel,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  text,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    height: 1.6,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('ARQUIVOS', style: sectionTitleStyle.copyWith(fontSize: 11)),
              const SizedBox(height: 6),
              for (final f in s.files)
                Text(
                  f,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (copy == null) ...[
                const SizedBox(height: 14),
                const Text(
                  'Instalar em',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                RadioGroup<AgentScope>(
                  groupValue: _scope,
                  onChanged: (v) {
                    if (v != null && !_busy) setState(() => _scope = v);
                  },
                  child: Column(
                    children: [
                      RadioListTile<AgentScope>(
                        key: const ValueKey('catalog-target-project'),
                        value: AgentScope.project,
                        enabled: ws != null,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          ws == null ? 'Projeto' : 'Projeto ${ws.name}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '.claude/skills/${s.name}',
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      RadioListTile<AgentScope>(
                        key: const ValueKey('catalog-target-global'),
                        value: AgentScope.global,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Global',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '~/.claude/skills/${s.name}',
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Text(
                  'Instalada em ${copy.dir}'
                  '${copy.origin!.installedAt.millisecondsSinceEpoch == 0 ? '' : ' · ${formatDay(copy.origin!.installedAt)}'}.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                NoticeBox.error(text: _error!),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: AmberButton(
            key: const ValueKey('catalog-install'),
            label: _busy ? 'Instalando…' : action,
            height: 34,
            expand: true,
            onTap: enabled && !_busy ? () => _install(copy) : null,
          ),
        ),
      ],
    );
  }
}

/// Repositories of the Catálogo tab (left column).
class CatalogRepoList extends ConsumerWidget {
  const CatalogRepoList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repos = ref.watch(catalogReposProvider);
    final current = ref.watch(selectedCatalogProvider) ?? repos.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Text('REPOSITÓRIOS', style: sectionTitleStyle),
        ),
        for (final r in repos)
          _RepoItem(
            repo: r,
            selected: r == current,
            onTap: () => ref.read(selectedCatalogProvider.notifier).select(r),
            onRemove: r == defaultCatalog
                ? null
                : () async {
                    await ref.read(catalogReposProvider.notifier).remove(r);
                    if (r == current) {
                      ref
                          .read(selectedCatalogProvider.notifier)
                          .select(defaultCatalog);
                    }
                  },
          ),
        const SizedBox(height: 6),
        SmallButton(
          key: const ValueKey('catalog-add-repo'),
          label: '+ Adicionar repositório',
          color: AppColors.amber,
          expand: true,
          onTap: () => showAddCatalogDialog(context),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 12, 6, 0),
          child: Text(
            'Cada repositório é clonado em ~/.promptorium/catalogs/ e '
            'atualizado com git. Repositórios privados usam as credenciais '
            'do seu git.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _RepoItem extends ConsumerWidget {
  const _RepoItem({
    required this.repo,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final CatalogRepo repo;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(catalogSnapshotProvider(repo)).value;
    final status = switch (s) {
      null => '…',
      CatalogSnapshot(cloned: false) => 'não sincronizado',
      CatalogSnapshot(empty: true) => 'vazio',
      _ =>
        '${s.skills.length} skills · ${s.head ?? ''}'
            '${s.syncedAt == null ? '' : ' · ${formatDay(s.syncedAt!)}'}',
    };
    final radius = BorderRadius.circular(8);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? SessionColors.selectedBg : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? SessionColors.selectedBorder : Colors.transparent,
          ),
        ),
        child: InkWell(
          key: ValueKey('catalog-repo-${repo.slug}'),
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo.slug,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        status,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remover da lista',
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: AppIcon(
                      AppIcons.close,
                      size: 12,
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
}
