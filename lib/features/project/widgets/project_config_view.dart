import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/agent_trailer.dart';
import '../../../core/git/git_service.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/agent_names.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_file.dart' show SpecSubagent;
import '../../specs/widgets/subagents_editor.dart';
import '../../sessions/session_manager.dart' show markedSessionsProvider;
import '../project_config.dart';
import 'agent_trailer_dialog.dart';

/// Whether the workspace already has code: any entry besides git / app /
/// editor folders and the specs folder.
final hasExistingCodeProvider = FutureProvider.family<bool, String>((
  ref,
  path,
) async {
  const ignored = {'.git', '.promptorium', '.claude', '.idea', '.vscode'};
  try {
    final specs = ProjectConfig.loadSync(path).specsDir.split('/').first;
    await for (final e in Directory(path).list()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!ignored.contains(name) && name != specs) return true;
    }
  } catch (_) {
    // unreadable folder: treated as new
  }
  return false;
});

/// First marked commit and how many there are on the base branch
/// (status line of the Git group, SPEC-048 R1 / R5).
final agentMarkInfoProvider =
    FutureProvider.family<({DateTime? since, int count}), String>((
      ref,
      path,
    ) async {
      final branch = ProjectConfig.loadSync(path).baseBranch ?? 'HEAD';
      final git = ref.read(gitServiceFactoryProvider)(path);
      return (
        since: await git.agentMarkSince(branch),
        count: await git.agentMarkCount(branch),
      );
    });

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// Status line of the option (SPEC-048 R1, R8) and whether it is good news.
({String text, Color color}) agentMarkStatus({
  required bool saved,
  required bool edited,
  required bool gitOk,
  DateTime? since,
  int count = 0,
  int liveMarked = 0,
}) {
  if (!gitOk) {
    return (
      text: 'Precisa do git $agentTrailerMinGitLabel ou mais novo',
      color: AppColors.red,
    );
  }
  if (edited != saved) {
    return (
      text: edited
          ? 'Liga nas próximas sessões, depois de salvar'
          : 'Desliga nas próximas sessões, depois de salvar',
      color: AppColors.amber,
    );
  }
  if (saved) {
    if (since == null) {
      return (
        text: 'Ligado · nenhum commit marcado ainda',
        color: CanvasColors.done,
      );
    }
    final d = since.toLocal();
    final n = count == 1 ? '1 commit marcado' : '$count commits marcados';
    return (
      text: 'Ligado desde ${d.day} ${_months[d.month - 1]} · $n',
      color: CanvasColors.done,
    );
  }
  if (liveMarked > 0) {
    return (text: 'Desliga nas próximas sessões', color: AppColors.amber);
  }
  return (text: 'Desligado', color: AppColors.textMuted);
}

/// "Configuração do projeto": where the specs live, how tests run, the base
/// branch, the default agent and the subagents of every spec. Saved to
/// `.promptorium/config.yml` in the repository.
class ProjectConfigView extends ConsumerStatefulWidget {
  const ProjectConfigView({
    super.key,
    required this.workspace,
    this.onPlan,
    this.intro,
  });

  final Workspace workspace;

  /// "Planejar um novo roadmap" (null = no button).
  final VoidCallback? onPlan;
  final String? intro;

  @override
  ConsumerState<ProjectConfigView> createState() => _ProjectConfigViewState();
}

/// Field to focus when the project config opens ("Testar" without
/// `executar:` opens it on that field, SPEC-032 R9).
class ConfigFocus extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? field) => state = field;
}

final configFocusProvider = NotifierProvider<ConfigFocus, String?>(
  ConfigFocus.new,
);

