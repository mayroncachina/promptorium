part of 'mcp_screen.dart';

// SPEC-105: the Codex tab of the MCP screen. A part of `mcp_screen.dart` so
// both tabs share the cards, pills and tiles of the Claude tab.

/// "Claude Code · 4 / Codex · 2" (R1). Counts are null while unknown.
class McpProviderSwitch extends ConsumerWidget {
  const McpProviderSwitch({
    super.key,
    required this.tab,
    required this.claudeCount,
    required this.codexCount,
  });

  final McpProviderTab tab;
  final int? claudeCount;
  final int? codexCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget segment(McpProviderTab t, int? n) {
      final on = t == tab;
      final r = BorderRadius.circular(6);
      return Material(
        color: on ? SessionColors.approvalBg : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(
            color: on ? SessionColors.approvalBorder : Colors.transparent,
          ),
        ),
        child: InkWell(
          key: ValueKey('mcp-tab-${t.id}'),
          borderRadius: r,
          onTap: on ? null : () => selectMcpProviderTab(ref, t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              '${t.label} · ${n ?? '—'}',
              maxLines: 1,
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(McpProviderTab.claude, claudeCount),
          const SizedBox(width: 2),
          segment(McpProviderTab.codex, codexCount),
        ],
      ),
    );
  }
}

/// Number of Codex servers for the switch (null while unknown or when the
/// Codex is missing).
int? codexServerCount(WidgetRef ref, String? cwd) =>
    ref.watch(codexMcpListProvider(cwd)).value?.length;

/// Why the Codex tab cannot list servers (R12): missing or incompatible
/// CLI. Null = it can.
String? codexMcpBlocker(ProviderAvailability? a) => switch (a?.status) {
  ProviderStatus.missing => 'Codex não encontrado. ${a!.message}',
  ProviderStatus.incompatible =>
    a!.version == null
        ? a.message
        : 'Codex ${a.version} encontrado. O Promptorium precisa da versão '
              '${codexMinVersion.substring(0, 5)} ou mais nova para listar e '
              'configurar servidores.',
  _ => null,
};

/// The Codex tab (R1–R5, R7, R9, R10, R12).
class CodexMcpPane extends ConsumerWidget {
  const CodexMcpPane({
    super.key,
    required this.cwd,
    required this.workspaceId,
    required this.claudeCount,
  });

  /// cwd of the `codex mcp` commands (workspace, else HOME).
  final String? cwd;
  final int? workspaceId;
  final int? claudeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avail = ref.watch(providerAvailabilityProvider('codex'));
    final blocker = codexMcpBlocker(avail.value);
    final checkingCli = avail.isLoading;
    final canList = !checkingCli && blocker == null;
    const idleList = AsyncValue<List<CodexMcpServer>>.loading();
    const idleStatus = AsyncValue<List<CodexMcpStatus>>.loading();
    final listAsync = canList ? ref.watch(codexMcpListProvider(cwd)) : idleList;
    // The status starts the servers (npx, OAuth checks): only after the
    // configuration was read.
    final statusAsync = canList && listAsync.hasValue
        ? ref.watch(codexMcpStatusProvider(cwd))
        : idleStatus;
    final board = ref.watch(codexMcpBoardProvider);
    final rows = buildCodexMcpRows(
      listAsync.value ?? const [],
      statusAsync.value ?? const [],
    );
    final appServer = appMcpEnabled(ref.watch(appSettingsProvider));
    final selectedKey = ref.watch(selectedCodexMcpServerProvider);
    CodexMcpRow? selected;
    for (final r in rows) {
      if (r.key == selectedKey) selected = r;
    }
    final appSelected = selectedKey == _codexAppKey && appServer;
    if (!appSelected) selected ??= rows.firstOrNull;
    final checking =
        checkingCli || listAsync.isLoading || statusAsync.isLoading;

