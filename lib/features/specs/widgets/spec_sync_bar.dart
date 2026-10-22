import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/provider_preferences.dart';
import '../../../data/providers.dart';
import '../../project/project_config.dart';
import '../spec_service.dart';
import '../spec_verifier.dart';
import '../workspace_watcher.dart';

/// Shared discovery and reconciliation controls for Specs and the Board.
class SpecSyncBar extends ConsumerStatefulWidget {
  const SpecSyncBar({
    super.key,
    required this.workspace,
    required this.specs,
    this.selected,
    this.canVerify = true,
    this.onUpdated,
  });
  final Workspace workspace;
  final List<Spec> specs;
  final Spec? selected;
  final bool canVerify;
  final VoidCallback? onUpdated;
  @override
  ConsumerState<SpecSyncBar> createState() => _SpecSyncBarState();
}

class _SpecSyncBarState extends ConsumerState<SpecSyncBar> {
  VerificationCancellation? _cancel;
  String? _progress;
  bool _syncing = false;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SpecSyncBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.id != widget.workspace.id) _cancel?.cancel();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await ref.read(specServiceProvider).sync(widget.workspace);
      widget.onUpdated?.call();
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showText(String title, String text) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _verify() async {
    final ws = widget.workspace;
    final candidates = widget.specs
        .where(
          (s) =>
              s.stage == SpecStage.backlog &&
              s.worktreePath == null &&
              s.status != SpecStatus.archived,
        )
        .toList();
    final selected = <int>{
      if (widget.selected != null &&
          candidates.any((s) => s.id == widget.selected!.id))
        widget.selected!.id,
    };
    final provider = ref.read(defaultAgentProvider(ws.id));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Verificar implementação'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Provedor: $provider. A análise usa IA e pode consumir créditos. '
                    'Specs com todos os requisitos e critérios comprovados serão marcadas como concluídas. '
                    'Resultados parciais mantêm o estado atual. Você pode cancelar durante a análise.',
                  ),
                  TextButton(
                    onPressed: () => update(() {
                      if (selected.length == candidates.length) {
                        selected.clear();
                      } else {
                        selected.addAll(candidates.map((s) => s.id));
                      }
                    }),
                    child: const Text('Selecionar/desmarcar todas'),
                  ),
                  for (final spec in candidates)
                    CheckboxListTile(
                      dense: true,
                      title: Text('${spec.code} · ${spec.title}'),
                      value: selected.contains(spec.id),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add(spec.id);
                        } else {
                          selected.remove(spec.id);
                        }
                      }),
                    ),
                  if (candidates.isEmpty)
                    const Text(
                      'Nenhuma spec disponível para verificar. Resolva operações em andamento primeiro.',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Verificar e concluir comprovadas'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || widget.workspace.id != ws.id) return;
    final token = VerificationCancellation();
    setState(() => _cancel = token);
    final summaries = <String>[];
    final verifier = ref.read(specVerifierProvider);
    try {
      final queue = candidates.where((s) => selected.contains(s.id)).toList();
      for (final (index, spec) in queue.indexed) {
        token.check();
        if (!mounted) return;
        setState(
          () => _progress =
              'Verificando ${spec.code} (${index + 1}/${queue.length})…',
        );
        try {
          final result = await verifier.verify(ws, spec, token);
          summaries.add(
            '${spec.code}: ${result['complete'] == true ? 'concluída' : 'pendências encontradas'}',
          );
        } catch (e) {
          summaries.add('${spec.code}: $e');
          if (token.cancelled) break;
        }
      }
      if (mounted && widget.workspace.id == ws.id) {
        widget.onUpdated?.call();
        await _showText('Resultado da verificação', summaries.join('\n'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _cancel = null;
          _progress = null;
        });
      }
    }
  }

  /// Repository revision and local changes the analysis looked at.
  static String _repositoryLine(Map<String, dynamic> report) {
    final head = report['repositoryHead'];
    if (head is! String || head.isEmpty) {
      return 'Revisão do repositório: não registrada.';
    }
    String short(Object? hash) {
      final text = '${hash ?? '?'}';
      return text.length > 12 ? text.substring(0, 12) : text;
    }

    final files = report['localChangedFiles'];
    final local = files == 0
        ? 'nenhuma'
        : '${files ?? '?'} arquivo(s) · ${short(report['localChanges'])}';
    return 'Revisão: ${short(head)} · Alterações locais: $local';
  }

  Future<void> _report() async {
    final spec = widget.selected;
    if (spec == null) return;
    final report = await ref
        .read(specVerifierProvider)
        .report(widget.workspace, spec);
    final text = await ref
        .read(specServiceProvider)
        .read(widget.workspace, spec);
    final verified =
        report?['complete'] == true &&
        report?['completedSpecHash'] == specDigest(text ?? '');
    final lines = <String>[
      if (report == null)
        spec.stage == SpecStage.done
            ? 'Conclusão declarada no arquivo; sem verificação pelo agente.'
            : 'Nenhuma verificação registrada.'
      else ...[
        verified
            ? 'Conclusão verificada pelo agente.'
            : 'Relatório anterior; não comprova a conclusão atual.',
        'Provedor: ${report['provider']} · Data: ${report['createdAt']}',
        _repositoryLine(report),
        for (final item in report['items'] as List? ?? []) ...[
          '',
          '${item['id']} · ${item['status'] == 'nao-verificavel' ? 'não verificável' : item['status']}',
          '${item['explanation']}',
          for (final evidence in item['evidence'] as List? ?? [])
            '  ${evidence['path']}: ${evidence['quote']}',
        ],
      ],
    ];
    await _showText('Relatório · ${spec.code}', lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceWatcherProvider);
    ref.listen(activeWorkspaceProvider, (_, ws) {
      if (ws?.id != widget.workspace.id) _cancel?.cancel();
    });
    final ws = widget.workspace;
    final config = ref.watch(projectConfigProvider(ws.path)).value;
    final folder = config?.specsDir ?? ProjectConfig.loadSync(ws.path).specsDir;
    final issues = ref.watch(specSyncIssuesProvider)[ws.id] ?? const <String>[];
    final busy = _cancel != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Pasta de specs: $folder/',
            key: const ValueKey('specs-folder'),
            style: const TextStyle(fontSize: 11),
          ),
          TextButton(
            key: const ValueKey('specs-sync'),
            onPressed: busy || _syncing ? null : _sync,
            child: Text(_syncing ? 'Sincronizando…' : 'Sincronizar specs'),
          ),
          TextButton(
            key: const ValueKey('specs-verify'),
            onPressed: busy || !widget.canVerify ? null : _verify,
            child: const Text('Verificar implementação'),
          ),
          if (widget.selected != null)
            TextButton(
              onPressed: _report,
              child: const Text('Relatório / origem'),
            ),
          if (widget.selected?.stage == SpecStage.done && !busy)
            TextButton(
              onPressed: () async {
                try {
                  await ref
                      .read(specServiceProvider)
                      .reopen(ws, widget.selected!);
                  widget.onUpdated?.call();
                } catch (e) {
                  _message('$e');
                }
              },
              child: const Text('Reabrir'),
            ),
          if (issues.isNotEmpty)
            TextButton(
              key: const ValueKey('specs-sync-issues'),
              onPressed: () =>
                  _showText('Pendências da sincronização', issues.join('\n\n')),
              child: Text('${issues.length} pendência(s)'),
            ),
          if (busy) ...[
            Text(_progress ?? 'Preparando verificação…'),
            TextButton(
              onPressed: _cancel!.cancel,
              child: const Text('Cancelar verificação'),
            ),
          ],
        ],
      ),
    );
  }
}
