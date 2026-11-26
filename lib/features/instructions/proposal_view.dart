import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart' show gitServiceFactoryProvider;
import '../../core/providers/instructions_files.dart';
import '../../core/providers/structured_run.dart' show providerDisplayName;
import '../../core/providers/workspace_assets.dart';
import '../../data/providers.dart' show Workspace;
import '../../ui/providers/provider_logos.dart';
import '../../ui/theme/tokens.dart';
import '../project/widgets/project_widgets.dart';
import '../sessions/widgets/session_style.dart';
import 'interview_controller.dart';
import 'proposal_apply.dart';

/// The proposal of the interview (SPEC-113 R19–R21, mock `5-proposta.png`):
/// each trecho with its file, section, questions of origin and diff, to
/// accept, edit, refuse or undo; on the right what the files become, the
/// check of the cited paths and "Commitar ao aplicar" with the branch.
/// A standalone widget: the tab Projeto › Instruções (T3) shows it when the
/// interview hands the proposal over.
///
/// [onDone] runs after "Concluir" (the trechos were applied) and after
/// "Descartar proposta"; [onBackToInterview] (hidden when null) goes back to
/// the interview while nothing was applied.
class InstructionsProposalView extends ConsumerStatefulWidget {
  const InstructionsProposalView({
    super.key,
    required this.workspace,
    required this.proposal,
    required this.onDone,
    this.onBackToInterview,
  });

  final Workspace workspace;
  final InstructionProposal proposal;
  final VoidCallback onDone;
  final VoidCallback? onBackToInterview;

  @override
  ConsumerState<InstructionsProposalView> createState() =>
      _InstructionsProposalViewState();
}

/// Where a trecho is (R19).
enum ProposalHunkState { pending, accepted, rejected, applied, conflict }

class _Item {
  _Item(this.original) : hunk = original;

  final InstructionProposalHunk original;
  InstructionProposalHunk hunk;
  ProposalHunkState state = ProposalHunkState.pending;
  ProposalConflictKind? conflict;
  bool editing = false;
  TextEditingController? oldText;
  TextEditingController? newText;

  void dispose() {
    oldText?.dispose();
    newText?.dispose();
  }
}

