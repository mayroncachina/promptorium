import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/agent_repository.dart';
import '../agents/widgets/agent_style.dart' show AgentAvatar, agentTint;
import '../sessions/session_manager.dart';
import '../sessions/widgets/session_style.dart';
import 'mcp_cli.dart';
import 'mcp_config.dart';
import 'mcp_rules.dart';
import 'mcp_state.dart';

/// One row of the server list: a configured entry (any scope) or a server
/// only seen in `system/init` / `claude mcp list` (claude.ai connectors,
/// plugins, `--mcp-config`).
@immutable
class McpServerRow {
  const McpServerRow({
    required this.name,
    this.config,
    this.status,
    this.tools = const [],
    this.overriddenBy,
  });

  final String name;
  final McpServerConfig? config;
  final McpLiveStatus? status;
  final List<String> tools;

  /// Scope that wins over this entry (null = this one is used).
  final McpScope? overriddenBy;

  McpScope? get scope => config?.scope;
  String get key => '${scope?.name ?? 'other'}:$name';
  String get serverKey => mcpServerKey(name);
}

/// Rows of the screen: registry entries + other servers of the status board /
/// inventory. Pure (tested through the widget).
List<McpServerRow> buildMcpRows({
  required McpRegistrySnapshot registry,
  required McpStatusBoardState board,
  McpInventory? inventory,
  List<String> sessionTools = const [],
}) {
  final tools = <String, Set<String>>{};
  inventory?.toolsByServer.forEach(
    (k, v) => tools.putIfAbsent(k, () => {}).addAll(v),
  );
  final known = [
    for (final c in registry.servers) c.name,
    ...board.byName.keys,
    ...?inventory?.servers.map((s) => s.name),
  ];
  for (final t in sessionTools) {
    final p = splitMcpToolId(t, known);
    if (p != null) tools.putIfAbsent(p.server, () => {}).add(p.tool);
  }
  List<String> toolsOf(String name) =>
      (tools[mcpServerKey(name)]?.toList() ?? <String>[])..sort();

  McpLiveStatus? statusOf(String name) {
    final b = board.byName[name];
    if (b != null) return b;
    for (final s in inventory?.servers ?? const []) {
      if (s.name == name) {
        return McpLiveStatus(
          name: name,
          state: McpConnState.fromInit(s.status),
        );
      }
    }
    return null;
  }

  final names = {for (final c in registry.servers) c.name};
  final others = <String>{
    ...board.byName.keys,
    ...?inventory?.servers.map((s) => s.name),
  }.where((n) => !names.contains(n)).toList()..sort();
  return [
    for (final c in registry.servers)
      McpServerRow(
        name: c.name,
        config: c,
        status: c.active ? statusOf(c.name) : null,
        tools: toolsOf(c.name),
        overriddenBy: c.active ? null : registry.effective(c.name)?.scope,
      ),
    for (final n in others)
      McpServerRow(name: n, status: statusOf(n), tools: toolsOf(n)),
  ];
}

Color mcpStateColor(McpConnState? s) => switch (s) {
  McpConnState.connected => AppColors.teal,
  McpConnState.failed => AppColors.red,
  McpConnState.pending || McpConnState.needsAuth => AppColors.amber,
  McpConnState.checking => AppColors.blue,
  _ => AppColors.textMuted,
};

/// Servidores MCP (plano, Fase 11).
class McpScreen extends ConsumerWidget {
  const McpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final cwd = ws?.path;
    final registryAsync = ref.watch(mcpRegistryProvider(cwd));
    // Wait for the workspace list: the CLI resolves project / local scope
    // from the cwd. Started once per workspace and app session (cached).
    final activeId = ref.watch(
      appSettingsProvider,
    )[AppSettingKeys.activeWorkspace];
    final ready = ws != null || int.tryParse(activeId ?? '') == null;
    final runCwd = cwd ?? ref.watch(agentHomeProvider);
    const idle = AsyncValue<Never>.loading();
    final listAsync = ready ? ref.watch(mcpListProvider(runCwd)) : idle;
    final invAsync = ready ? ref.watch(mcpInventoryProvider(runCwd)) : idle;
    final board = ref.watch(mcpStatusBoardProvider);
    final lastInit = ref.watch(
      sessionManagerProvider.select((s) => s.lastInit),
    );
    final registry =
        registryAsync.value ?? const McpRegistrySnapshot(<McpServerConfig>[]);
    final rows = buildMcpRows(
      registry: registry,
      board: board,
      inventory: invAsync.value,
      sessionTools: lastInit?.tools ?? const [],
    );
    final checking = listAsync.isLoading || invAsync.isLoading;
    final selectedKey = ref.watch(selectedMcpServerProvider);
    McpServerRow? selected;
    for (final r in rows) {
      if (r.key == selectedKey) selected = r;
    }
    selected ??= rows.isEmpty ? null : rows.first;