    final list = _CodexList(
      rows: rows,
      board: board,
      selectedKey: appSelected ? _codexAppKey : selected?.key,
      claudeCount: claudeCount,
      codexCount: listAsync.value?.length,
      appServer: appServer,
      checking: checking,
      blocker: blocker,
      errors: [
        if (listAsync.hasError) '${listAsync.error}',
        if (statusAsync.hasError) 'status: ${statusAsync.error}',
      ],
    );
    final Widget detail;
    if (blocker != null) {
      detail = const _Empty(loading: false, codex: true);
    } else if (appSelected) {
      detail = const _CodexAppServerDetail();
    } else if (selected == null) {
      detail = _Empty(loading: checking, codex: true);
    } else {
      detail = _CodexDetail(
        key: ValueKey('mcp-codex-detail-${selected.key}'),
        row: selected,
        live: board.byName[selected.name],
        cwd: cwd,
        workspaceId: workspaceId,
        checking: checking,
      );
    }
    return LayoutBuilder(
      builder: (context, c) => ColoredBox(
        color: AppColors.background,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: c.maxWidth < 1100 ? 240.0 : 280.0, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        ),
      ),
    );
  }
}

const _codexAppKey = 'codex:app:$appMcpServerName';

class _CodexList extends ConsumerWidget {
  const _CodexList({
    required this.rows,
    required this.board,
    required this.selectedKey,
    required this.claudeCount,
    required this.codexCount,
    required this.appServer,
    required this.checking,
    required this.blocker,
    required this.errors,
  });

