import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/run_prefs.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../agent_file.dart';
import '../agent_repository.dart';
import 'agent_style.dart';

/// Editor of one agent (mockup Agentes): Identidade, Prompt de sistema,
/// Ferramentas, Execução and the live preview of the generated file.
class AgentEditor extends ConsumerStatefulWidget {
  const AgentEditor({
    super.key,
    required this.entry,
    required this.workspace,
    required this.onSaved,
    required this.onDeleted,
    required this.onTest,
  });

  /// null = new agent.
  final AgentEntry? entry;
  final Workspace? workspace;

  /// Called with the path written.
  final ValueChanged<String> onSaved;
  final VoidCallback onDeleted;

  /// "Testar em sessão" (after saving) with the agent name.
  final ValueChanged<String> onTest;

  @override
  ConsumerState<AgentEditor> createState() => AgentEditorState();
}

class AgentEditorState extends ConsumerState<AgentEditor> {
  late final AgentFile _base = widget.entry?.file ?? AgentFile.empty();

  late final _name = TextEditingController(text: _base.name ?? '');
  late final _description = TextEditingController(
    text: _base.description ?? '',
  );
  late final String _bodyPrefix = _leadingNewlines(_base.body);
  late final _prompt = TextEditingController(
    text: widget.entry == null ? '' : _base.body.substring(_bodyPrefix.length),
  );
  late final String _initialOthers = _base.tools
      .where((t) => !agentToolPills.contains(t))
      .join(', ');
  late final _otherTools = TextEditingController(text: _initialOthers);
  final _budget = TextEditingController();
  late final _maxTurns = TextEditingController(
    text: _base.maxTurns?.toString() ?? '',
  );

  late AgentScope _scope =
      widget.entry?.scope ??
      (widget.workspace == null ? AgentScope.global : AgentScope.project);
  late String? _model = _base.model;
  late String? _permission = _base.permissionMode;

  /// `effort` of the frontmatter (null = absent: the session's effort).
  late String? _effort = _base.effort;
  late final List<String> _tools = [
    for (final t in _base.tools)
      if (agentToolPills.contains(t)) t,
  ];
  bool _toolsTouched = false;
  late final List<String> _mcp = [..._base.mcpServerNames];
  bool _mcpTouched = false;
  String _loadedBudget = '';
  bool _busy = false;
  String? _error;

