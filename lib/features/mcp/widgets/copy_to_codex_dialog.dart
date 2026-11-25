import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../agents/widgets/agent_style.dart'
    show FieldLabel, agentFieldDecoration;
import '../../sessions/widgets/session_style.dart';
import '../codex_mcp_cli.dart';
import '../codex_mcp_state.dart';
import '../copy_to_codex.dart';
import '../mcp_cli.dart';
import '../mcp_config.dart';

/// "Copiar para o Codex" (SPEC-105 R6). Returns true after the copy.
Future<bool?> showCopyToCodexDialog(
  BuildContext context, {
  required McpServerConfig config,
  required String? cwd,
  required String? workspacePath,
  String? workspaceName,
}) => showAppDialog<bool>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => CopyToCodexDialog(
    config: config,
    cwd: cwd,
    workspacePath: workspacePath,
    workspaceName: workspaceName,
  ),
);

class CopyToCodexDialog extends ConsumerStatefulWidget {
  const CopyToCodexDialog({
    super.key,
    required this.config,
    required this.cwd,
    required this.workspacePath,
    this.workspaceName,
  });

  final McpServerConfig config;

  /// cwd of the `codex mcp` commands.
  final String? cwd;
  final String? workspacePath;
  final String? workspaceName;

  @override
  ConsumerState<CopyToCodexDialog> createState() => _CopyToCodexDialogState();
}

class _CopyToCodexDialogState extends ConsumerState<CopyToCodexDialog> {
  ClaudeMcpRawEntry? _raw;
  bool _rawRead = false;
  final _values = <String, TextEditingController>{};
  final _tokenVar = TextEditingController();
  bool _copyValues = false;
  bool _busy = false;
  String? _error;

  McpServerConfig get c => widget.config;