    return LayoutBuilder(
      builder: (context, c) {
        final listWidth = c.maxWidth < 1100 ? 240.0 : 280.0;
        return ColoredBox(
          color: AppColors.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: listWidth,
                child: _ServerList(
                  rows: rows,
                  selectedKey: selected?.key,
                  workspaceName: ws?.name,
                  checking: checking,
                  errors: [
                    ...registry.errors,
                    if (registryAsync.hasError) '${registryAsync.error}',
                    if (listAsync.hasError) 'mcp list: ${listAsync.error}',
                    if (invAsync.hasError) 'ferramentas: ${invAsync.error}',
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? _Empty(loading: registryAsync.isLoading)
                    : _ServerDetail(
                        key: ValueKey('mcp-detail-${selected.key}'),
                        row: selected,
                        workspaceId: ws?.id,
                        cwd: runCwd,
                        registryKey: cwd,
                        checking: checking,
                        statusAt: board.at,
                        statusSource: board.source,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      loading
          ? 'Lendo a configuração MCP…'
          : 'Nenhum servidor MCP configurado. Use "Adicionar servidor".',
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    ),
  );
}

// --- list ----------------------------------------------------------------------

class _ServerList extends StatelessWidget {
  const _ServerList({
    required this.rows,
    required this.selectedKey,
    required this.workspaceName,
    required this.checking,
    required this.errors,
  });

  final List<McpServerRow> rows;
  final String? selectedKey;
  final String? workspaceName;
  final bool checking;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    List<McpServerRow> of(McpScope? s) => [
      for (final r in rows)
        if (r.scope == s) r,
    ];
    final ws = workspaceName == null ? '' : ' · $workspaceName';
    final groups = [
      ('Globais', '~/.claude.json', of(McpScope.user)),
      ('Projeto$ws', '.mcp.json', of(McpScope.project)),
      ('Local$ws', '~/.claude.json', of(McpScope.local)),
      ('Outros', 'sessão / claude.ai', of(null)),
    ];
    return ColoredBox(
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text('SERVIDORES MCP', style: sectionTitleStyle),
                ),
                if (checking)
                  const Text(
                    'verificando…',
                    key: ValueKey('mcp-checking'),
                    style: TextStyle(fontSize: 11, color: AppColors.blue),
                  ),
              ],
            ),
          ),
          for (final e in errors)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: Text(
                e,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.red),
              ),
            ),
          for (final (title, path, items) in groups)
            if (items.isNotEmpty || title != 'Outros') ...[
              _GroupHeader(title: title, path: path),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text(
                    'Nenhum servidor',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              for (final r in items)
                _ServerTile(row: r, selected: r.key == selectedKey),
            ],
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.path});

  final String title;
  final String path;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
    child: Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

String _statusLabel(McpServerRow r) {
  if (r.overriddenBy != null) return 'Sobrescrito';
  return r.status?.state.label ?? '—';
}

String _meta(McpServerRow r) {
  if (r.overriddenBy != null) {
    return 'usa o de ${r.overriddenBy!.label.toLowerCase()}';
  }
  final st = r.status;
  if (st?.state == McpConnState.failed && st?.detail != null) {
    return st!.detail!;
  }
  final transport = r.config?.transport.label;
  final n = r.tools.isEmpty ? null : '${r.tools.length} ferramentas';
  return [?transport, ?n].join(' · ');
}

class _ServerTile extends ConsumerWidget {
  const _ServerTile({required this.row, required this.selected});