  bool get isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _description, _prompt, _otherTools, _budget]) {
      c.addListener(_changed);
    }
    _maxTurns.addListener(_changed);
    _loadBudget();
  }

  Future<void> _loadBudget() async {
    final e = widget.entry;
    if (e == null) return;
    try {
      final s = await ref.read(agentSettingsRepoProvider).get(e.name, e.scope);
      final b = s?.budgetUsd;
      if (!mounted || b == null || _budget.text.isNotEmpty) return;
      _loadedBudget = formatBudget(b);
      _budget.text = _loadedBudget;
    } catch (_) {
      // no settings row
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _prompt,
      _otherTools,
      _budget,
      _maxTurns,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // --- form → file -------------------------------------------------------------

  /// The file as it would be saved now (also the live preview).
  AgentFile get current {
    var f = _base
        .withValue('name', _text('name', _name.text))
        .withValue('description', _text('description', _description.text));
    if (_toolsTouched || _otherTools.text != _initialOthers) {
      f = f.withToolList('tools', [
        ..._tools,
        ...parseToolList(_otherTools.text),
      ]);
    }
    f = f.withValue('model', _model);
    f = f.withValue('permissionMode', _permission);
    f = f.withValue('effort', _effort);
    final turns = _parsedTurns;
    if (turns.ok) f = f.withValue('maxTurns', turns.value);
    if (_mcpTouched) f = f.withMcpServerNames(_mcp);
    final text = _prompt.text;
    final body = isNew
        ? (text.isEmpty ? '' : '\n$text${text.endsWith('\n') ? '' : '\n'}')
        : '$_bodyPrefix$text';
    return f.withBody(body);
  }

  /// Empty text removes a key the file did not have (no `name: ""`).
  String? _text(String key, String value) {
    final v = value.trim();
    return v.isEmpty && !_base.has(key) ? null : v;
  }

  ({bool ok, int? value}) get _parsedTurns {
    final t = _maxTurns.text.trim();
    if (t.isEmpty) return (ok: true, value: null);
    final n = int.tryParse(t);
    return n != null && n >= 1
        ? (ok: true, value: n)
        : (ok: false, value: null);
  }

  ({bool ok, double? value}) get _parsedBudget {
    final t = _budget.text.trim().replaceAll(r'$', '').replaceAll(',', '.');
    if (t.isEmpty) return (ok: true, value: null);
    final n = double.tryParse(t.trim());
    return n != null && n > 0 ? (ok: true, value: n) : (ok: false, value: null);
  }

  bool get dirty =>
      isNew ||
      current.serialize() != _base.serialize() ||
      _scope != widget.entry!.scope ||
      _budget.text.trim() != _loadedBudget;

  AgentRepository get _repo =>
      ref.read(agentRepositoryProvider(widget.workspace?.path));

  /// Path the save would write (for the preview).
  String? get _targetPath {
    final e = widget.entry;
    final name = _name.text.trim();
    if (e != null && e.scope == _scope && e.name == name) return e.path;
    if (name.isEmpty) return null;
    try {
      return _repo.pathFor(name, _scope);
    } on AgentException {
      return null;
    }
  }

  String _displayPath(String? path) {
    if (path == null) return '—';
    final home = _repo.home;
    final ws = widget.workspace?.path;
    if (ws != null && path.startsWith('$ws/')) {
      return path.substring(ws.length + 1);
    }
    if (home != null && path.startsWith('$home/')) {
      return '~/${path.substring(home.length + 1)}';
    }
    return path;
  }

  // --- actions -----------------------------------------------------------------

  /// Saves; returns the agent name on success.
  Future<String?> save() async {
    if (_busy) return null;
    final turns = _parsedTurns;
    final budget = _parsedBudget;
    if (!turns.ok) {
      setState(() => _error = 'Máx. de turnos deve ser um inteiro ≥ 1.');
      return null;
    }
    if (!budget.ok) {
      setState(() => _error = 'Orçamento inválido (ex.: 2.00).');
      return null;
    }
    final file = current;
    final e = widget.entry;
    final moving = e != null && e.scope != _scope;
    if (moving) {
      String target;
      try {
        target = _repo.pathFor(file.name ?? '', _scope);
      } on AgentException catch (x) {
        setState(() => _error = x.message);
        return null;
      }
      final ok = await confirmAgentAction(
        context,
        title: 'Mover agente',
        message:
            'Salvar em ${_displayPath(target)} e remover '
            '${_displayPath(e.path)}?',
        confirm: 'Mover',
      );
      if (!ok || !mounted) return null;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await _repo.save(file, _scope, previousPath: e?.path);
      final settings = ref.read(agentSettingsRepoProvider);
      final name = file.name!.trim();
      if (e != null && (e.name != name || e.scope != _scope)) {
        await settings.delete(e.name, e.scope);
      }
      await settings.upsert(
        AgentSetting(
          agentName: name,
          scope: _scope,
          budgetUsd: budget.value,
          // Mirrors of the frontmatter (the file is the source of truth).
          maxTurns: file.maxTurns,
          permissionMode: file.permissionMode,
          mcpServers: file.mcpServerNames,
        ),
      );
      _invalidate();
      if (mounted) widget.onSaved(path);
      return name;
    } on AgentException catch (x) {
      if (mounted) setState(() => _error = x.message);
    } catch (x) {
      if (mounted) setState(() => _error = 'Falha ao salvar: $x');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  void _invalidate() {
    ref.invalidate(agentEntriesProvider(widget.workspace?.path));
  }

  Future<void> _delete() async {
    final e = widget.entry;
    if (e == null) return;
    final ok = await confirmAgentAction(
      context,
      title: 'Excluir agente',
      message: 'Excluir ${_displayPath(e.path)}? O arquivo é apagado do disco.',
      confirm: 'Excluir',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.delete(e.path);
      await ref.read(agentSettingsRepoProvider).delete(e.name, e.scope);
      _invalidate();
      if (mounted) widget.onDeleted();
    } catch (x) {
      if (mounted) setState(() => _error = 'Falha ao excluir: $x');
    }
  }

  Future<void> _test() async {
    final name = dirty ? await save() : widget.entry?.name;
    if (name != null && mounted) widget.onTest(name);
  }

  // --- UI ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final file = current;
    final ws = widget.workspace;
    final mcpKnown =
        ref.watch(mcpServerNamesProvider(ws?.path)).value ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(file),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, c) {
                final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _identity(),
                    const SizedBox(height: 16),
                    _promptCard(),
                  ],
                );
                final right = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _toolsCard(),
                    const SizedBox(height: 16),
                    _execution(mcpKnown),
                    const SizedBox(height: 16),
                    _preview(file),
                  ],
                );
                if (c.maxWidth >= 2 * 360 + 16) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 16),
                      Expanded(child: right),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [left, const SizedBox(height: 16), right],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(AgentFile file) {
    final name = _name.text.trim();
    final e = widget.entry;
    final ws = widget.workspace;
    final sessions = ws == null || e == null
        ? const <Session>[]
        : [
            for (final s
                in ref.watch(sessionsProvider(ws.id)).value ??
                    const <Session>[])
              if (s.agentName == e.name) s,
          ];
    final done = sessions
        .where((s) => s.status == SessionStatus.completed)
        .length;
    final avg = sessions.isEmpty
        ? 0.0
        : sessions.fold(0.0, (a, s) => a + s.costUsd) / sessions.length;
    final subtitle = e == null
        ? 'Novo agente · ainda não salvo'
        : '${sessions.length} ${sessions.length == 1 ? 'sessão' : 'sessões'}'
              ' · $done concluídas · custo médio \$${avg.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          AgentAvatar(name: name, color: agentTint(name, file.color), size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? 'novo-agente' : name,
                        key: const ValueKey('agent-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InfoTag(_scope == AgentScope.global ? 'Global' : 'Projeto'),
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
          const SizedBox(width: 8),
          if (e != null) ...[
            Flexible(
              child: SmallButton(
                key: const ValueKey('agent-delete'),
                label: 'Excluir',
                color: AppColors.red,
                height: 32,
                onTap: _busy ? null : _delete,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: SmallButton(
              key: const ValueKey('agent-test'),
              label: 'Testar em sessão',
              height: 32,
              onTap: _busy ? null : _test,
            ),
          ),
          const SizedBox(width: 8),
          AmberButton(
            key: const ValueKey('agent-save'),
            label: _busy ? 'Salvando…' : 'Salvar',
            height: 32,
            onTap: _busy || !dirty ? null : save,
          ),
        ],
      ),
    );
  }

  Widget _identity() {
    final known = agentModels.map((m) => m.$1).toList();
    final model = _model ?? 'inherit';
    final custom = known.contains(model) ? null : model;
    return AgentCard(
      title: 'Identidade',
      children: [
        const FieldLabel('Nome'),
        TextField(
          key: const ValueKey('agent-name'),
          controller: _name,
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
          decoration: agentFieldDecoration('ex.: code-reviewer'),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Quando usar este agente'),
        TextField(
          key: const ValueKey('agent-description'),
          controller: _description,
          minLines: 1,
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
          decoration: agentFieldDecoration(
            'O Claude decide delegar a partir deste texto',
          ),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Modelo'),
        Row(
          children: [
            for (final (id, label) in [...agentModels, ?_customModel(custom)])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ToggleBox(
                    key: ValueKey('agent-model-$id'),
                    on: model == id,
                    height: 34,
                    onTap: () => setState(() {
                      _model = id == 'inherit' && !_base.has('model')
                          ? null
                          : id;
                    }),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: model == id
                            ? AppColors.amber
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const FieldLabel('Esforço (effort)'),
        _effortRow(),
        const SizedBox(height: 12),
        const FieldLabel('Escopo'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _scopeBox(
                AgentScope.global,
                'Global',
                'Todos os workspaces e o claude fora do app',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _scopeBox(
                AgentScope.project,
                'Só este projeto',
                widget.workspace == null
                    ? 'Selecione um workspace'
                    : 'Vai para o git e sobrescreve o global',
              ),
            ),
          ],
        ),
      ],
    );
  }

  (String, String)? _customModel(String? custom) =>
      custom == null ? null : (custom, custom);

  /// "Padrão" removes `effort` (the session's effort applies); a value the
  /// app does not know stays selectable as written in the file.
  Widget _effortRow() {
    final effort = _effort ?? defaultEffort;
    return Row(
      children: [
        for (final id in {...effortChoices, effort})
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ToggleBox(
                key: ValueKey('agent-effort-$id'),
                on: effort == id,
                height: 34,
                onTap: () =>
                    setState(() => _effort = id == defaultEffort ? null : id),
                child: Text(
                  id == defaultEffort ? 'Padrão' : id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: effort == id
                        ? AppColors.amber
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _scopeBox(AgentScope scope, String title, String hint) => ToggleBox(
    key: ValueKey('agent-scope-${scope.name}'),
    on: _scope == scope,
    radius: 8,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    onTap: scope == AgentScope.project && widget.workspace == null
        ? null
        : () => setState(() => _scope = scope),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _promptCard() => AgentCard(
    title: 'Prompt de sistema',
    children: [
      TextField(
        key: const ValueKey('agent-prompt'),
        controller: _prompt,
        minLines: 12,
        maxLines: 28,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12,
          height: 1.6,
        ),
        decoration: agentFieldDecoration(
          'Você é um engenheiro sênior. Leia a spec antes de começar…',
        ),
      ),
    ],
  );

  Widget _toolsCard() {
    final others = parseToolList(_otherTools.text);
    final count = _tools.length + others.length;
    return AgentCard(
      title: 'Ferramentas',
      trailing: Text(
        '${_tools.length} de ${agentToolPills.length}'
        '${others.isEmpty ? '' : ' + ${others.length}'}',
        key: const ValueKey('agent-tool-count'),
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in agentToolPills)
              TogglePill(
                key: ValueKey('agent-tool-$t'),
                label: t,
                on: _tools.contains(t),
                onTap: () => setState(() {
                  _toolsTouched = true;
                  _tools.contains(t) ? _tools.remove(t) : _tools.add(t);
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('agent-tools-other'),
          controller: _otherTools,
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
          decoration: agentFieldDecoration(
            'Outras: Bash(git *), mcp__servidor__ferramenta',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          count == 0
              ? 'Nenhuma selecionada: o agente herda todas as ferramentas.'
              : 'Só estas ficam disponíveis para o agente (tools).',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _execution(List<String> mcpKnown) {
    final perm = _permission ?? 'default';
    final known = agentPermissionModes.map((p) => p.$1).toList();
    final mcpAll = [
      ...mcpKnown,
      for (final m in _mcp)
        if (!mcpKnown.contains(m)) m,
    ];
    return AgentCard(
      title: 'Execução',
      children: [
        const FieldLabel('Modo de permissão'),
        Row(
          children: [
            for (final (id, hint) in [
              ...agentPermissionModes,
              if (!known.contains(perm)) (perm, 'definido no arquivo'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ToggleBox(
                    key: ValueKey('agent-perm-$id'),
                    on: perm == id,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    onTap: () => setState(() {
                      _permission =
                          id == 'default' && !_base.has('permissionMode')
                          ? null
                          : id;
                    }),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: perm == id
                                ? AppColors.amber
                                : AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Orçamento máximo por sessão',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                key: const ValueKey('agent-budget'),
                controller: _budget,
                style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
                decoration: agentFieldDecoration(r'$ —'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Máx. de turnos (maxTurns)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                key: const ValueKey('agent-max-turns'),
                controller: _maxTurns,
                style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
                decoration: agentFieldDecoration('—'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const FieldLabel('Servidores MCP'),
        if (mcpAll.isEmpty)
          const Text(
            'Nenhum servidor em ~/.claude.json ou .mcp.json.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in mcpAll)
                TogglePill(
                  key: ValueKey('agent-mcp-$m'),
                  label: m,
                  on: _mcp.contains(m),
                  onTap: () => setState(() {
                    _mcpTouched = true;
                    _mcp.contains(m) ? _mcp.remove(m) : _mcp.add(m);
                  }),
                ),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey('agent-error'),
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
      ],
    );
  }

  Widget _preview(AgentFile file) {
    final text = file.serialize();
    return AgentCard(
      title: 'Arquivo gerado',
      trailing: Flexible(
        child: Text(
          _displayPath(_targetPath),
          key: const ValueKey('agent-path'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 11,
            color: AppColors.amber,
          ),
        ),
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText.rich(
            key: const ValueKey('agent-preview'),
            previewSpan(text),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              height: 1.65,
              color: AppColors.text,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'O orçamento fica no Promptorium e vira --max-budget-usd ao abrir a '
          'sessão; maxTurns também é passado como --max-turns. O CLI não '
          'aplica permissionMode com --agent: a Nova sessão pré-seleciona o '
          'modo e o esforço (--effort) do agente.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Colored preview: `---` dimmed, top-level keys lilac; the body is cut
/// after [bodyLines] lines.
TextSpan previewSpan(String text, {int bodyLines = 8}) {
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  final spans = <InlineSpan>[];
  var fences = 0, body = 0;
  final keyRe = RegExp(r'^([A-Za-z_][A-Za-z0-9_-]*:)(.*)$');
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final nl = i == lines.length - 1 ? '' : '\n';
    if (fences < 2 && l.trimRight() == '---') {
      fences++;
      spans.add(
        TextSpan(
          text: '$l$nl',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
      continue;
    }
    if (fences >= 2) {
      if (body == bodyLines) {
        spans.add(
          const TextSpan(
            text: '…',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        );
        break;
      }
      body++;
      spans.add(TextSpan(text: '$l$nl'));
      continue;
    }
    final m = keyRe.firstMatch(l);
    if (m != null) {
      spans.add(
        TextSpan(
          text: m.group(1),
          style: const TextStyle(color: AppColors.lilac),
        ),
      );
      spans.add(TextSpan(text: '${m.group(2)}$nl'));
    } else {
      spans.add(TextSpan(text: '$l$nl'));
    }
  }
  return TextSpan(children: spans);
}

String formatBudget(double v) => v.toStringAsFixed(2);

String _leadingNewlines(String s) {
  var i = 0;
  while (i < s.length && (s[i] == '\n')) {
    i++;
  }
  return s.substring(0, i);
}
