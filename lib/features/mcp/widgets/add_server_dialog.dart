import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../agents/agent_repository.dart' show agentHomeProvider;
import '../../agents/widgets/agent_style.dart'
    show FieldLabel, TogglePill, agentFieldDecoration;
import '../../sessions/widgets/session_style.dart';
import '../mcp_cli.dart';
import '../mcp_config.dart';
import '../mcp_state.dart';

/// "Adicionar servidor": runs `claude mcp add` (never edits the JSON files).
/// Returns the new server's name.
Future<String?> showAddMcpServerDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => const AddMcpServerDialog(),
    );

class AddMcpServerDialog extends ConsumerStatefulWidget {
  const AddMcpServerDialog({super.key});

  @override
  ConsumerState<AddMcpServerDialog> createState() => _AddMcpServerDialogState();
}

class _AddMcpServerDialogState extends ConsumerState<AddMcpServerDialog> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _pairs = TextEditingController();
  McpScope _scope = McpScope.local;
  McpTransport _transport = McpTransport.stdio;
  bool _busy = false;
  String? _error;

  bool get _stdio => _transport == McpTransport.stdio;

  @override
  void initState() {
    super.initState();
    // Without a workspace only the user scope makes sense.
    if (ref.read(activeWorkspaceProvider) == null) _scope = McpScope.user;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    // Clear the secrets typed by the user before dropping the controller.
    _pairs
      ..clear()
      ..dispose();
    super.dispose();
  }

  McpAddRequest _request() {
    final pairs = parseKeyValues(_pairs.text, header: !_stdio);
    if (_stdio) {
      final words = splitCommandLine(_target.text);
      if (words.isEmpty) throw const McpException('Informe o comando.');
      return McpAddRequest(
        name: _name.text.trim(),
        scope: _scope,
        transport: _transport,
        command: words.first,
        args: words.skip(1).toList(),
        env: pairs,
      );
    }
    return McpAddRequest(
      name: _name.text.trim(),
      scope: _scope,
      transport: _transport,
      url: _target.text.trim(),
      headers: pairs,
    );
  }

  Future<void> _submit() async {
    final ws = ref.read(activeWorkspaceProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final req = _request();
      if (req.scope != McpScope.user && ws == null) {
        throw const McpException(
          'Selecione um workspace para os escopos Projeto e Local.',
        );
      }
      final cwd = ws?.path;
      final runCwd = cwd ?? ref.read(agentHomeProvider);
      await ref.read(mcpCliProvider).add(req, runCwd);
      ref
        ..invalidate(mcpRegistryProvider(cwd))
        ..invalidate(mcpListProvider(runCwd))
        ..invalidate(mcpInventoryProvider(runCwd));
      ref
          .read(selectedMcpServerProvider.notifier)
          .select('${req.scope.name}:${req.name}');
      if (mounted) Navigator.of(context).pop(req.name);
    } on McpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    // Centered and scrollable: fits the 1100×700 minimum window.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          key: const ValueKey('mcp-add-dialog'),
          color: AppColors.panel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Adicionar servidor MCP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Executa claude mcp add — o Claude Code grava a configuração.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Nome'),
                  TextField(
                    key: const ValueKey('mcp-add-name'),
                    controller: _name,
                    autofocus: true,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 13,
                    ),
                    decoration: agentFieldDecoration('ex.: github'),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Escopo'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in McpScope.values)
                        TogglePill(
                          key: ValueKey('mcp-add-scope-${s.name}'),
                          label: s.label,
                          on: _scope == s,
                          onTap: s != McpScope.user && ws == null
                              ? null
                              : () => setState(() => _scope = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _scope == McpScope.user
                        ? 'Global · todos os workspaces (~/.claude.json)'
                        : _scope == McpScope.project
                        ? 'Projeto · ${ws?.name ?? '—'} (.mcp.json, versionado)'
                        : 'Local · ${ws?.name ?? '—'} (privado, ~/.claude.json)',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Tipo'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final t in const [
                        McpTransport.stdio,
                        McpTransport.http,
                        McpTransport.sse,
                      ])
                        TogglePill(
                          key: ValueKey('mcp-add-type-${t.name}'),
                          label: t.label,
                          on: _transport == t,
                          onTap: () => setState(() => _transport = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FieldLabel(_stdio ? 'Comando e argumentos' : 'URL'),
                  TextField(
                    key: const ValueKey('mcp-add-target'),
                    controller: _target,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 13,
                    ),
                    decoration: agentFieldDecoration(
                      _stdio
                          ? 'npx -y @modelcontextprotocol/server-github'
                          : 'https://mcp.exemplo.com/mcp',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FieldLabel(
                    _stdio
                        ? 'Variáveis de ambiente (CHAVE=valor, uma por linha)'
                        : 'Headers (Nome: valor, um por linha)',
                  ),
                  TextField(
                    key: const ValueKey('mcp-add-pairs'),
                    controller: _pairs,
                    minLines: 2,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                    ),
                    decoration: agentFieldDecoration(
                      _stdio ? 'GITHUB_TOKEN=…' : 'Authorization: Bearer …',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Os valores vão direto para o Claude Code; o Promptorium não '
                    'os guarda nem os exibe depois.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      key: const ValueKey('mcp-add-error'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SmallButton(
                        label: 'Cancelar',
                        onTap: _busy ? null : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      AmberButton(
                        key: const ValueKey('mcp-add-submit'),
                        label: _busy ? 'Adicionando…' : 'Adicionar',
                        onTap: _busy ? null : _submit,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