class _ProjectConfigViewState extends ConsumerState<ProjectConfigView> {
  late final bool _focusRun = () {
    final focus = ref.read(configFocusProvider) == 'executar';
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(configFocusProvider.notifier).set(null);
      });
    }
    return focus;
  }();
  late ProjectConfig _saved = ProjectConfig.loadSync(widget.workspace.path);
  late final _specs = TextEditingController(text: _saved.specsDir);
  late final _tests = TextEditingController(text: _saved.testCommand ?? '');
  late final _branch = TextEditingController(text: _saved.baseBranch ?? '');
  late final _lint = TextEditingController(text: _saved.lintCommand ?? '');
  late final _build = TextEditingController(text: _saved.buildCommand ?? '');
  late final _format = TextEditingController(text: _saved.formatCommand ?? '');
  late final _run = TextEditingController(text: _saved.runCommand ?? '');
  late final _editor = TextEditingController(text: _saved.editorCommand ?? '');
  late final _attempts = TextEditingController(text: '${_saved.gate.attempts}');
  late final _timeout = TextEditingController(
    text: '${_saved.gate.timeoutSeconds}',
  );
  late final _blocked = TextEditingController(
    text: _saved.blockedCommands.join('\n'),
  );
  late final _copy = TextEditingController(
    text: _saved.worktree.copy.join(', '),
  );
  late final _prepare = TextEditingController(
    text: _saved.worktree.prepare ?? '',
  );
  late final _port = TextEditingController(
    text: _saved.worktree.basePort?.toString() ?? '',
  );
  late final _dev = TextEditingController(text: _saved.dev?.command ?? '');
  late final _devReady = TextEditingController(
    text: _saved.dev?.readyText ?? '',
  );
  late final _devPath = TextEditingController(
    text: _saved.dev == null || _saved.dev!.path == '/' ? '' : _saved.dev!.path,
  );
  late bool _reviewerOn = _saved.reviewer.enabled;
  late final _reviewerModel = TextEditingController(
    text: _saved.reviewer.model,
  );
  late final _reviewerBudget = TextEditingController(
    text: '${_saved.reviewer.budgetUsd}',
  );
  late final _reviewerRounds = TextEditingController(
    text: '${_saved.reviewer.rounds}',
  );
  late bool _requireCommit = _saved.gate.requireCommit;
  late bool _requireClean = _saved.gate.requireCleanTree;
  late bool _markAgents = _saved.git.markAgentCommits;
  late String? _agent = _saved.agent;
  late List<SpecSubagent> _subagents = _saved.subagents;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _specs.dispose();
    _tests.dispose();
    _branch.dispose();
    for (final c in [
      _lint,
      _build,
      _format,
      _run,
      _editor,
      _attempts,
      _timeout,
      _blocked,
      _copy,
      _prepare,
      _port,
      _dev,
      _devReady,
      _devPath,
      _reviewerModel,
      _reviewerBudget,
      _reviewerRounds,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// The verification as edited; null when it equals the defaults and the
  /// file did not have it (the file stays as it was).
  VerificationConfig? get _verification {
    const d = VerificationConfig();
    final v = VerificationConfig(
      attempts: int.tryParse(_attempts.text.trim()) ?? d.attempts,
      timeoutSeconds: int.tryParse(_timeout.text.trim()) ?? d.timeoutSeconds,
      requireCommit: _requireCommit,
      requireCleanTree: _requireClean,
      // Not edited here (SPEC-023 R5): kept as the file has it.
      countTests: _saved.gate.countTests,
    );
    return v.isDefault && _saved.verification == null ? null : v;
  }

  // Built on the saved config: keys this view does not edit are kept.
  ProjectConfig get _current => _saved.copyWith(
    specsDir: _specs.text.trim().isEmpty
        ? ProjectConfig.defaultSpecsDir
        : _specs.text.trim(),
    testCommand: () => _text(_tests),
    lintCommand: () => _text(_lint),
    buildCommand: () => _text(_build),
    formatCommand: () => _text(_format),
    runCommand: () => _text(_run),
    editorCommand: () => _text(_editor),
    baseBranch: () => _text(_branch),
    agent: () => _agent,
    subagents: _subagents,
    verification: () => _verification,
    blockedCommands: [
      for (final l in _blocked.text.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ],
    worktree: WorktreeConfig(
      copy: [
        for (final f in _copy.text.split(RegExp(r'[,\n]')))
          if (f.trim().isNotEmpty) f.trim(),
      ],
      prepare: _text(_prepare),
      basePort: int.tryParse(_port.text.trim()),
    ),
    dev: () => _devConfig,
    reviewer: ReviewerConfig(
      enabled: _reviewerOn,
      model: _text(_reviewerModel) ?? const ReviewerConfig().model,
      budgetUsd:
          double.tryParse(_reviewerBudget.text.trim().replaceAll(',', '.')) ??
          const ReviewerConfig().budgetUsd,
      rounds:
          int.tryParse(_reviewerRounds.text.trim()) ??
          const ReviewerConfig().rounds,
    ),
    git: GitConfig(markAgentCommits: _markAgents),
  );

  /// `dev:` from the three fields (SPEC-051 R1); empty command = none.
  DevServerConfig? get _devConfig {
    final command = _text(_dev);
    if (command == null) return null;
    var path = _text(_devPath) ?? '/';
    if (!path.startsWith('/')) path = '/$path';
    final ready = _text(_devReady);
    return DevServerConfig(
      command: command,
      readyText: ready == 'porta' ? null : ready,
      path: path,
    );
  }

  bool get _dirty => _current != _saved;

  Future<void> _save() async {
    final c = _current;
    final err = ProjectConfig.validateSpecsDir(c.specsDir);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (c.baseBranch != null && c.baseBranch!.startsWith('-')) {
      setState(() => _error = 'Branch base inválida.');
      return;
    }
    final attempts = int.tryParse(_attempts.text.trim());
    final timeout = int.tryParse(_timeout.text.trim());
    if (attempts == null || attempts < 0 || timeout == null || timeout < 1) {
      setState(
        () => _error = 'Tentativas: número ≥ 0; tempo limite: segundos (≥ 1).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ProjectConfig.save(widget.workspace.path, c);
      _saved = c;
      ref.invalidate(projectConfigProvider);
      ref.invalidate(hasExistingCodeProvider);
      ref.invalidate(agentMarkInfoProvider(widget.workspace.path));
      messenger?.showAppToast(
        const SnackBar(
          content: Text(
            'Configuração salva em .promptorium/config.yml '
            '(faça commit para o time receber).',
          ),
        ),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Falha ao salvar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String text, [String? hint]) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _field(
    Key key,
    TextEditingController c,
    String hint, {
    Widget? suffix,
  }) => TextField(
    key: key,
    controller: c,
    style: const TextStyle(fontSize: 13, fontFamily: AppFonts.mono),
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      suffixIcon: suffix,
    ),
    onChanged: (_) => setState(() {}),
  );

  /// Native folder chooser, starting at the current specs folder (or the
  /// repository); the answer must be a subfolder of the repository.
  Future<void> _pickSpecsDir() async {
    final root = widget.workspace.path;
    final current = _specs.text.trim();
    final start = current.isNotEmpty && Directory('$root/$current').existsSync()
        ? '$root/$current'
        : root;
    final picked = await ref.read(directoryPickerProvider)(
      initialDirectory: start,
    );
    if (picked == null || !mounted) return;
    final rel = ProjectConfig.relativeDir(root, picked);
    setState(() {
      if (rel == null) {
        _error = 'Escolha uma subpasta de $root.';
        return;
      }
      _error = null;
      _specs.text = rel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.workspace.path;
    final agents =
        ref.watch(agentListProvider(path)).value ?? const <AgentRef>[];
    final specsChanged =
        _specs.text.trim() != _saved.specsDir && _specs.text.trim().isNotEmpty;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        // Save / error stay visible below the scrolling form.
        child: Column(
          children: [
            Expanded(child: _form(path, agents, specsChanged)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        key: const ValueKey('config-error'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      AmberButton(
                        key: const ValueKey('config-save'),
                        label: 'Salvar',
                        height: 34,
                        onTap: _dirty && !_busy ? _save : null,
                      ),
                      const SizedBox(width: 8),
                      if (widget.onPlan != null)
                        SmallButton(
                          key: const ValueKey('config-plan'),
                          label: 'Planejar um novo roadmap…',
                          height: 34,
                          onTap: widget.onPlan,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Group "Git" (SPEC-048 R1): the marking of agent commits.
  Widget _gitGroup(String path) {
    final git = ref.watch(gitVersionProvider);
    final info = ref.watch(agentMarkInfoProvider(path)).value;
    final live = ref
        .watch(markedSessionsProvider)
        .values
        .where((r) => r == path)
        .length;
    final status = agentMarkStatus(
      saved: _saved.git.markAgentCommits,
      edited: _markAgents,
      // Unknown yet (reading git) counts as fine: no flash of the warning.
      gitOk: !git.hasValue || gitSupportsAgentTrailer(git.value),
      since: info?.since,
      count: info?.count ?? 0,
      liveMarked: live,
    );
    return Container(
      key: const ValueKey('config-git-group'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Git',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Checkbox(
                key: const ValueKey('config-mark-agents'),
                value: _markAgents,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => _markAgents = v ?? false),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () => setState(() => _markAgents = !_markAgents),
                  child: const Text(
                    'Marcar commits feitos por agentes',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              agentTrailerInfoTip(),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: status.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    status.text,
                    key: const ValueKey('config-mark-agents-status'),
                    style: TextStyle(fontSize: 12, color: status.color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(
    String path,
    List<AgentRef> agents,
    bool specsChanged,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    children: [
      Text(
        'Configuração de ${widget.workspace.name}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        widget.intro ??
            'Fica em ${ProjectConfig.filePath}, dentro do repositório: '
                'faça commit para o time usar o mesmo.',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      _label('Pasta das specs', 'relativa ao repositório (padrão: specs)'),
      _field(
        const ValueKey('config-specs'),
        _specs,
        'specs',
        suffix: IconButton(
          key: const ValueKey('config-specs-pick'),
          tooltip: 'Escolher pasta…',
          icon: const Icon(Icons.folder_open, size: 18),
          onPressed: _pickSpecsDir,
        ),
      ),
      if (specsChanged)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'As specs que já existem continuam onde estão e na lista; '
            'só as novas vão para a pasta nova. Mova os arquivos se '
            'quiser juntar tudo.',
            key: ValueKey('config-specs-warning'),
            style: TextStyle(fontSize: 11, color: AppColors.amber),
          ),
        ),
      _label('Comando de testes', 'as sessões rodam isto antes de cada commit'),
      _field(const ValueKey('config-tests'), _tests, 'ex.: pytest -q'),
      _label(
        'Verificação das etapas',
        'roda no worktree antes de marcar a etapa como feita',
      ),
      _field(const ValueKey('config-lint'), _lint, 'lint: ex.: ruff check'),
      const SizedBox(height: 6),
      _field(
        const ValueKey('config-build'),
        _build,
        'build: ex.: make build (opcional)',
      ),
      const SizedBox(height: 6),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 6,
        children: [
          SizedBox(
            width: 80,
            child: _field(
              const ValueKey('config-attempts'),
              _attempts,
              'tentativas',
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'reenvios ao agente',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: _field(
              const ValueKey('config-timeout'),
              _timeout,
              'segundos',
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            's por comando',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
      CheckboxListTile(
        key: const ValueKey('config-require-commit'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _requireCommit,
        title: const Text(
          'Exigir commit da etapa',
          style: TextStyle(fontSize: 12),
        ),
        onChanged: (v) => setState(() => _requireCommit = v ?? true),
      ),
      CheckboxListTile(
        key: const ValueKey('config-require-clean'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _requireClean,
        title: const Text(
          'Exigir árvore limpa (nada sem commit)',
          style: TextStyle(fontSize: 12),
        ),
        onChanged: (v) => setState(() => _requireClean = v ?? true),
      ),
      const SizedBox(height: 16),
      _gitGroup(path),
      _label('Formatar ao editar', '{arquivo} = arquivo editado pelo agente'),
      _field(
        const ValueKey('config-format'),
        _format,
        'ex.: dart format {arquivo}',
      ),
      _label(
        'Executar o app',
        '"Testar" da Review roda no worktree da spec, sem trocar a raiz',
      ),
      TextField(
        key: const ValueKey('config-run'),
        controller: _run,
        autofocus: _focusRun,
        style: const TextStyle(fontSize: 13, fontFamily: AppFonts.mono),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'ex.: flutter run -d linux',
        ),
        onChanged: (_) => setState(() {}),
      ),
      _label('Editor', 'abre o worktree da Review (padrão: code)'),
      _field(const ValueKey('config-editor'), _editor, 'ex.: code'),
      _label(
        'Comandos bloqueados',
        'um por linha; * = qualquer coisa (soma à lista embutida)',
      ),
      TextField(
        key: const ValueKey('config-blocked'),
        controller: _blocked,
        minLines: 2,
        maxLines: 6,
        style: const TextStyle(fontSize: 13, fontFamily: AppFonts.mono),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'git push --force*',
        ),
        onChanged: (_) => setState(() {}),
      ),
      _label(
        'Worktree pronto para rodar',
        'ao criar o worktree de uma spec ou sessão',
      ),
      _field(
        const ValueKey('config-copy'),
        _copy,
        'copiar (ignorados pelo git): ex.: .env, .env.local',
      ),
      const SizedBox(height: 6),
      _field(
        const ValueKey('config-prepare'),
        _prepare,
        'preparar: ex.: npm ci',
      ),
      const SizedBox(height: 6),
      _field(
        const ValueKey('config-port'),
        _port,
        'porta base: ex.: 4000 (PROMPTORIUM_PORT = base + índice)',
      ),
      _label(
        'Servidor de desenvolvimento',
        'o app sobe no worktree da spec · sem porta base, escolhe uma livre',
      ),
      _field(
        const ValueKey('config-dev'),
        _dev,
        r'comando: ex.: npm run dev -- --port $PROMPTORIUM_PORT',
      ),
      const SizedBox(height: 6),
      _field(
        const ValueKey('config-dev-ready'),
        _devReady,
        'pronto: vazio = a porta responde HTTP; ou um texto do log',
      ),
      const SizedBox(height: 6),
      _field(
        const ValueKey('config-dev-path'),
        _devPath,
        'caminho do preview: ex.: /login (padrão /)',
      ),
      _label(
        'Revisor automático',
        'revisa a spec terminada antes de você (somente leitura)',
      ),
      CheckboxListTile(
        key: const ValueKey('config-reviewer'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _reviewerOn,
        title: const Text(
          'Ligado: aprova ou devolve a spec com apontamentos',
          style: TextStyle(fontSize: 12),
        ),
        onChanged: (v) => setState(() => _reviewerOn = v ?? false),
      ),
      if (_reviewerOn)
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SizedBox(
              width: 140,
              child: _field(
                const ValueKey('config-reviewer-model'),
                _reviewerModel,
                'modelo',
              ),
            ),
            SizedBox(
              width: 140,
              child: _field(
                const ValueKey('config-reviewer-budget'),
                _reviewerBudget,
                'US\$ por rodada',
              ),
            ),
            SizedBox(
              width: 140,
              child: _field(
                const ValueKey('config-reviewer-rounds'),
                _reviewerRounds,
                'rodadas',
              ),
            ),
          ],
        ),
      _label(
        'Branch base',
        'origem dos worktrees e destino do merge (vazio = a atual)',
      ),
      _field(const ValueKey('config-branch'), _branch, 'ex.: main'),
      _label('Agente padrão', 'usado nas specs sem agente próprio'),
      DropdownButton<String?>(
        key: const ValueKey('config-agent'),
        isExpanded: true,
        isDense: true,
        value: agents.any((a) => a.name == _agent) ? _agent : null,
        hint: const Text('(nenhum)', style: TextStyle(fontSize: 13)),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('(nenhum)', style: TextStyle(fontSize: 13)),
          ),
          for (final a in agents)
            DropdownMenuItem<String?>(
              value: a.name,
              child: Text(a.name, style: const TextStyle(fontSize: 13)),
            ),
        ],
        onChanged: (v) => setState(() => _agent = v),
      ),
      _label('Subagentes de toda spec', 'somados aos da própria spec'),
      SubagentsEditor(
        mainAgent: _agent,
        workspacePath: path,
        subagents: _subagents,
        allowStep: false,
        initiallyOpen: true,
        onChange: (l) => setState(() => _subagents = l),
      ),
    ],
  );
}
