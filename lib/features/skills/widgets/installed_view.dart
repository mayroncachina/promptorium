import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../agents/agent_file.dart';
import '../../project/widgets/project_widgets.dart';
import '../../sessions/new_session_dialog.dart';
import '../../sessions/widgets/session_style.dart';
import '../skill_catalog.dart';
import '../skill_repository.dart';
import '../skills_state.dart';
import 'skill_dialogs.dart';

/// Instaladas: editor of the selected skill's SKILL.md (center) and its
/// files, origin, usage and actions (right).
class InstalledSkillView extends ConsumerStatefulWidget {
  const InstalledSkillView({super.key, required this.entry});

  final SkillEntry entry;

  @override
  ConsumerState<InstalledSkillView> createState() => _InstalledSkillViewState();
}

class _InstalledSkillViewState extends ConsumerState<InstalledSkillView> {
  late final _name = TextEditingController();
  late final _tools = TextEditingController();
  late final _description = TextEditingController();
  late final _body = TextEditingController();
  bool _preview = false;
  bool _saving = false;
  String? _error;

  SkillEntry get e => widget.entry;

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_name, _tools, _description, _body]) {
      c.addListener(_changed);
    }
  }

  @override
  void didUpdateWidget(InstalledSkillView old) {
    super.didUpdateWidget(old);
    if (old.entry.dir != e.dir || old.entry.hash != e.hash) _load();
  }

  void _load() {
    _name.text = e.file.name ?? '';
    _tools.text = _toolsText(e.file.value('allowed-tools'));
    _description.text = e.file.description ?? '';
    _body.text = e.file.body;
    _error = null;
  }

  static String _toolsText(Object? v) => parseToolList(v).join(', ');

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [_name, _tools, _description, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  AgentFile get _edited => e.file
      .withValue('name', _name.text.trim())
      .withValue('description', _description.text.trim())
      .withToolList('allowed-tools', parseToolList(_tools.text))
      .withBody(_body.text);

  bool get _dirty => !_edited.sameContent(e.file);

  String? get _workspacePath => ref.read(activeWorkspaceProvider)?.path;

  void _refresh() => ref.invalidate(skillEntriesProvider(_workspacePath));

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final dir = await ref
          .read(skillRepositoryProvider(_workspacePath))
          .save(_edited, e.scope, previousDir: e.dir);
      ref.read(selectedSkillProvider.notifier).select(dir);
      _refresh();
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDialog(
      context,
      title: 'Remover ${e.name}?',
      text:
          'A pasta ${e.dir} será apagada. Se ela veio de um catálogo, dá '
          'para instalar de novo.',
      action: 'Remover',
    );
    if (!ok) return;
    await ref.read(skillRepositoryProvider(_workspacePath)).delete(e.dir);
    ref.read(selectedSkillProvider.notifier).select(null);
    _refresh();
  }

  Future<void> _copy() async {
    final to = e.isProject ? AgentScope.global : AgentScope.project;
    try {
      final dir = await ref
          .read(skillRepositoryProvider(_workspacePath))
          .copy(e, to);
      ref.read(selectedSkillProvider.notifier).select(dir);
      _refresh();
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    }
  }

  Future<void> _update(CatalogRepo repo, CatalogSkill latest) async {
    if (e.hasLocalChanges) {
      final ok = await confirmDialog(
        context,
        title: 'Substituir as mudanças locais?',
        text:
            'Esta cópia de ${e.name} foi alterada aqui depois de instalada. '
            'Atualizar troca tudo pela versão do catálogo.',
        action: 'Atualizar mesmo assim',
      );
      if (!ok) return;
    }
    try {
      await ref
          .read(skillCatalogProvider)
          .install(
            latest,
            repo,
            ref.read(skillRepositoryProvider(_workspacePath)),
            e.scope,
            overwrite: true,
          );
      _refresh();
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    }
  }

  void _test() {
    showNewSessionDialog(
      context,
      title: 'Testar skill ${e.name}',
      prompt: 'Use a skill `${e.name}` para: ',
    );
  }

  @override
  Widget build(BuildContext context) {
    final origin = e.origin;
    final originRepo = origin == null ? null : CatalogRepo.parse(origin.repo);
    CatalogSkill? latest;
    if (originRepo != null) {
      final snap = ref.watch(catalogSnapshotProvider(originRepo)).value;
      latest = snap?.skills.where((s) => s.path == origin!.path).firstOrNull;
    }
    final update = latest != null && latest.hash != origin!.hash;
    final usage = ref.watch(skillUsageProvider(e.name)).value;
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.text,
    );
    InputDecoration field({String? hint}) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: const OutlineInputBorder(),
    );
    final scopeLabel = e.isProject ? 'Projeto' : 'Global';
    final originLabel = origin == null
        ? 'local'
        : e.hasLocalChanges
        ? 'catálogo · alterada aqui'
        : 'catálogo';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                e.name,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.text,
                                ),
                              ),
                              InfoTag(scopeLabel),
                              InfoTag(originLabel),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.skillMdPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SmallButton(
                            key: const ValueKey('skill-test'),
                            label: 'Testar em sessão',
                            onTap: _dirty ? null : _test,
                          ),
                          AmberButton(
                            key: const ValueKey('skill-save'),
                            label: _saving ? 'Salvando…' : 'Salvar',
                            onTap: _dirty && !_saving ? _save : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (update)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: NoticeBox.warning(
                    key: const ValueKey('skill-update-banner'),
                    text: e.hasLocalChanges
                        ? 'Há uma versão nova no catálogo '
                              '(${origin.commit} → ${latest.commit}), e esta '
                              'cópia foi alterada aqui.'
                        : 'Há uma versão nova no catálogo '
                              '(${origin.commit} → ${latest.commit}).',
                    action: SmallButton(
                      key: const ValueKey('skill-update'),
                      label: 'Atualizar',
                      onTap: () => _update(originRepo!, latest!),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: NoticeBox.error(text: _error!),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('name', style: label),
                              const SizedBox(height: 6),
                              TextField(
                                key: const ValueKey('skill-name'),
                                controller: _name,
                                style: mono,
                                decoration: field(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'allowed-tools (opcional)',
                                style: label,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                key: const ValueKey('skill-tools'),
                                controller: _tools,
                                style: mono,
                                decoration: field(hint: 'Read, Grep'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('description', style: label),
                        const Spacer(),
                        Text(
                          '${_description.text.trim().length}/$skillDescriptionMax',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                _description.text.trim().length >
                                    skillDescriptionMax
                                ? AppColors.red
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('skill-description'),
                      controller: _description,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text,
                      ),
                      decoration: field(),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'É pela descrição que o Claude decide quando usar a '
                      'skill: diga o que ela faz e em que situação usar.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Instruções (corpo do SKILL.md)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: label,
                          ),
                        ),
                        _Toggle(
                          preview: _preview,
                          onChanged: (v) => setState(() => _preview = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(minHeight: 260),
                      decoration: BoxDecoration(
                        color: SessionColors.terminalPanel,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _preview
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: MarkdownBody(
                                data: _body.text,
                                styleSheet: MarkdownStyleSheet.fromTheme(
                                  Theme.of(context),
                                ),
                              ),
                            )
                          : TextField(
                              key: const ValueKey('skill-body'),
                              controller: _body,
                              minLines: 12,
                              maxLines: null,
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 12,
                                height: 1.6,
                                color: AppColors.text,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SidePanel(
          title: 'Arquivos',
          width: 300,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final f in e.files)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(f, style: mono),
                ),
              const SizedBox(height: 16),
              Text('ORIGEM', style: sectionTitleStyle),
              const SizedBox(height: 8),
              if (origin == null)
                const Text(
                  'Criada aqui (não veio de um catálogo).',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                )
              else ...[
                _Row('Repositório', origin.repo),
                _Row('Caminho', origin.path),
                _Row('Commit', origin.commit.isEmpty ? '—' : origin.commit),
                _Row('Mudanças locais', e.hasLocalChanges ? 'sim' : 'nenhuma'),
              ],
              const SizedBox(height: 16),
              Text('USO', style: sectionTitleStyle),
              const SizedBox(height: 8),
              Text(
                usage == null
                    ? '…'
                    : usage.sessions == 0
                    ? 'Ainda não carregada em nenhuma sessão.'
                    : 'Carregada em ${usage.sessions} '
                          '${usage.sessions == 1 ? 'sessão' : 'sessões'}'
                          '${usage.last == null ? '' : ' · última em ${formatDay(usage.last!)}'}.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SmallButton(
                key: const ValueKey('skill-copy'),
                label: e.isProject
                    ? 'Copiar para Global'
                    : 'Copiar para o projeto',
                expand: true,
                onTap: e.isProject || _workspacePath != null ? _copy : null,
              ),
              const SizedBox(height: 8),
              SmallButton(
                key: const ValueKey('skill-remove'),
                label: 'Remover',
                expand: true,
                color: AppColors.red,
                border: SessionColors.stopBorder,
                onTap: _remove,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `15/10 14:20`.
String formatDay(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}

class _Row extends StatelessWidget {
  const _Row(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.preview, required this.onChanged});

  final bool preview;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, bool value) {
      final on = preview == value;
      return Material(
        color: on ? AppColors.amberTint : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: ValueKey('skill-mode-${value ? 'preview' : 'edit'}'),
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: on ? AppColors.amber : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [item('Editar', false), item('Visualizar', true)],
      ),
    );
  }
}