  @override
  void initState() {
    super.initState();
    for (final k in c.envKeys) {
      _values[k] = TextEditingController();
    }
    _tokenVar.text = planCodexCopy(c, null).defaultTokenVar;
    readClaudeMcpRaw(c, workspacePath: widget.workspacePath).then((raw) {
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _rawRead = true;
      });
    });
  }

  @override
  void dispose() {
    // Clear what was typed or copied before dropping the controllers.
    for (final t in _values.values) {
      t
        ..clear()
        ..dispose();
    }
    _tokenVar.dispose();
    super.dispose();
  }

  CodexCopyPlan get _plan => planCodexCopy(c, _raw);

  CodexMcpAddRequest _request() => codexCopyRequest(
    _plan,
    _raw,
    envValues: {for (final e in _values.entries) e.key: e.value.text},
    tokenVar: _tokenVar.text,
  );

  String? _preview() {
    try {
      return codexMcpAddPreview(_request());
    } catch (_) {
      return null;
    }
  }

  void _setCopyValues(bool on) {
    setState(() {
      _copyValues = on;
      for (final MapEntry(:key, :value) in _values.entries) {
        value.text = on ? _raw?.env[key] ?? '' : '';
      }
    });
  }

  Future<void> _copy({CodexMcpServer? replacing}) async {
    if (replacing != null) {
      final ok = await showAppDialog<bool>(
        context: context,
        barrierColor: AppColors.scrim,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('mcp-copy-replace-confirm'),
          backgroundColor: AppColors.panel,
          title: Text(
            'Substituir ${c.name} no Codex?',
            style: const TextStyle(fontSize: 15),
          ),
          content: Text(
            'Executa codex mcp remove ${c.name} e depois o codex mcp add '
            'mostrado. A configuração atual do Codex se perde.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              key: const ValueKey('mcp-copy-replace-ok'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Substituir',
                style: TextStyle(color: AppColors.red),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final req = _request();
      final cli = ref.read(codexMcpCliProvider);
      if (replacing != null) await cli.remove(c.name, widget.cwd);
      final r = await cli.add(req, widget.cwd);
      ref
        ..invalidate(codexMcpListProvider(widget.cwd))
        ..invalidate(codexMcpStatusProvider(widget.cwd));
      // R6: open the Codex tab with the server selected; its status is
      // read there (R2).
      ref
          .read(selectedCodexMcpServerProvider.notifier)
          .select('codex:${c.name}');
      await selectMcpProviderTab(ref, McpProviderTab.codex);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(r.message)));
      Navigator.of(context).pop(true);
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
    final plan = _plan;
    final codexAsync = ref.watch(codexMcpListProvider(widget.cwd));
    final existing = codexAsync.value
        ?.where((s) => s.name == c.name)
        .firstOrNull;
    final blocker =
        plan.blocker ??
        (codexAsync.hasError
            ? 'Codex indisponível: ${codexAsync.error}'
            : null);
    final preview = _preview();
    CodexMcpAddRequest? req;
    try {
      req = _request();
    } catch (_) {}
    final ready =
        _rawRead && codexAsync.hasValue && blocker == null && preview != null;
    final ws = widget.workspaceName;
    final scopeLabel = switch (c.scope) {
      McpScope.user => 'Global · ~/.claude.json',
      McpScope.project => 'Projeto · .mcp.json',
      McpScope.local => 'Local · ~/.claude.json',
    };

    final rows = <(String, String, String, String?)>[
      ('Transporte', c.transport.label, plan.stdio ? 'stdio' : 'http', null),
      if (plan.stdio) ...[
        ('Comando', c.command ?? '—', c.command ?? '—', null),
        ('Argumentos', c.args.join(' '), c.args.join(' '), null),
        for (final k in plan.envKeys)
          (
            'Variáveis',
            '$k = $mcpMask',
            '$k = ${(_values[k]?.text ?? '').isEmpty ? 'preencher' : mcpMask}',
            (_values[k]?.text ?? '').isEmpty
                ? 'valor não copiado'
                : _copyValues
                ? 'copiado do Claude'
                : null,
          ),
      ] else ...[
        ('URL', c.url ?? '—', c.url ?? '—', null),
        if (plan.bearerHeader)
          (
            'Token',
            'Authorization: Bearer $mcpMask',
            '\$${_tokenVar.text.trim()}',
            'valor não copiado',
          ),
      ],
      (
        'Escopo',
        scopeLabel,
        'Global · ~/.codex/config.toml',
        plan.scopeWarning ? 'vale em todos os projetos' : null,
      ),
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          key: const ValueKey('mcp-copy-dialog'),
          color: AppColors.panel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Copiar '),
                              TextSpan(
                                text: c.name,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                ),
                              ),
                              const TextSpan(text: ' para o Codex'),
                            ],
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                  const Text(
                    'Cópia única: mudanças futuras no Claude Code não chegam '
                    'ao Codex.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (blocker != null) ...[
                    _Banner(
                      key: const ValueKey('mcp-copy-blocker'),
                      text: blocker,
                      color: AppColors.red,
                      bg: SessionColors.delBg,
                      border: SessionColors.stopBorder,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (existing != null && blocker == null) ...[
                    _Banner(
                      key: const ValueKey('mcp-copy-exists'),
                      text:
                          'O Codex já tem um servidor ${c.name}. Ele só muda '
                          'se você substituir.',
                      color: AppColors.amber,
                      bg: SessionColors.approvalBg,
                      border: SessionColors.approvalBorder,
                    ),
                    const SizedBox(height: 8),
                    if (req != null)
                      _Table(
                        key: const ValueKey('mcp-copy-diff'),
                        header: const (
                          'Campo',
                          'No Codex hoje',
                          'Vindo do Claude',
                        ),
                        rows: [
                          for (final (f, a, b) in codexCopyDiff(existing, req))
                            (f, a, b, null),
                        ],
                        arrow: false,
                      ),
                    const SizedBox(height: 12),
                  ],
                  _Table(
                    key: const ValueKey('mcp-copy-table'),
                    header: const ('Campo', 'Claude Code', 'Codex'),
                    rows: rows,
                    arrow: true,
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, box) {
                      final values = _ValuesBox(
                        plan: plan,
                        values: _values,
                        tokenVar: _tokenVar,
                        copyValues: _copyValues,
                        canCopyValues: _raw != null && blocker == null,
                        onCopyValues: _setCopyValues,
                        onChanged: () => setState(() {}),
                      );
                      final scope = plan.scopeWarning
                          ? _Banner(
                              key: const ValueKey('mcp-copy-scope'),
                              text:
                                  'No Codex o servidor fica global: no Claude '
                                  'ele vale só para '
                                  '${ws == null ? 'este projeto' : 'o projeto $ws'}. '
                                  'O Codex desta versão não tem escopo de '
                                  'projeto para MCP comprovado.',
                              color: AppColors.amber,
                              bg: SessionColors.approvalBg,
                              border: SessionColors.approvalBorder,
                            )
                          : null;
                      if (scope == null) return values;
                      if (box.maxWidth < 600) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [values, const SizedBox(height: 12), scope],
                        );
                      }
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: values),
                            const SizedBox(width: 12),
                            Expanded(child: scope),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'COMANDO QUE SERÁ EXECUTADO',
                    style: sectionTitleStyle,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SelectableText(
                      blocker != null ? '—' : preview ?? 'codex mcp add …',
                      key: const ValueKey('mcp-copy-preview'),
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      key: const ValueKey('mcp-copy-error'),
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
                        key: const ValueKey('mcp-copy-cancel'),
                        label: 'Cancelar',
                        onTap: _busy ? null : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      if (existing != null)
                        SmallButton(
                          key: const ValueKey('mcp-copy-replace'),
                          label: _busy
                              ? 'Substituindo…'
                              : 'Substituir no Codex',
                          onTap: _busy || !ready
                              ? null
                              : () => _copy(replacing: existing),
                        )
                      else
                        AmberButton(
                          key: const ValueKey('mcp-copy-submit'),
                          label: _busy ? 'Copiando…' : 'Copiar para o Codex',
                          onTap: _busy || !ready ? null : _copy,
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

class _ValuesBox extends StatelessWidget {
  const _ValuesBox({
    required this.plan,
    required this.values,
    required this.tokenVar,
    required this.copyValues,
    required this.canCopyValues,
    required this.onCopyValues,
    required this.onChanged,
  });

  final CodexCopyPlan plan;
  final Map<String, TextEditingController> values;
  final TextEditingController tokenVar;
  final bool copyValues;
  final bool canCopyValues;
  final ValueChanged<bool> onCopyValues;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    final children = <Widget>[
      if (plan.stdio && plan.envKeys.isEmpty)
        const Text('Sem variáveis de ambiente para copiar.', style: small),
      if (plan.stdio)
        for (final k in plan.envKeys) ...[
          FieldLabel('Valor de $k no Codex'),
          TextField(
            key: ValueKey('mcp-copy-value-$k'),
            controller: values[k],
            onChanged: (_) => onChanged(),
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
            decoration: agentFieldDecoration('vazio = não copia o valor'),
          ),
          const SizedBox(height: 8),
        ],
      if (plan.stdio && plan.envKeys.isNotEmpty) ...[
        InkWell(
          key: const ValueKey('mcp-copy-values'),
          onTap: canCopyValues ? () => onCopyValues(!copyValues) : null,
          child: Row(
            children: [
              Checkbox(
                value: copyValues,
                onChanged: canCopyValues
                    ? (v) => onCopyValues(v ?? false)
                    : null,
              ),
              const Flexible(
                child: Text(
                  'Copiar também os valores do Claude Code',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const Text(
          'Se marcar, os valores ficam em texto no ~/.codex/config.toml.',
          style: small,
        ),
      ],
      if (!plan.stdio && plan.bearerHeader) ...[
        const FieldLabel('Variável do token no Codex'),
        TextField(
          key: const ValueKey('mcp-copy-token-var'),
          controller: tokenVar,
          onChanged: (_) => onChanged(),
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
          decoration: agentFieldDecoration('ex.: GITHUB_TOKEN'),
        ),
        const SizedBox(height: 4),
        const Text(
          'O token não é copiado: o Codex o lê dessa variável ao conectar '
          '(--bearer-token-env-var). Defina a variável no ambiente do app.',
          style: small,
        ),
      ],
      if (!plan.stdio && !plan.bearerHeader)
        const Text(
          'Sem token: o Codex usa OAuth se o servidor pedir. Depois de copiar, '
          'use "Entrar" na aba Codex.',
          style: small,
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    required this.color,
    required this.bg,
    required this.border,
  });

  final String text;
  final Color color;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: border),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: color)),
  );
}

/// Campo | A | → | B | note.
class _Table extends StatelessWidget {
  const _Table({
    super.key,
    required this.header,
    required this.rows,
    required this.arrow,
  });

  final (String, String, String) header;
  final List<(String, String, String, String?)> rows;
  final bool arrow;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    const head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );
    Widget cell(String t, TextStyle s, {int flex = 3}) => Expanded(
      flex: flex,
      child: Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: s),
    );
    Widget line(List<Widget> cells) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: cells),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line([
          cell(header.$1.toUpperCase(), head, flex: 2),
          cell(header.$2.toUpperCase(), head),
          if (arrow) const SizedBox(width: 24),
          cell(header.$3.toUpperCase(), head),
          if (arrow) const Expanded(flex: 2, child: SizedBox()),
        ]),
        for (final (f, a, b, note) in rows)
          line([
            cell(f, const TextStyle(fontSize: 12), flex: 2),
            cell(a, mono),
            if (arrow)
              const SizedBox(
                width: 24,
                child: Text('→', style: TextStyle(color: AppColors.textMuted)),
              ),
            cell(
              b,
              mono.copyWith(
                color: b.endsWith('preencher') ? AppColors.amber : null,
              ),
            ),
            if (arrow)
              cell(
                note ?? '',
                TextStyle(
                  fontSize: 11,
                  color: note == 'vale em todos os projetos'
                      ? AppColors.amber
                      : AppColors.textSecondary,
                ),
                flex: 2,
              ),
          ]),
      ],
    );
  }
}