  final McpServerRow row;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = row.overriddenBy != null
        ? AppColors.textMuted
        : mcpStateColor(row.status?.state);
    final radius = BorderRadius.circular(8);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? SessionColors.selectedBg : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? SessionColors.selectedBorder : Colors.transparent,
          ),
        ),
        child: InkWell(
          key: ValueKey('mcp-row-${row.key}'),
          borderRadius: radius,
          onTap: () =>
              ref.read(selectedMcpServerProvider.notifier).select(row.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Dot(color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.name,
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
                    const SizedBox(width: 6),
                    Text(
                      _statusLabel(row),
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    _meta(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
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

// --- detail --------------------------------------------------------------------

class _ServerDetail extends ConsumerStatefulWidget {
  const _ServerDetail({
    super.key,
    required this.row,
    required this.workspaceId,
    required this.cwd,
    required this.registryKey,
    required this.checking,
    required this.statusAt,
    required this.statusSource,
  });

  final McpServerRow row;
  final int? workspaceId;

  /// cwd of the `claude mcp` commands (workspace, else HOME).
  final String? cwd;

  /// Key of [mcpRegistryProvider] (workspace path or null).
  final String? registryKey;
  final bool checking;
  final DateTime? statusAt;
  final McpStatusSource? statusSource;

  @override
  ConsumerState<_ServerDetail> createState() => _ServerDetailState();
}

class _ServerDetailState extends ConsumerState<_ServerDetail> {
  bool _testing = false;

  McpServerRow get row => widget.row;

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: TextStyle(color: error ? AppColors.red : null),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// `claude mcp get <name>` (only Status / Issue are read).
  Future<void> _test() async {
    setState(() => _testing = true);
    final board = ref.read(mcpStatusBoardProvider.notifier);
    board.setOne(row.name, McpConnState.checking);
    try {
      final st = await ref.read(mcpCliProvider).get(row.name, widget.cwd);
      board.setOne(row.name, st.state, detail: st.issue);
      _toast(
        '${row.name}: ${st.state.label}'
        '${st.issue == null ? '' : ' — ${st.issue}'}',
        error: st.state == McpConnState.failed,
      );
    } on McpException catch (e) {
      board.setOne(row.name, McpConnState.unknown, detail: e.message);
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Re-runs `claude mcp list` and the tool inventory.
  void _restart() {
    ref
      ..invalidate(mcpRegistryProvider(widget.registryKey))
      ..invalidate(mcpListProvider(widget.cwd))
      ..invalidate(mcpInventoryProvider(widget.cwd));
  }

  Future<void> _remove() async {
    final c = row.config;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('mcp-remove-confirm'),
        backgroundColor: AppColors.panel,
        title: Text('Remover ${c.name}?', style: const TextStyle(fontSize: 15)),
        content: Text(
          'Executa claude mcp remove ${c.name} -s ${c.scope.cliValue} '
          '(${c.scope.label.toLowerCase()} · ${c.sourcePath}).',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('mcp-remove-ok'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Remover',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(mcpCliProvider).remove(c.name, c.scope, widget.cwd);
      ref.read(selectedMcpServerProvider.notifier).select(null);
      _restart();
      _toast('${c.name} removido (${c.scope.label.toLowerCase()}).');
    } on McpException catch (e) {
      _toast(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = row.config;
    final st = row.status;
    final color = row.overriddenBy != null
        ? AppColors.textMuted
        : mcpStateColor(st?.state);
    final statusText = row.overriddenBy != null
        ? 'Sobrescrito pelo escopo ${row.overriddenBy!.label}'
        : st == null
        ? (widget.checking ? 'Verificando…' : 'Sem status')
        : st.state.label;
    final subtitle = [
      if (c != null) '${c.transport.label} · ${c.target}',
      if (c == null) 'Visto na sessão (sem configuração local)',
      '${row.tools.length} ferramentas',
    ].join(' · ');

    final header = Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Dot(color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        row.name,
                        key: const ValueKey('mcp-detail-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusText,
                        key: const ValueKey('mcp-detail-status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ),
                    if (c != null) ...[
                      const SizedBox(width: 8),
                      InfoTag(c.scope.label),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmallButton(
                key: const ValueKey('mcp-test'),
                label: _testing ? 'Testando…' : 'Testar conexão',
                height: 32,
                onTap: _testing || c == null || row.overriddenBy != null
                    ? null
                    : _test,
              ),
              const SizedBox(width: 8),
              SmallButton(
                key: const ValueKey('mcp-restart'),
                label: 'Reiniciar',
                height: 32,
                onTap: widget.checking ? null : _restart,
              ),
              const SizedBox(width: 8),
              SmallButton(
                key: const ValueKey('mcp-remove'),
                label: 'Remover',
                height: 32,
                color: AppColors.red,
                border: SessionColors.stopBorder,
                onTap: c == null ? null : _remove,
              ),
            ],
          ),
        ],
      ),
    );

    final left = [
      _ConnectionCard(row: row, failure: st?.detail),
      _ToolsCard(row: row, loading: widget.checking),
    ];
    final right = [
      _UsedByCard(name: row.name, cwd: widget.registryKey),
      if (c != null) _ConfigCard(config: c),
      if (widget.workspaceId != null)
        _LogCard(workspaceId: widget.workspaceId!, serverKey: row.serverKey),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              Widget column(List<Widget> cards) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    cards[i],
                  ],
                ],
              );
              final wide = box.maxWidth >= 720;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: column(left)),
                          const SizedBox(width: 16),
                          Expanded(flex: 10, child: column(right)),
                        ],
                      )
                    : column([...left, ...right]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title.toUpperCase(), style: sectionTitleStyle),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

const _mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
const _dim = TextStyle(fontSize: 12, color: AppColors.textSecondary);

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.row, this.failure});

  final McpServerRow row;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final c = row.config;
    final items = <(String, String, bool)>[
      if (c != null) ...[
        ('Transporte', c.transport.label, true),
        if (c.command != null) ('Comando', c.target, true),
        if (c.url != null) ('URL', c.url!, true),
        for (final k in c.envKeys) (k, mcpMask, true),
        for (final k in c.headerKeys) (k, mcpMask, true),
        ('Escopo', '${c.scope.label} · ${c.scope.hint}', false),
      ] else
        ('Origem', 'system/init / claude mcp list', false),
      if (failure != null && row.overriddenBy == null)
        ('Erro', failure!, false),
    ];
    return _Card(
      title: 'Conexão',
      child: Column(
        children: [
          for (final (label, value, mono) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _dim,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mono
                          ? _mono.copyWith(
                              color: value == mcpMask
                                  ? AppColors.textSecondary
                                  : AppColors.text,
                            )
                          : const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Rule pill look (mockup MCP).
({String label, Color bg, Color border, Color color}) _ruleLook(McpRule r) =>
    switch (r) {
      McpRule.allow => (
        label: 'Permitido',
        bg: SessionColors.runningToolBg,
        border: SessionColors.runningToolBorder,
        color: AppColors.teal,
      ),
      McpRule.ask => (
        label: 'Pedir aprovação',
        bg: SessionColors.approvalBg,
        border: SessionColors.approvalBorder,
        color: AppColors.amber,
      ),
      McpRule.block => (
        label: 'Bloqueado',
        bg: AppColors.background,
        border: SessionColors.blockedBorder,
        color: AppColors.textSecondary,
      ),
    };

/// Order of the pill cycle (mockup: Permitido → Pedir → Bloqueado).
McpRule nextMcpRule(McpRule r) => switch (r) {
  McpRule.allow => McpRule.ask,
  McpRule.ask => McpRule.block,
  McpRule.block => McpRule.allow,
};

class _ToolsCard extends ConsumerWidget {
  const _ToolsCard({required this.row, required this.loading});

  final McpServerRow row;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = row.serverKey;
    final rules = {
      for (final r in ref.watch(mcpServerRulesProvider(key)).value ?? const [])
        r.tool: r.rule,
    };
    final tools = {...row.tools, ...rules.keys}.toList()..sort();
    final notBlocked = tools.where((t) => rules[t] != McpRule.block).length;
    return _Card(
      title: 'Ferramentas expostas',
      trailing: Text(
        '$notBlocked de ${tools.length} liberadas',
        key: const ValueKey('mcp-tools-count'),
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tools.isEmpty)
            Text(
              loading
                  ? 'Listando ferramentas (system/init, sem custo)…'
                  : row.overriddenBy != null
                  ? 'Este escopo não é usado (outro escopo vence).'
                  : 'Nenhuma ferramenta vista — o servidor conectou?',
              style: _dim,
            ),
          for (final t in tools)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mono.copyWith(
                          color: row.tools.contains(t)
                              ? AppColors.text
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RulePill(
                      key: ValueKey('mcp-rule-$t'),
                      rule: rules[t] ?? McpRule.ask,
                      onTap: () async {
                        await ref
                            .read(mcpToolRulesRepoProvider)
                            .setRule(
                              key,
                              t,
                              nextMcpRule(rules[t] ?? McpRule.ask),
                            );
                        ref.invalidate(mcpServerRulesProvider(key));
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Permitido = --allowedTools (sem pedir) · Bloqueado = '
            '--disallowedTools · vale para as próximas sessões e conversas. '
            'No modo Perguntar, Permitido continua pedindo aprovação.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RulePill extends StatelessWidget {
  const _RulePill({super.key, required this.rule, required this.onTap});

  final McpRule rule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = _ruleLook(rule);
    final r = BorderRadius.circular(13);
    return Material(
      color: l.bg,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: l.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: r,
        child: Container(
          height: 26,
          constraints: const BoxConstraints(minWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            l.label,
            maxLines: 1,
            style: TextStyle(fontSize: 11, color: l.color),
          ),
        ),
      ),
    );
  }
}

class _UsedByCard extends ConsumerWidget {
  const _UsedByCard({required this.name, required this.cwd});

  final String name;
  final String? cwd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(agentEntriesProvider(cwd)).value ?? const [];
    final users = [
      for (final e in entries)
        if (!e.overriddenByProject && e.file.mcpServerNames.contains(name)) e,
    ];
    return _Card(
      title: 'Usado por',
      child: users.isEmpty
          ? const Text(
              'Nenhum agente cita este servidor em mcpServers.',
              style: _dim,
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in users)
                  Container(
                    key: ValueKey('mcp-used-by-${e.name}'),
                    height: 28,
                    padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AgentAvatar(
                          name: e.name,
                          color: agentTint(e.name, e.file.color),
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(e.name, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ConfigCard extends ConsumerWidget {
  const _ConfigCard({required this.config});

  final McpServerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(agentHomeProvider);
    var path = config.sourcePath;
    if (home != null && path.startsWith('$home/')) {
      path = '~${path.substring(home.length)}';
    }
    return _Card(
      title: 'Configuração',
      trailing: Flexible(
        child: Text(
          path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 11,
            color: AppColors.amber,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: SelectableText(
          config.maskedJson(),
          key: const ValueKey('mcp-config-json'),
          style: _mono.copyWith(height: 1.6),
        ),
      ),
    );
  }
}

class _LogCard extends ConsumerWidget {
  const _LogCard({required this.workspaceId, required this.serverKey});

  final int workspaceId;
  final String serverKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mcpLogProvider((workspaceId, serverKey)));
    final items = async.value ?? const <McpLogEntry>[];
    String two(int v) => v.toString().padLeft(2, '0');
    String clock(DateTime t) {
      final l = t.toLocal();
      return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
    }

    (String, Color) look(McpLogStatus s) => switch (s) {
      McpLogStatus.ok => ('ok', AppColors.teal),
      McpLogStatus.error => ('erro', AppColors.red),
      McpLogStatus.waiting => ('aguardando aprovação', AppColors.amber),
      McpLogStatus.running => ('executando', AppColors.blue),
      McpLogStatus.noResult => ('sem resultado', AppColors.textMuted),
    };

    const base = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11,
      color: AppColors.textSecondary,
    );
    return _Card(
      title: 'Log recente',
      trailing: InkWell(
        onTap: () => ref.invalidate(mcpLogProvider((workspaceId, serverKey))),
        child: const Text(
          'atualizar',
          style: TextStyle(fontSize: 11, color: AppColors.amber),
        ),
      ),
      child: items.isEmpty
          ? Text(
              async.isLoading
                  ? 'Lendo eventos das sessões…'
                  : 'Nenhuma chamada nas sessões deste workspace.',
              style: _dim,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text.rich(
                      TextSpan(
                        style: base,
                        children: [
                          TextSpan(
                            text: '${clock(e.at)} ',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                          TextSpan(text: '${e.tool} '),
                          TextSpan(
                            text: look(e.status).$1,
                            style: TextStyle(color: look(e.status).$2),
                          ),
                          if (e.duration != null)
                            TextSpan(text: ' ${e.duration!.inMilliseconds} ms'),
                          TextSpan(text: ' · ${e.agent ?? e.sessionTitle}'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
    );
  }
}