  final List<CodexMcpRow> rows;
  final McpStatusBoardState board;
  final String? selectedKey;
  final int? claudeCount;
  final int? codexCount;
  final bool appServer;
  final bool checking;
  final String? blocker;
  final List<String> errors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final global = [
      for (final r in rows)
        if (r.config != null) r,
    ];
    final plugins = [
      for (final r in rows)
        if (r.fromPlugin) r,
    ];
    return ColoredBox(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
            child: Row(
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: McpProviderSwitch(
                      tab: McpProviderTab.codex,
                      claudeCount: claudeCount,
                      codexCount: blocker == null ? codexCount : null,
                    ),
                  ),
                ),
                if (checking && blocker == null) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'verificando…',
                    key: ValueKey('mcp-codex-checking'),
                    style: TextStyle(fontSize: 11, color: AppColors.blue),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                if (blocker != null)
                  _CodexUnavailable(message: blocker!)
                else ...[
                  for (final e in errors)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                      child: Text(
                        e,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  const _GroupHeader(
                    title: 'Globais',
                    path: '~/.codex/config.toml',
                  ),
                  if (global.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
                      child: Text(
                        'Nenhum servidor',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  for (final r in global)
                    _CodexTile(
                      row: r,
                      live: board.byName[r.name],
                      selected: r.key == selectedKey,
                    ),
                  if (plugins.isNotEmpty) ...[
                    const _GroupHeader(title: 'De plugins', path: 'só leitura'),
                    for (final r in plugins)
                      _CodexTile(
                        row: r,
                        live: board.byName[r.name],
                        selected: r.key == selectedKey,
                      ),
                  ],
                  if (appServer) ...[
                    const _GroupHeader(
                      title: 'Da sessão',
                      path: 'Promptorium · só leitura',
                    ),
                    _CodexAppTile(selected: selectedKey == _codexAppKey),
                  ],
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Text(
              'Configuração por codex mcp list --json; status por '
              'mcpServerStatus/list, sem turno e sem custo.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// R12: Codex missing or incompatible; the Claude tab is not affected.
class _CodexUnavailable extends ConsumerWidget {
  const _CodexUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Container(
      key: const ValueKey('mcp-codex-unavailable'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SessionColors.delBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.stopBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          const Text(
            'Atualize com codex update ou instale o Codex CLI e confira o '
            'PATH em Configurações → Provedores. A aba Claude Code segue '
            'normal; o app nunca troca de provedor sem avisar.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SmallButton(
            key: const ValueKey('mcp-codex-recheck'),
            label: 'Conferir de novo',
            height: 28,
            onTap: () => ref.invalidate(providerAvailabilityProvider('codex')),
          ),
        ],
      ),
    ),
  );
}

String _codexMeta(CodexMcpRow r, McpLiveStatus? live) {
  final st = live ?? _liveOf(r);
  if (st?.state == McpConnState.failed && st?.detail != null) {
    return st!.detail!;
  }
  final c = r.config;
  if (c == null) return 'plugin ${r.status?.pluginId ?? ''}'.trim();
  final kind = c.transport == McpTransport.http
      ? switch (c.auth) {
          CodexMcpAuth.bearerToken => 'token',
          CodexMcpAuth.oAuth || CodexMcpAuth.notLoggedIn => 'oauth',
          _ => null,
        }
      : c.command;
  return [c.transport.label, ?kind].join(' · ');
}

McpLiveStatus? _liveOf(CodexMcpRow r) {
  final s = r.status;
  if (r.config != null && !r.config!.enabled) {
    return McpLiveStatus(name: r.name, state: McpConnState.disabled);
  }
  return s == null
      ? null
      : McpLiveStatus(name: r.name, state: s.state, detail: s.toolsError);
}

class _CodexTile extends ConsumerWidget {
  const _CodexTile({
    required this.row,
    required this.live,
    this.selected = false,
  });

  final CodexMcpRow row;
  final McpLiveStatus? live;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = row.config?.enabled == false
        ? _liveOf(row)
        : live ?? _liveOf(row);
    return _Tile(
      tileKey: ValueKey('mcp-row-${row.key}'),
      name: row.name,
      status: st?.state.label ?? '—',
      meta: _codexMeta(row, st),
      color: mcpStateColor(st?.state),
      selected: selected,
      onTap: () =>
          ref.read(selectedCodexMcpServerProvider.notifier).select(row.key),
    );
  }
}

class _CodexAppTile extends ConsumerWidget {
  const _CodexAppTile({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Tile(
    tileKey: const ValueKey('mcp-row-codex-app'),
    name: appMcpServerName,
    status: 'por execução',
    meta: 'injetado em cada execução',
    color: AppColors.textMuted,
    selected: selected,
    onTap: () =>
        ref.read(selectedCodexMcpServerProvider.notifier).select(_codexAppKey),
  );
}

/// A list tile (same look as the Claude tab's).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.tileKey,
    required this.name,
    required this.status,
    required this.meta,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Key tileKey;
  final String name;
  final String status;
  final String meta;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          key: tileKey,
          borderRadius: radius,
          onTap: onTap,
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
                        name,
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
                    Text(status, style: TextStyle(fontSize: 11, color: color)),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    meta,
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

/// The Promptorium server in Codex runs (R7): by override of each run, only
/// the read tools (writes stay out: per-tool approval in the Codex is not
/// proven).
class _CodexAppServerDetail extends StatelessWidget {
  const _CodexAppServerDetail();

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('mcp-codex-detail-app'),
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        appMcpServerName,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Servidor do próprio Promptorium, dado a cada execução Codex por '
        'override (-c mcp_servers.promptorium…), com um token que some quando '
        'ela termina. Nada é gravado no ~/.codex. No Codex, as ferramentas de '
        'escrita ficam de fora: a aprovação por ferramenta não foi comprovada.',
        key: ValueKey('mcp-codex-app-note'),
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 16),
      for (final t in appMcpCatalog)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  t.name,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: Text(t.summary, style: const TextStyle(fontSize: 12)),
              ),
              Text(
                t.write ? 'Fora no Codex' : 'Liberada',
                style: TextStyle(
                  fontSize: 12,
                  color: t.write ? AppColors.textMuted : AppColors.teal,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _CodexDetail extends ConsumerStatefulWidget {
  const _CodexDetail({
    super.key,
    required this.row,
    required this.live,
    required this.cwd,
    required this.workspaceId,
    required this.checking,
  });

  final CodexMcpRow row;
  final McpLiveStatus? live;
  final String? cwd;
  final int? workspaceId;
  final bool checking;

  @override
  ConsumerState<_CodexDetail> createState() => _CodexDetailState();
}

class _CodexDetailState extends ConsumerState<_CodexDetail> {
  bool _busy = false;
  String? _busyLabel;

  CodexMcpRow get row => widget.row;

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(
        SnackBar(
          content: Text(
            text,
            style: TextStyle(color: error ? AppColors.red : null),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _run(String label, Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await body();
    } on McpException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast(CodexRpc.redact('$e'), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  void _refresh() => ref
    ..invalidate(codexMcpListProvider(widget.cwd))
    ..invalidate(codexMcpStatusProvider(widget.cwd));

  /// `mcpServerStatus/list` of this server with `detail: full` (R2).
  Future<void> _test() => _run('Testando…', () async {
    final board = ref.read(codexMcpBoardProvider.notifier);
    board.setOne(row.name, McpConnState.checking);
    try {
      final list = await readCodexMcpStatus(
        executable: ref.read(codexExecutableProvider),
        starter: ref.read(codexMcpStarterProvider),
        workingDirectory: widget.cwd,
        serverName: row.name,
        full: true,
      );
      final st = list.where((s) => s.name == row.name).firstOrNull;
      if (st == null) {
        board.setOne(row.name, McpConnState.unknown);
        _toast('${row.name}: o Codex não informou o status.', error: true);
        return;
      }
      board.setOne(row.name, st.state, detail: st.toolsError);
      _toast(
        '${row.name}: ${st.state.label}'
        '${st.toolsError == null ? '' : ' — ${st.toolsError}'}',
        error: st.state == McpConnState.failed,
      );
    } catch (e) {
      board.setOne(row.name, McpConnState.unknown, detail: '$e');
      rethrow;
    }
  });

  /// R5: `mcpServer/oauth/login`, the browser, then
  /// `mcpServer/oauthLogin/completed`.
  Future<void> _login() => _run('Entrando…', () async {
    final r = await codexMcpOauthLogin(
      executable: ref.read(codexExecutableProvider),
      starter: ref.read(codexMcpStarterProvider),
      workingDirectory: widget.cwd,
      name: row.name,
      openUrl: ref.read(codexMcpOpenUrlProvider),
    );
    if (!mounted) return;
    if (r.success) {
      _toast('${row.name}: login concluído.');
      _refresh();
    } else {
      _toast('${row.name}: ${r.error ?? 'login não concluído.'}', error: true);
    }
  });

  Future<void> _logout() => _run('Saindo…', () async {
    await ref.read(codexMcpCliProvider).logout(row.name, widget.cwd);
    _toast('${row.name}: sessão OAuth encerrada.');
    _refresh();
  });

  Future<void> _remove() async {
    final ok = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('mcp-remove-confirm'),
        backgroundColor: AppColors.panel,
        title: Text(
          'Remover ${row.name} do Codex?',
          style: const TextStyle(fontSize: 15),
        ),
        content: Text(
          'Executa codex mcp remove ${row.name} (global · ~/.codex/config.toml).',
          key: const ValueKey('mcp-codex-remove-command'),
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
    await _run('Removendo…', () async {
      await ref.read(codexMcpCliProvider).remove(row.name, widget.cwd);
      ref.read(selectedCodexMcpServerProvider.notifier).select(null);
      ref.read(codexMcpBoardProvider.notifier).remove(row.name);
      _refresh();
      _toast('${row.name} removido do Codex.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = row.config;
    final live = c?.enabled == false
        ? _liveOf(row)
        : widget.live ?? _liveOf(row);
    final auth = row.status?.auth ?? c?.auth ?? CodexMcpAuth.unknown;
    final color = mcpStateColor(live?.state);
    final http = c?.transport == McpTransport.http;
    final canLogin =
        http &&
        (auth == CodexMcpAuth.notLoggedIn ||
            live?.state == McpConnState.needsAuth);
    final canLogout = http && auth == CodexMcpAuth.oAuth;
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Dot(color),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
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
              Text(
                live == null
                    ? (widget.checking ? 'Verificando…' : 'Sem status')
                    : live.state.label,
                key: const ValueKey('mcp-detail-status'),
                style: TextStyle(fontSize: 11, color: color),
              ),
              const SizedBox(width: 8),
              InfoTag(row.fromPlugin ? 'Codex · plugin' : 'Codex · Global'),
            ],
          ),
          Wrap(
            runSpacing: 8,
            children: [
              SmallButton(
                key: const ValueKey('mcp-test'),
                label: _busyLabel == 'Testando…'
                    ? 'Testando…'
                    : 'Testar conexão',
                height: 32,
                onTap: _busy || c?.enabled == false ? null : _test,
              ),
              if (canLogin) ...[
                const SizedBox(width: 8),
                SmallButton(
                  key: const ValueKey('mcp-codex-login'),
                  label: _busyLabel == 'Entrando…' ? 'Entrando…' : 'Entrar',
                  height: 32,
                  color: AppColors.amber,
                  onTap: _busy ? null : _login,
                ),
              ],
              if (canLogout) ...[
                const SizedBox(width: 8),
                SmallButton(
                  key: const ValueKey('mcp-codex-logout'),
                  label: 'Sair',
                  height: 32,
                  onTap: _busy ? null : _logout,
                ),
              ],
              const SizedBox(width: 8),
              SmallButton(
                key: const ValueKey('mcp-remove'),
                label: 'Remover',
                height: 32,
                color: AppColors.red,
                border: SessionColors.stopBorder,
                onTap: c == null || _busy ? null : _remove,
              ),
            ],
          ),
        ],
      ),
    );

    final tools = row.status?.tools ?? const <CodexMcpTool>[];
    final left = [
      _CodexConnectionCard(row: row, live: live, auth: auth),
      _CodexToolsCard(row: row, tools: tools, loading: widget.checking),
    ];
    final right = [
      if (c != null) _CodexConfigCard(config: c),
      if (widget.workspaceId != null)
        _CodexLogCard(
          workspaceId: widget.workspaceId!,
          serverKey: mcpServerKey(row.name),
        ),
      const _Card(
        title: 'Usado por',
        trailing: InfoTag('Só Claude Code'),
        child: Text(
          'Os agentes que citam servidores em mcpServers rodam no Claude Code. '
          'Agentes no Codex chegam com a SPEC-106.',
          key: ValueKey('mcp-codex-used-by'),
          style: _dim,
        ),
      ),
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

class _CodexConnectionCard extends StatelessWidget {
  const _CodexConnectionCard({
    required this.row,
    required this.live,
    required this.auth,
  });

  final CodexMcpRow row;
  final McpLiveStatus? live;
  final CodexMcpAuth auth;

  @override
  Widget build(BuildContext context) {
    final c = row.config;
    final n = row.status?.tools.length;
    final items = <(String, String, bool)>[
      if (c != null) ...[
        (
          'Transporte',
          c.transport == McpTransport.http
              ? 'http (streamable)'
              : c.transport.label,
          false,
        ),
        if (c.command != null) ('Comando', c.target, true),
        if (c.url != null) ('URL', c.url!, true),
        for (final k in c.envKeys) (k, mcpMask, true),
        for (final k in c.headerKeys) (k, mcpMask, true),
        if (c.bearerTokenEnvVar != null)
          ('Token', 'variável ${c.bearerTokenEnvVar}', true),
      ] else
        ('Plugin', row.status?.pluginId ?? '—', true),
      if (auth != CodexMcpAuth.unsupported && auth != CodexMcpAuth.unknown)
        ('Autenticação', auth.label, false),
      (
        'Estado',
        [live?.state.label ?? '—', if (n != null) '$n ferramentas'].join(' · '),
        false,
      ),
      if (c != null && !c.enabled)
        ('Desligado', c.disabledReason ?? 'enabled = false', false),
      if (live?.state == McpConnState.failed && live?.detail != null)
        ('Erro', live!.detail!, false),
      ('Origem', 'codex mcp get · mcpServerStatus/list', false),
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
                      maxLines: 3,
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

class _CodexConfigCard extends StatelessWidget {
  const _CodexConfigCard({required this.config});

  final CodexMcpServer config;

  @override
  Widget build(BuildContext context) => _Card(
    title: 'Configuração',
    trailing: const Text(
      '~/.codex/config.toml',
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 11,
        color: AppColors.amber,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            config.maskedToml(),
            key: const ValueKey('mcp-codex-config-toml'),
            style: _mono.copyWith(height: 1.6),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'O app não edita este arquivo: adicionar e remover usam codex mcp '
          'add/remove.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

/// R9: the rules of the Claude tab, with what the Codex does with each.
class _CodexToolsCard extends ConsumerWidget {
  const _CodexToolsCard({
    required this.row,
    required this.tools,
    required this.loading,
  });

  final CodexMcpRow row;
  final List<CodexMcpTool> tools;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = mcpServerKey(row.name);
    final rules = {
      for (final r in ref.watch(mcpServerRulesProvider(key)).value ?? const [])
        r.tool: r.rule,
    };
    final names = {for (final t in tools) t.name, ...rules.keys}.toList()
      ..sort();
    final desc = {for (final t in tools) t.name: t.description};
    final shown = names.where((t) => rules[t] != McpRule.block).length;
    return _Card(
      title: 'Ferramentas e regras',
      trailing: Text(
        '$shown de ${names.length}',
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
          if (names.isEmpty)
            Text(
              loading
                  ? 'Listando ferramentas (mcpServerStatus/list, sem custo)…'
                  : row.status?.toolsError ??
                        'Nenhuma ferramenta vista — o servidor conectou?',
              style: _dim,
            ),
          for (final t in names)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final name = Text(
                      t,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mono.copyWith(
                        color: desc.containsKey(t)
                            ? AppColors.text
                            : AppColors.textMuted,
                      ),
                    );
                    final pills = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                        const SizedBox(width: 6),
                        _CodexRuleTag(
                          key: ValueKey('mcp-codex-rule-tag-$t'),
                          rule: rules[t] ?? McpRule.ask,
                        ),
                      ],
                    );
                    // Narrow cards: the pills go under the name.
                    if (box.maxWidth < 460) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name,
                          const SizedBox(height: 4),
                          FittedBox(fit: BoxFit.scaleDown, child: pills),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 4, child: name),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 5,
                          child: Text(
                            desc[t] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _dim.copyWith(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        pills,
                      ],
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'No Codex, só Bloqueado tem equivalente (disabled_tools por '
            'execução). Permitido e Pedir aprovação continuam valendo no '
            'Claude Code.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// "disabled_tools" (Bloqueado is applied) or "Só Claude Code" (R9: the app
/// does not pretend to apply it).
class _CodexRuleTag extends StatelessWidget {
  const _CodexRuleTag({super.key, required this.rule});

  final McpRule rule;

  @override
  Widget build(BuildContext context) {
    final applies = codexRuleApplies(rule);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: applies ? SessionColors.runningToolBg : AppColors.background,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: applies ? SessionColors.runningToolBorder : AppColors.border,
        ),
      ),
      child: Text(
        applies ? 'disabled_tools' : 'Só Claude Code',
        style: TextStyle(
          fontSize: 11,
          color: applies ? AppColors.teal : AppColors.textMuted,
        ),
      ),
    );
  }
}

class _CodexLogCard extends ConsumerWidget {
  const _CodexLogCard({required this.workspaceId, required this.serverKey});

  final int workspaceId;
  final String serverKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (workspaceId, serverKey);
    final async = ref.watch(codexMcpLogProvider(key));
    final items = async.value ?? const <McpLogEntry>[];
    String two(int v) => v.toString().padLeft(2, '0');
    String clock(DateTime t) {
      final l = t.toLocal();
      return '${two(l.hour)}:${two(l.minute)}';
    }

    (String, Color) look(McpLogStatus s) => switch (s) {
      McpLogStatus.ok => ('ok', AppColors.teal),
      McpLogStatus.error => ('erro', AppColors.red),
      McpLogStatus.waiting => ('aguardando', AppColors.amber),
      McpLogStatus.running => ('executando', AppColors.blue),
      McpLogStatus.noResult => ('sem resultado', AppColors.textMuted),
    };
    const base = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11,
      color: AppColors.textSecondary,
    );
    return _Card(
      title: 'Log recente · sessões Codex',
      trailing: InkWell(
        onTap: () => ref.invalidate(codexMcpLogProvider(key)),
        child: const Text(
          'atualizar',
          style: TextStyle(fontSize: 11, color: AppColors.amber),
        ),
      ),
      child: items.isEmpty
          ? Text(
              async.isLoading
                  ? 'Lendo eventos das sessões…'
                  : 'Nenhuma chamada nas sessões Codex deste workspace.',
              key: const ValueKey('mcp-codex-log-empty'),
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
                            text: '${look(e.status).$1} ',
                            style: TextStyle(color: look(e.status).$2),
                          ),
                          TextSpan(text: '${clock(e.at)} ${e.tool}'),
                          if (e.duration != null)
                            TextSpan(
                              text:
                                  ' · ${(e.duration!.inMilliseconds / 1000).toStringAsFixed(1)} s',
                            ),
                          TextSpan(text: ' · ${e.sessionTitle}'),
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
