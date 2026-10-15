import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../agents/agent_file.dart';
import '../skill_catalog.dart';
import '../skill_repository.dart';
import '../skill_writer.dart';
import '../skills_state.dart';

/// Dialogs of the Skills screen (Nova skill, repositório, confirmação).

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-action'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Frame shared by the dialogs: title, body, footer (Cancelar + action).
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.dialogKey,
    required this.title,
    required this.children,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
    this.footerNote,
    this.busy = false,
  });

  final Key dialogKey;
  final String title;
  final List<Widget> children;
  final String actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final String? footerNote;
  final bool busy;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.6),
    child: Material(
      key: dialogKey,
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (footerNote != null)
                    Expanded(
                      child: Text(
                        footerNote!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: actionKey,
                    onPressed: busy ? null : onAction,
                    child: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
const _mono = TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 12,
  color: AppColors.text,
);

InputDecoration _field({String? hint}) => InputDecoration(
  isDense: true,
  hintText: hint,
  hintStyle: const TextStyle(color: AppColors.textMuted),
  border: const OutlineInputBorder(),
);

Widget _errorText(String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          e,
          key: const ValueKey('skill-dialog-error'),
          style: const TextStyle(fontSize: 12, color: AppColors.red),
        ),
      );

// --- Nova skill ------------------------------------------------------------------

enum NewSkillMode { ai, session, blank }

Future<void> showNewSkillDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const NewSkillDialog(),
);

class NewSkillDialog extends ConsumerStatefulWidget {
  const NewSkillDialog({super.key});

  @override
  ConsumerState<NewSkillDialog> createState() => _NewSkillDialogState();
}

