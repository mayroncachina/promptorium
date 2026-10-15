import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_root.dart';
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_icon.dart';
import 'project_service.dart';

/// "Novo projeto" (step 1 · Pasta e repositório): creates the folder, runs
/// `git init` and opens the Projeto screen on the new workspace.
Future<void> showNewProjectDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const NewProjectDialog(),
);

/// `~/workspace` when it exists, else `$HOME`.
String defaultProjectParent({String? home}) {
  final h = home ?? Platform.environment['HOME'] ?? '/';
  final ws = '$h/workspace';
  return Directory(ws).existsSync() ? ws : h;
}

/// `/home/x/workspace` → `~/workspace`.
String tildePath(String path, {String? home}) {
  final h = home ?? Platform.environment['HOME'];
  if (h == null || h.isEmpty) return path;
  if (path == h) return '~';
  return path.startsWith('$h/') ? '~${path.substring(h.length)}' : path;
}

class NewProjectDialog extends ConsumerStatefulWidget {
  const NewProjectDialog({super.key});

  @override
  ConsumerState<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends ConsumerState<NewProjectDialog> {
  final _name = TextEditingController();
  final _parent = TextEditingController(
    text: tildePath(defaultProjectParent()),
  );
  final _remote = TextEditingController();
  bool _withRemote = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _parent.dispose();
    _remote.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final start = expandHome(_parent.text.trim());
    final picked = await ref.read(directoryPickerProvider)(
      initialDirectory: Directory(start).existsSync()
          ? start
          : Platform.environment['HOME'],
    );
    if (picked != null && mounted) {
      setState(() => _parent.text = tildePath(picked));
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    if (_withRemote && _remote.text.trim().isEmpty) {
      setState(() => _error = 'Informe a URL do repositório remoto.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(projectServiceProvider)
          .createProject(
            parent: _parent.text,
            name: _name.text,
            remoteUrl: _withRemote ? _remote.text : null,
          );
      ref.read(navigationProvider.notifier).go(AppSection.project);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field({String? hint}) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textMuted),
    border: const OutlineInputBorder(),
  );

  static const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    color: AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final target = [
      _parent.text.trim().replaceAll(RegExp(r'/+$'), ''),
      _name.text.trim(),
    ].where((p) => p.isNotEmpty).join('/');
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Material(
        key: const ValueKey('new-project-dialog'),
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
                  'Novo projeto',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Nome da pasta', style: _label),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('new-project-name'),
                      controller: _name,
                      autofocus: true,
                      enabled: !_busy,
                      style: _mono,
                      decoration: _field(hint: 'meu-projeto'),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _create(),
                    ),
                    const SizedBox(height: 14),
                    const Text('Criar dentro de', style: _label),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('new-project-parent'),
                            controller: _parent,
                            enabled: !_busy,
                            style: _mono,
                            decoration: _field(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            key: const ValueKey('new-project-browse'),
                            onPressed: _busy ? null : _browse,
                            icon: AppIcon(AppIcons.folder, size: 14),
                            label: const Text('Procurar…'),
                          ),
                        ),
                      ],
                    ),
                    if (_name.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Será criada: $target',
                        key: const ValueKey('new-project-target'),
                        overflow: TextOverflow.ellipsis,
                        style: _mono.copyWith(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text('Repositório', style: _label),
                    RadioGroup<bool>(
                      groupValue: _withRemote,
                      onChanged: (v) {
                        if (!_busy && v != null) {
                          setState(() => _withRemote = v);
                        }
                      },
                      child: const Column(
                        children: [
                          RadioListTile<bool>(
                            key: ValueKey('new-project-local'),
                            value: false,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Só local',
                              style: TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              'git init + commit inicial',
                              style: TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          RadioListTile<bool>(
                            key: ValueKey('new-project-remote'),
                            value: true,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Local e conectado a um remoto',
                              style: TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              'git init + git remote add origin <url>',
                              style: TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_withRemote) ...[
                      const SizedBox(height: 6),
                      TextField(
                        key: const ValueKey('new-project-remote-url'),
                        controller: _remote,
                        enabled: !_busy,
                        style: _mono,
                        decoration: _field(
                          hint: 'git@github.com:org/projeto.git',
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Cria a pasta, roda git init e faz um commit inicial '
                      'vazio. Depois, o planejamento abre na tela Projeto; '
                      'nada mais é gravado até o fim.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const ValueKey('new-project-error'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('new-project-create'),
                      onPressed: _busy || _name.text.trim().isEmpty
                          ? null
                          : _create,
                      child: Text(_busy ? 'Criando…' : 'Criar e planejar'),
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
}
