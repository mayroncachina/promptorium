import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_root.dart';
import '../../core/git/repo_setup.dart';
import '../../data/providers.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';

/// Workspace selector opened from the title bar: lists the registered
/// workspaces, selects one, removes one or adds a git folder (typed path or
/// native folder chooser). A folder that is not a repository can be `git
/// init`-ed (optionally with a remote) or cloned into.
Future<void> showWorkspacePicker(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const WorkspacePicker(),
);

/// What to do with a folder that is not a git repository.
enum _Setup { init, remote, clone }

class WorkspacePicker extends ConsumerStatefulWidget {
  const WorkspacePicker({super.key});

  @override
  ConsumerState<WorkspacePicker> createState() => _WorkspacePickerState();
}

class _WorkspacePickerState extends ConsumerState<WorkspacePicker> {
  final _path = TextEditingController();
  final _url = TextEditingController();
  bool _adding = false;
  bool _busy = false;
  String? _error;

  /// Folder that is not a git repository: the setup choices replace the form.
  String? _setupFolder;
  bool _setupFolderEmpty = false;
  _Setup _setup = _Setup.init;
  bool _commitFiles = true;

  @override
  void dispose() {
    _path.dispose();
    _url.dispose();
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
    } on NotAGitRepository catch (e) {
      if (mounted) _offerSetup(e.path);
    } on InvalidWorkspaceFolder catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Falha ao adicionar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _offerSetup(String folder) {
    var empty = false;
    try {
      empty = ref.read(repoSetupProvider).isEmptyFolder(folder);
    } on FileSystemException {
      // Unreadable folder: git will report it.
    }
    setState(() {
      _setupFolder = folder;
      _setupFolderEmpty = empty;
      _setup = _Setup.init;
      _commitFiles = true;
      _url.clear();
      _error = null;
    });
  }

  Future<void> _runSetup() async {
    final folder = _setupFolder;
    if (_busy || folder == null) return;
    if (_setup != _Setup.init && _url.text.trim().isEmpty) {
      setState(() => _error = 'Informe a URL do repositório.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await switch (_setup) {
        _Setup.init => _actions.initFolder(folder, commitFiles: _commitFiles),
        _Setup.remote => _actions.initFolder(
          folder,
          commitFiles: _commitFiles,
          remoteUrl: _url.text,
        ),
        _Setup.clone => _actions.cloneInto(folder, _url.text),
      };
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = repoSetupError(e));
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
              // Hidden while choosing what to do with a non-git folder.
              if (_setupFolder == null) ...[
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
              ],
              if (_setupFolder != null)
                _setupForm()
              else if (_adding)
                _addForm()
              else
                _addButton(),
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

  /// Shown when the chosen folder is not a git repository.
  Widget _setupForm() {
    final folder = _setupFolder!;
    final clone = _setup == _Setup.clone;
    final (action, busyLabel) = switch (_setup) {
      _Setup.init => ('Iniciar repositório', 'Iniciando…'),
      _Setup.remote => ('Iniciar e conectar', 'Iniciando…'),
      _Setup.clone => ('Clonar', 'Clonando…'),
    };
    final options = [
      (
        _Setup.init,
        'Iniciar um repositório git aqui',
        'git init + commit inicial',
      ),
      (
        _Setup.remote,
        'Iniciar e conectar a um repositório remoto',
        'git init + git remote add origin <url> + commit inicial',
      ),
      (
        _Setup.clone,
        'Clonar um repositório remoto',
        _setupFolderEmpty
            ? 'git clone <url> nesta pasta (vazia)'
            : 'git clone <url> numa subpasta desta pasta',
      ),
    ];
    return Padding(
      key: const ValueKey('workspace-setup'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'A pasta não é um repositório git. O que deseja fazer?',
            style: TextStyle(fontSize: 13, color: AppColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            folder,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          RadioGroup<_Setup>(
            groupValue: _setup,
            onChanged: (v) {
              if (_busy || v == null) return;
              setState(() {
                _setup = v;
                _error = null;
              });
            },
            child: Column(
              children: [
                for (final (value, title, subtitle) in options)
                  RadioListTile<_Setup>(
                    key: ValueKey('workspace-setup-${value.name}'),
                    value: value,
                    enabled: !_busy,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(title, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      subtitle,
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
          if (_setup != _Setup.init) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('workspace-setup-url'),
              controller: _url,
              autofocus: true,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.text,
              ),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'URL do repositório',
                hintText: 'git@github.com:org/projeto.git',
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _runSetup(),
            ),
          ],
          if (clone && _url.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Destino: ${RepoSetup.cloneDestination(folder, _url.text, folderEmpty: _setupFolderEmpty)}',
              key: const ValueKey('workspace-setup-destination'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (!clone && !_setupFolderEmpty) ...[
            const SizedBox(height: 4),
            CheckboxListTile(
              key: const ValueKey('workspace-setup-commit-files'),
              value: _commitFiles,
              enabled: !_busy,
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _commitFiles = v ?? true),
              title: const Text(
                'Incluir os arquivos da pasta no commit inicial',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'As sessões trabalham em worktrees criados a partir de um '
                'commit; desmarcado, elas começam sem os arquivos.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('workspace-setup-error'),
              style: const TextStyle(fontSize: 12, color: AppColors.red),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _setupFolder = null;
                        _error = null;
                      }),
                child: const Text('Voltar'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('workspace-setup-confirm'),
                onPressed: _busy ? null : _runSetup,
                child: Text(_busy ? busyLabel : action),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