class _InstructionsProposalViewState
    extends ConsumerState<InstructionsProposalView> {
  late final List<_Item> _items = [
    for (final h in widget.proposal.hunks) _Item(h),
  ];

  /// The root files as read when the screen opened (or after a write).
  Map<String, String?>? _texts;
  List<CitedPath>? _paths;
  InstructionsCommitTarget? _target;
  bool _commit = false;
  bool _busy = false;
  String? _error;

  /// The last "Aplicar" that wrote something.
  ProposalApplyResult? _result;

  /// How many trechos the last "Aplicar" sent back as conflicts.
  int _lastConflicts = 0;
  bool _undone = false;

  String get _root => widget.workspace.path;

  @override
  void initState() {
    super.initState();
    _load();
    _checkPaths();
    _readTarget();
  }

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<Map<String, String?>> _read() async => {
    for (final f in instructionRootFiles)
      f: (await readInstructionsSnapshot('$_root/$f')).text,
  };

  Future<void> _load() async {
    final texts = await _read();
    if (mounted) setState(() => _texts = texts);
  }

  Future<void> _checkPaths() async {
    final paths = await checkCitedPaths(_root, _items.map((i) => i.hunk));
    if (mounted) setState(() => _paths = paths);
  }

  Future<void> _readTarget() async {
    final git = ref.read(gitServiceFactoryProvider)(_root);
    InstructionsCommitTarget target;
    try {
      target = await readCommitTarget(_root, git);
    } catch (_) {
      target = const InstructionsCommitTarget(isRepo: false);
    }
    if (mounted) setState(() => _target = target);
  }

  // --- Decisões ---------------------------------------------------------------

  void _set(_Item i, ProposalHunkState s) => setState(() {
    i.state = s;
    i.conflict = null;
    _error = null;
  });

  /// "Desfazer" of a trecho: back to what the AI proposed, to decide.
  void _undoDecision(_Item i) => setState(() {
    i.state = ProposalHunkState.pending;
    i.hunk = i.original;
    i.conflict = null;
    i.editing = false;
  });

  void _acceptAll() => setState(() {
    for (final i in _items) {
      if (i.state == ProposalHunkState.pending) {
        i.state = ProposalHunkState.accepted;
      }
    }
  });

  void _edit(_Item i) => setState(() {
    i.oldText?.dispose();
    i.newText?.dispose();
    i.oldText = TextEditingController(text: i.hunk.oldText);
    i.newText = TextEditingController(text: i.hunk.newText);
    i.editing = true;
  });

  /// "Salvar" of the editor: the edited trecho is accepted.
  void _saveEdit(_Item i) {
    final h = i.hunk;
    setState(() {
      i.hunk = InstructionProposalHunk(
        file: h.file,
        section: h.section,
        oldText: i.oldText!.text,
        newText: i.newText!.text,
        questions: h.questions,
      );
      i.editing = false;
      i.state = ProposalHunkState.accepted;
      i.conflict = null;
    });
    _checkPaths();
  }

  List<_Item> get _accepted => [
    for (final i in _items)
      if (i.state == ProposalHunkState.accepted) i,
  ];

  // --- Aplicar ----------------------------------------------------------------

  Future<void> _apply() async {
    final accepted = _accepted;
    if (accepted.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await applyInstructionProposal(
        root: _root,
        hunks: [for (final i in accepted) i.hunk],
        commit: _commit && (_target?.canCommit ?? false),
        git: ref.read(gitServiceFactoryProvider)(_root),
      );
      if (result.wrote) {
        // The trechos are in the files: the interview is done (R19).
        await ref
            .read(instructionInterviewProvider(widget.workspace.id).notifier)
            .discard();
      }
      final texts = result.wrote ? await _read() : null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (texts != null) _texts = texts;
        for (var k = 0; k < accepted.length; k++) {
          final c = result.conflicts[k];
          accepted[k].state = c == null
              ? ProposalHunkState.applied
              : ProposalHunkState.conflict;
          accepted[k].conflict = c;
        }
        _lastConflicts = result.conflicts.length;
        if (result.wrote) {
          _result = result;
          _undone = false;
        }
      });
    } on InstructionsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Não foi possível aplicar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Desfazer" of the write (R5): the files go back to what they were.
  Future<void> _undoWrite() async {
    final r = _result;
    if (r?.write == null || _busy) return;
    setState(() => _busy = true);
    try {
      await undoInstructionWrite(r!.write!);
      final texts = await _read();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _texts = texts;
        _undone = true;
        for (final i in _items) {
          if (i.state == ProposalHunkState.applied) {
            i.state = ProposalHunkState.accepted;
          }
        }
      });
    } on InstructionsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelSolid,
        title: const Text(
          'Descartar a proposta?',
          style: TextStyle(fontSize: 15, color: AppColors.text),
        ),
        content: const Text(
          'A entrevista e a proposta saem do projeto. Os arquivos não mudam.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          SmallButton(
            label: 'Cancelar',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          AmberButton(
            key: const ValueKey('proposal-discard-confirm'),
            label: 'Descartar',
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref
        .read(instructionInterviewProvider(widget.workspace.id).notifier)
        .discard();
    if (mounted) widget.onDone();
  }

  // --- Tela -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final texts = _texts;
    final plan = texts == null
        ? null
        : planProposal(texts, [for (final i in _accepted) i.hunk]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _list()),
              const VerticalDivider(width: 1, color: AppColors.border),
              SizedBox(width: 296, child: _side(plan)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar() {
    final p = widget.proposal;
    final questions = p.questions.isNotEmpty
        ? p.questions.length
        : {for (final h in p.hunks) ...h.questions}.length;
    final model = p.model;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text(
            'Proposta da IA',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 10),
          if (questions > 0) ...[
            _Tag(
              questions == 1 ? '1 pergunta' : '$questions perguntas',
              color: AppColors.lilac,
              border: projectLilacBorder,
              background: projectLilacBg,
            ),
            const SizedBox(width: 8),
          ],
          ProviderChip(
            p.provider,
            key: const ValueKey('proposal-provider'),
            dense: true,
            name: [
              providerDisplayName(p.provider),
              if (model case final m? when m.isNotEmpty) m,
            ].join(' · '),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _counts(),
              key: const ValueKey('proposal-counts'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (widget.onBackToInterview != null && _result == null)
            SmallButton(
              key: const ValueKey('proposal-back'),
              label: 'Voltar à entrevista',
              onTap: widget.onBackToInterview,
            ),
        ],
      ),
    );
  }

  /// "4 trechos · 2 aceitos, 1 recusado, 1 a decidir".
  String _counts() {
    int n(ProposalHunkState s) => _items.where((i) => i.state == s).length;
    String plural(int k, String one, String many) => k == 1 ? one : many;
    final total = _items.length;
    final parts = [
      if (n(ProposalHunkState.applied) case final a when a > 0)
        '$a ${plural(a, 'aplicado', 'aplicados')}',
      if (n(ProposalHunkState.accepted) case final a when a > 0)
        '$a ${plural(a, 'aceito', 'aceitos')}',
      if (n(ProposalHunkState.rejected) case final r when r > 0)
        '$r ${plural(r, 'recusado', 'recusados')}',
      if (n(ProposalHunkState.conflict) case final c when c > 0)
        '$c em conflito',
      if (n(ProposalHunkState.pending) case final p when p > 0) '$p a decidir',
    ];
    return '$total ${plural(total, 'trecho', 'trechos')}'
        '${parts.isEmpty ? '' : ' · ${parts.join(', ')}'}';
  }

  Widget _list() {
    final pending = _items.any((i) => i.state == ProposalHunkState.pending);
    final accepted = _accepted.length;
    final r = _result;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.proposal.endedEarly) ...[
            const NoticeBox.warning(
              key: ValueKey('proposal-ended-early'),
              text:
                  'A entrevista foi encerrada antes do fim: o que ficou '
                  'aberto não virou regra.',
            ),
            const SizedBox(height: 10),
          ],
          if (_items.isEmpty)
            const Expanded(
              child: StepEmpty(
                title: 'Nada a mudar',
                text: 'A IA não propôs mudanças nos arquivos de instruções.',
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, k) => _card(k, _items[k]),
              ),
            ),
          if (_error case final e?) ...[
            const SizedBox(height: 10),
            NoticeBox.error(key: const ValueKey('proposal-error'), text: e),
          ],
          if (_lastConflicts > 0) ...[
            const SizedBox(height: 10),
            NoticeBox.warning(
              key: const ValueKey('proposal-conflicts'),
              text: _lastConflicts == 1
                  ? '1 trecho não casa mais com o arquivo e não foi gravado. '
                        'Edite o texto antigo ou recuse o trecho.'
                  : '$_lastConflicts trechos não casam mais com o arquivo e '
                        'não foram gravados. Edite o texto antigo ou recuse '
                        'os trechos.',
            ),
          ],
          if (r != null) ...[const SizedBox(height: 10), _done(r)],
          const SizedBox(height: 12),
          Row(
            children: [
              SmallButton(
                key: const ValueKey('proposal-accept-all'),
                label: 'Aceitar todos',
                height: 34,
                onTap: pending ? _acceptAll : null,
              ),
              const Spacer(),
              if (r == null) ...[
                SmallButton(
                  key: const ValueKey('proposal-discard'),
                  label: 'Descartar proposta',
                  height: 34,
                  onTap: _busy ? null : _discard,
                ),
                const SizedBox(width: 10),
              ],
              AmberButton(
                key: const ValueKey('proposal-apply'),
                label: accepted == 1
                    ? 'Aplicar 1 trecho'
                    : 'Aplicar $accepted trechos',
                height: 34,
                busy: _busy,
                onTap: accepted == 0 || _texts == null ? null : _apply,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _done(ProposalApplyResult r) {
    final files = r.changed.join(' e ');
    final String text;
    if (_undone) {
      text = 'Desfeito: $files voltaram ao que eram.';
    } else if (r.commitSha case final sha?) {
      text = 'Gravado em $files e commitado em ${r.branch} ($sha), sem push.';
    } else if (r.commitError case final e?) {
      text = 'Gravado em $files, mas o commit falhou: $e';
    } else {
      text = 'Gravado em $files.';
    }
    final committed = r.commitSha != null;
    return Container(
      key: const ValueKey('proposal-done'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SessionColors.runningToolBg,
        border: Border.all(color: SessionColors.runningToolBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: r.commitError != null && !_undone
                    ? AppColors.amber
                    : AppColors.teal,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (!_undone)
            Tooltip(
              message: committed ? 'Já está no commit ${r.commitSha}.' : '',
              child: SmallButton(
                key: const ValueKey('proposal-undo-write'),
                label: 'Desfazer',
                onTap: committed || _busy ? null : _undoWrite,
              ),
            ),
          const SizedBox(width: 8),
          SmallButton(
            key: const ValueKey('proposal-finish'),
            label: 'Concluir',
            color: AppColors.teal,
            border: SessionColors.runningToolBorder,
            background: SessionColors.runningToolBg,
            onTap: widget.onDone,
          ),
        ],
      ),
    );
  }

  // --- Trecho -----------------------------------------------------------------

  Widget _card(int k, _Item i) {
    final h = i.hunk;
    final file = instructionFileOf(h.file) ?? h.file;
    final pending = i.state == ProposalHunkState.pending;
    final conflict = i.state == ProposalHunkState.conflict;
    final newSection = isNewSection(_texts?[file], h);
    final missing = [
      for (final p in _paths ?? const <CitedPath>[])
        if (!p.exists && h.newText.contains('`${p.path}')) p.path,
    ];
    final actions = <Widget>[
      if (i.editing) ...[
        SmallButton(
          key: ValueKey('proposal-hunk-$k-cancel'),
          label: 'Cancelar',
          onTap: () => setState(() => i.editing = false),
        ),
        const SizedBox(width: 6),
        SmallButton(
          key: ValueKey('proposal-hunk-$k-save'),
          label: 'Salvar',
          color: AppColors.teal,
          border: SessionColors.runningToolBorder,
          background: SessionColors.runningToolBg,
          onTap: () => _saveEdit(i),
        ),
      ] else if (pending || conflict) ...[
        SmallButton(
          key: ValueKey('proposal-hunk-$k-edit'),
          label: 'Editar',
          onTap: _busy ? null : () => _edit(i),
        ),
        const SizedBox(width: 6),
        SmallButton(
          key: ValueKey('proposal-hunk-$k-reject'),
          label: 'Recusar',
          onTap: _busy ? null : () => _set(i, ProposalHunkState.rejected),
        ),
        if (pending) ...[
          const SizedBox(width: 6),
          SmallButton(
            key: ValueKey('proposal-hunk-$k-accept'),
            label: 'Aceitar',
            color: AppColors.teal,
            border: SessionColors.runningToolBorder,
            background: SessionColors.runningToolBg,
            onTap: _busy ? null : () => _set(i, ProposalHunkState.accepted),
          ),
        ],
      ] else if (i.state != ProposalHunkState.applied)
        SmallButton(
          key: ValueKey('proposal-hunk-$k-undo'),
          label: 'Desfazer',
          onTap: _busy ? null : () => _undoDecision(i),
        ),
    ];
    final badge = switch (i.state) {
      ProposalHunkState.accepted => const _Tag(
        'aceito',
        color: AppColors.teal,
        border: SessionColors.runningToolBorder,
        background: SessionColors.runningToolBg,
      ),
      ProposalHunkState.rejected => const _Tag('recusado'),
      ProposalHunkState.applied => const _Tag(
        'aplicado',
        color: AppColors.teal,
        border: SessionColors.runningToolBorder,
        background: SessionColors.runningToolBg,
      ),
      ProposalHunkState.conflict => const _Tag(
        'conflito',
        color: AppColors.red,
        border: SessionColors.stopBorder,
        background: SessionColors.delBg,
      ),
      ProposalHunkState.pending => null,
    };
    final highlight = pending || conflict;
    return Container(
      key: ValueKey('proposal-hunk-$k'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pending ? SessionColors.approvalBg : AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: conflict
              ? SessionColors.stopBorder
              : highlight
              ? SessionColors.approvalBorder
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        h.section.isEmpty ? file : '$file › ${h.section}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    for (final q in h.questions) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: widget.proposal.questions[q] ?? '',
                        child: _Tag(q, mono: true),
                      ),
                    ],
                    if (newSection) ...[
                      const SizedBox(width: 8),
                      const _Tag(
                        'seção nova',
                        key: ValueKey('proposal-new-section'),
                        color: AppColors.amber,
                        border: SessionColors.approvalBorder,
                        background: SessionColors.approvalBg,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (badge != null) ...[
                KeyedSubtree(
                  key: ValueKey('proposal-hunk-$k-state'),
                  child: badge,
                ),
                const SizedBox(width: 8),
              ],
              ...actions,
            ],
          ),
          const SizedBox(height: 10),
          if (i.editing)
            _editor(k, i, conflict: conflict)
          else
            _Diff(h, plain: i.state == ProposalHunkState.rejected),
          if (conflict) ...[
            const SizedBox(height: 8),
            Text(
              i.conflict == ProposalConflictKind.otherFile
                  ? 'O trecho é de outro arquivo: só o AGENTS.md e o '
                        'CLAUDE.md da raiz são gravados.'
                  : 'O texto antigo não está mais no $file. Nada deste '
                        'trecho foi gravado.',
              key: ValueKey('proposal-hunk-$k-conflict'),
              style: const TextStyle(fontSize: 12, color: AppColors.red),
            ),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Não existe no projeto: ${missing.join(', ')}',
              key: ValueKey('proposal-hunk-$k-missing'),
              style: const TextStyle(fontSize: 12, color: AppColors.amber),
            ),
          ],
        ],
      ),
    );
  }

  Widget _editor(int k, _Item i, {required bool conflict}) {
    Widget field(String label, TextEditingController c, String key) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: sectionTitleStyle),
        const SizedBox(height: 4),
        TextField(
          key: ValueKey(key),
          controller: c,
          maxLines: null,
          minLines: 2,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            color: AppColors.text,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conflict || !i.hunk.isInsertion) ...[
          field('TEXTO ANTIGO', i.oldText!, 'proposal-hunk-$k-old'),
          const SizedBox(height: 8),
        ],
        field('TEXTO NOVO', i.newText!, 'proposal-hunk-$k-new'),
      ],
    );
  }

  // --- Lateral ----------------------------------------------------------------

  Widget _side(ProposalPlan? plan) {
    final target = _target;
    final paths = _paths;
    final previewConflicts = plan?.conflicts.length ?? 0;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('DEPOIS DE APLICAR', style: sectionTitleStyle),
        const SizedBox(height: 10),
        if (plan != null)
          for (final f in instructionRootFiles)
            if (plan.before[f] != null || plan.after[f] != null) ...[
              _fileCard(f, plan.before[f], plan.after[f]),
              const SizedBox(height: 8),
            ],
        if (previewConflicts > 0) ...[
          NoticeBox.warning(
            key: const ValueKey('proposal-preview-conflicts'),
            text: previewConflicts == 1
                ? '1 trecho aceito não casa mais com o arquivo: ao aplicar, '
                      'ele volta como conflito.'
                : '$previewConflicts trechos aceitos não casam mais com o '
                      'arquivo: ao aplicar, eles voltam como conflito.',
          ),
          const SizedBox(height: 8),
        ],
        if (paths != null && paths.isNotEmpty) ...[
          _pathsBox(paths),
          const SizedBox(height: 8),
        ],
        if (target != null) ...[
          _commitBox(target),
          const SizedBox(height: 8),
          if (target.canCommit && _commit && target.offBase)
            NoticeBox.warning(
              key: const ValueKey('proposal-commit-off-base'),
              text:
                  '${target.branch} não é a base do projeto '
                  '(${target.base}): as specs novas só recebem o texto '
                  'depois do merge.',
            )
          else if (!_commit || !target.canCommit)
            const NoticeBox.warning(
              key: ValueKey('proposal-no-commit'),
              text:
                  'Sem commit, as worktrees das specs continuam com o texto '
                  'antigo.',
            ),
          const SizedBox(height: 10),
        ],
        const Text(
          'Vale para a próxima sessão. As sessões abertas não mudam.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _fileCard(String file, String? before, String? after) {
    final same = before == after;
    final delta = lineDelta(before, after);
    final a = before == null ? 0 : utf8.encode(before).length;
    final b = after == null ? 0 : utf8.encode(after).length;
    return _Box(
      key: ValueKey('proposal-after-$file'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                file,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 13,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Text(
                same
                    ? 'sem mudança'
                    : before == null
                    ? 'novo · ${proposalSize(b)}'
                    : proposalSizeChange(a, b),
                key: ValueKey('proposal-after-$file-size'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (!same) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '+${delta.added}',
                    style: const TextStyle(color: AppColors.teal),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: '−${delta.removed}',
                    style: const TextStyle(color: AppColors.red),
                  ),
                  const TextSpan(text: ' linhas'),
                ],
              ),
              key: ValueKey('proposal-after-$file-lines'),
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pathsBox(List<CitedPath> paths) {
    final missing = paths.where((p) => !p.exists).toList();
    if (missing.isEmpty) {
      final n = paths.length;
      return NoticeBox(
        key: const ValueKey('proposal-paths-ok'),
        text: n == 1
            ? 'Conferido no projeto. O caminho citado na proposta existe.'
            : 'Conferido no projeto. Os $n caminhos citados na proposta '
                  'existem.',
      );
    }
    return NoticeBox.warning(
      key: const ValueKey('proposal-paths-missing'),
      text:
          '${missing.length == 1 ? 'Um caminho citado não existe' : '${missing.length} caminhos citados não existem'} '
          'no projeto: ${missing.map((p) => p.path).join(', ')}.',
    );
  }

  Widget _commitBox(InstructionsCommitTarget target) {
    final enabled = target.canCommit && _result == null;
    final reason = target.disabledReason;
    return _Box(
      key: const ValueKey('proposal-commit'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: enabled ? () => setState(() => _commit = !_commit) : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    key: const ValueKey('proposal-commit-check'),
                    value: _commit && target.canCommit,
                    onChanged: enabled
                        ? (v) => setState(() => _commit = v ?? false)
                        : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Commitar ao aplicar'),
                        if (target.branch case final b?) ...[
                          const TextSpan(text: ' em '),
                          TextSpan(
                            text: b,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              color: AppColors.amberLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                    key: const ValueKey('proposal-commit-label'),
                    style: TextStyle(
                      fontSize: 13,
                      color: target.canCommit
                          ? AppColors.text
                          : AppColors.textDisabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              instructionsCommitMessage,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: target.canCommit
                    ? AppColors.textSecondary
                    : AppColors.textDisabled,
              ),
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                reason,
                key: const ValueKey('proposal-commit-disabled'),
                style: const TextStyle(fontSize: 12, color: AppColors.amber),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "3,1 KB", "820 bytes".
String proposalSize(int bytes) => bytes < 1024
    ? '$bytes bytes'
    : '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB';

/// "3,1 → 3,2 KB", "820 → 960 bytes".
String proposalSizeChange(int a, int b) {
  if (a < 1024 && b < 1024) return '$a → $b bytes';
  String kb(int x) => (x / 1024).toStringAsFixed(1).replaceAll('.', ',');
  return '${kb(a)} → ${kb(b)} KB';
}

/// The diff of a trecho: the old lines in red, the new ones in green;
/// [plain] (a refused trecho) shows only the new text, without color.
class _Diff extends StatelessWidget {
  const _Diff(this.hunk, {this.plain = false});

  final InstructionProposalHunk hunk;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    List<String> lines(String s) {
      final t = s.replaceAll(RegExp(r'\n+$'), '');
      return t.isEmpty ? const [] : t.split('\n');
    }

    Widget line(String text, {Color? bg, Color color = AppColors.text}) =>
        Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              height: 1.5,
              color: color,
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: SessionColors.terminalPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!plain)
            for (final l in lines(hunk.oldText))
              line(l, bg: SessionColors.delBg, color: const Color(0xFFF5B7AE)),
          for (final l in lines(hunk.newText))
            plain
                ? line(l, color: AppColors.textSecondary)
                : line(l, bg: SessionColors.addBg),
          if (!plain && hunk.newText.trim().isEmpty)
            line('(remove o trecho)', color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(
    this.text, {
    super.key,
    this.color = AppColors.textSecondary,
    this.border = AppColors.border,
    this.background = Colors.transparent,
    this.mono = false,
  });

  final String text;
  final Color color;
  final Color border;
  final Color background;
  final bool mono;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: border),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: color,
        fontFamily: mono ? AppFonts.mono : null,
      ),
    ),
  );
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}