class _NewSkillDialogState extends ConsumerState<NewSkillDialog> {
  final _ask = TextEditingController();
  final _name = TextEditingController();
  NewSkillMode _mode = NewSkillMode.ai;
  late AgentScope _scope = ref.read(activeWorkspaceProvider) == null
      ? AgentScope.global
      : AgentScope.project;
  String? _sessionId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ask.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final ws = ref.read(activeWorkspaceProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String dir;
      if (_mode == NewSkillMode.blank) {
        final name = skillSlug(_name.text);
        if (name.isEmpty) throw const SkillException('Informe o nome.');
        dir = await ref
            .read(skillRepositoryProvider(ws?.path))
            .save(
              AgentFile.create(
                name: name,
                description: _ask.text.trim().isEmpty
                    ? 'Descreva o que a skill faz e quando usar.'
                    : _ask.text.trim(),
                body: blankSkillBody(name),
              ),
              _scope,
            );
      } else {
        if (_mode == NewSkillMode.session && _sessionId == null) {
          throw const SkillException('Escolha a sessão.');
        }
        dir = await ref
            .read(skillWriterProvider)
            .write(
              workspace: ws,
              scope: _scope,
              request: _ask.text,
              sessionId: _mode == NewSkillMode.session ? _sessionId : null,
              name: _name.text.trim().isEmpty ? null : _name.text,
            );
      }
      ref.invalidate(skillEntriesProvider(ws?.path));
      ref.read(skillsTabProvider.notifier).set(SkillsTab.installed);
      ref.read(selectedSkillProvider.notifier).select(dir);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    final sessions = ws == null
        ? const <Session>[]
        : ref.watch(sessionsProvider(ws.id)).value ?? const <Session>[];
    final base = _scope == AgentScope.project
        ? '${ws?.name ?? '<projeto>'}/.claude/skills/'
        : '~/.claude/skills/';
    final ai = _mode != NewSkillMode.blank;
    return _DialogFrame(
      dialogKey: const ValueKey('new-skill-dialog'),
      title: 'Nova skill',
      actionKey: const ValueKey('new-skill-create'),
      actionLabel: _busy
          ? (ai ? 'Gerando…' : 'Criando…')
          : (ai ? 'Gerar rascunho' : 'Criar'),
      onAction: _create,
      busy: _busy,
      footerNote: ai ? 'Uma chamada curta ao Claude (centavos).' : null,
      children: [
        const Text('Como começar', style: _label),
        RadioGroup<NewSkillMode>(
          groupValue: _mode,
          onChanged: (v) {
            if (v != null && !_busy) setState(() => _mode = v);
          },
          child: const Column(
            children: [
              RadioListTile<NewSkillMode>(
                key: ValueKey('new-skill-mode-ai'),
                value: NewSkillMode.ai,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Escrever com o Claude',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'Você descreve; o Claude escreve o rascunho do SKILL.md.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              RadioListTile<NewSkillMode>(
                key: ValueKey('new-skill-mode-session'),
                value: NewSkillMode.session,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'A partir de uma sessão',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'Transforma o que deu certo numa sessão em passo a passo.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              RadioListTile<NewSkillMode>(
                key: ValueKey('new-skill-mode-blank'),
                value: NewSkillMode.blank,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Em branco', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  'SKILL.md com frontmatter e seções vazias.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_mode == NewSkillMode.session) ...[
          const SizedBox(height: 10),
          const Text('Sessão', style: _label),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: const ValueKey('new-skill-session'),
            initialValue: _sessionId,
            isExpanded: true,
            decoration: _field(
              hint: sessions.isEmpty ? 'Nenhuma sessão neste workspace' : null,
            ),
            items: [
              for (final s in sessions.take(30))
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    s.title ?? s.branch,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: _busy ? null : (v) => setState(() => _sessionId = v),
          ),
        ],
        const SizedBox(height: 12),
        Text(switch (_mode) {
          NewSkillMode.ai => 'O que a skill deve fazer, e quando usar',
          NewSkillMode.session => 'Foco (opcional)',
          NewSkillMode.blank => 'description (opcional)',
        }, style: _label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('new-skill-ask'),
          controller: _ask,
          enabled: !_busy,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: _field(
            hint: _mode == NewSkillMode.ai
                ? 'Ex.: revisar migrations do Prisma antes do merge, '
                      'procurando perda de dados e índices faltando.'
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ai ? 'Nome (opcional)' : 'Nome', style: _label),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('new-skill-name'),
                    controller: _name,
                    enabled: !_busy,
                    style: _mono,
                    decoration: _field(hint: 'revisar-migration'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Salvar em', style: _label),
                  const SizedBox(height: 6),
                  SegmentedButton<AgentScope>(
                    key: const ValueKey('new-skill-scope'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AgentScope.project,
                        enabled: ws != null,
                        label: const Text('Projeto'),
                      ),
                      const ButtonSegment(
                        value: AgentScope.global,
                        label: Text('Global'),
                      ),
                    ],
                    selected: {_scope},
                    onSelectionChanged: _busy
                        ? null
                        : (s) => setState(() => _scope = s.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$base<nome>/',
                    style: _mono.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        _errorText(_error),
      ],
    );
  }
}

// --- Adicionar repositório -------------------------------------------------------

Future<void> showAddCatalogDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const _AddCatalogDialog(),
);

class _AddCatalogDialog extends ConsumerStatefulWidget {
  const _AddCatalogDialog();

  @override
  ConsumerState<_AddCatalogDialog> createState() => _AddCatalogDialogState();
}

class _AddCatalogDialogState extends ConsumerState<_AddCatalogDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    try {
      final r = await ref.read(catalogReposProvider.notifier).add(_text.text);
      ref.read(selectedCatalogProvider.notifier).select(r);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => _DialogFrame(
    dialogKey: const ValueKey('add-catalog-dialog'),
    title: 'Adicionar repositório de skills',
    actionKey: const ValueKey('add-catalog-confirm'),
    actionLabel: 'Adicionar',
    onAction: _add,
    children: [
      const Text('Repositório no GitHub', style: _label),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('add-catalog-repo'),
        controller: _text,
        autofocus: true,
        style: _mono,
        decoration: _field(hint: 'owner/nome ou https://github.com/owner/nome'),
        onSubmitted: (_) => _add(),
      ),
      const SizedBox(height: 6),
      const Text(
        'Formato esperado: uma pasta por skill com SKILL.md, na raiz '
        '(<nome>/SKILL.md) ou em skills/<nome>/SKILL.md.',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      _errorText(_error),
    ],
  );
}
