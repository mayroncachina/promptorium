import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_root.dart';
import '../../data/providers.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';

/// Workspace selector opened from the title bar: lists the registered
/// workspaces, selects one, removes one or adds a git folder (typed path or
/// native folder chooser).
Future<void> showWorkspacePicker(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const WorkspacePicker(),
);

class WorkspacePicker extends ConsumerStatefulWidget {
  const WorkspacePicker({super.key});

  @override
  ConsumerState<WorkspacePicker> createState() => _WorkspacePickerState();
}

class _WorkspacePickerState extends ConsumerState<WorkspacePicker> {
  final _path = TextEditingController();
  bool _adding = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  WorkspaceActions get _actions => ref.read(workspaceActionsProvider);

  Future<void> _select(Workspace w) async {
    await _actions.select(w.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _actions.addFolder(_path.text);
      if (mounted) Navigator.of(context).pop();
    } on InvalidWorkspaceFolder catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Falha ao adicionar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the folder chooser (starting at the typed path, if it exists) and
  /// adds the chosen folder right away; cancelling keeps the form as is.
  Future<void> _browse() async {
    if (_busy) return;
    final typed = expandHome(_path.text.trim());
    final start = typed.isNotEmpty && Directory(typed).existsSync()
        ? typed
        : Platform.environment['HOME'];
    final String? picked;
    try {
      picked = await ref.read(directoryPickerProvider)(initialDirectory: start);
    } catch (e) {
      if (mounted) setState(() => _error = 'Falha ao abrir o seletor: $e');
      return;
    }
    if (picked == null || !mounted) return;
    _path.text = picked;
    await _add();
  }

  @override
  Widget build(BuildContext context) {
    final workspaces = ref.watch(workspacesProvider);
    final active = ref.watch(activeWorkspaceProvider);
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Material(
        key: const ValueKey('workspace-picker'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  'Workspaces',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: switch (workspaces) {
                  AsyncData(:final value) when value.isEmpty => const _Hint(
                    'Nenhum workspace. Adicione a pasta de um repositório git.',
                  ),
                  AsyncData(:final value) => ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final w in value)
                        _WorkspaceRow(
                          workspace: w,
                          active: w.id == active?.id,
                          onTap: () => _select(w),
                          onRemove: () => _actions.remove(w.id),
                        ),
                    ],
                  ),
                  AsyncError(:final error) => _Hint('Erro: $error'),
                  _ => const _Hint('Carregando…'),
                },
              ),
              const Divider(height: 1),
              if (_adding) _addForm() else _addButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addButton() => InkWell(
    key: const ValueKey('workspace-add'),
    onTap: () => setState(() => _adding = true),
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          AppIcon(AppIcons.plus, size: 14, color: AppColors.amber),
          const SizedBox(width: 8),
          const Text(
            'Adicionar pasta…',
            style: TextStyle(fontSize: 13, color: AppColors.amber),
          ),
        ],
      ),
    ),
  );

  Widget _addForm() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Caminho do repositório git',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('workspace-path-field'),
                controller: _path,
                autofocus: true,
                enabled: !_busy,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '~/workspace/projeto',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                key: const ValueKey('workspace-browse'),
                onPressed: _busy ? null : _browse,
                icon: AppIcon(AppIcons.folder, size: 14),
                label: const Text('Procurar…'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _adding = false;
                      _error = null;
                    }),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('workspace-add-confirm'),
              onPressed: _busy ? null : _add,
              child: Text(_busy ? 'Verificando…' : 'Adicionar'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.workspace,
    required this.active,
    required this.onTap,
    required this.onRemove,
  });

  final Workspace workspace;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('workspace-item-${workspace.id}'),
      onTap: onTap,
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.amberTint : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            AppIcon(
              AppIcons.folder,
              size: 16,
              color: active ? AppColors.amber : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workspace.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: active ? AppColors.amber : AppColors.text,
                    ),
                  ),
                  Text(
                    workspace.path,
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
            if (active)
              AppIcon(AppIcons.check, size: 14, color: AppColors.amber),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Remover da lista (não apaga arquivos)',
              child: InkWell(
                key: ValueKey('workspace-remove-${workspace.id}'),
                onTap: onRemove,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AppIcon(
                    AppIcons.close,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    ),
  );
}
