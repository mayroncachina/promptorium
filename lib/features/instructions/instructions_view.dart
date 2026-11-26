import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/capabilities.dart';
import '../../core/providers/instructions_files.dart';
import '../../core/providers/provider_availability.dart';
import '../../core/providers/workspace_assets.dart';
import '../../core/system/worktree_launcher.dart';
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/diff_view.dart';
import '../project/project_config.dart';
import '../project/widgets/project_widgets.dart';
import '../sessions/widgets/session_style.dart';
import 'instructions_editor.dart';
import 'interview_controller.dart' show InstructionProposal;
import 'interview_view.dart';
import 'unify_dialog.dart';
import 'unify_service.dart' show canUnify;

/// How a provider row reads (R2, R5): the state pill's tone.
enum InstructionsTone { loaded, expected, warning, missing }

/// One line of the providers table (R5): what the provider reads, its state
/// and the proof.
@immutable
class InstructionsRow {
  const InstructionsRow({
    required this.provider,
    required this.reads,
    required this.state,
    required this.tone,
    required this.proof,
  });

  final String provider;
  final String reads;
  final String state;
  final InstructionsTone tone;
  final String proof;
}

/// `hoje 14:32`, `20/11 14:32`.
String instructionsWhen(DateTime t, {DateTime? now}) {
  final l = t.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(l.hour)}:${two(l.minute)}';
  return l.year == n.year && l.month == n.month && l.day == n.day
      ? 'hoje $hm'
      : '${two(l.day)}/${two(l.month)} $hm';
}

/// Whether the Codex reads the root `CLAUDE.md` (R1, R3): the capability,
/// unless the last run proved otherwise (a project without `AGENTS.md`
/// whose run did not load the `CLAUDE.md`).
bool codexReadsClaudeMd(
  InstructionsInventory inv,
  InstructionsProof? proof, {
  required bool fallback,
}) {
  if (!fallback) return false;
  if (proof == null) return true;
  final onlyClaude =
      inv.claude != null && inv.agentsState == AgentsMdState.absent;
  return !onlyClaude || proof.loaded(claudeMdName);
}

/// The two rows of the table (R2, R4, R5). [codexReason] = why the Codex
/// cannot run (unavailable, incompatible, off): the row stays and says it.
List<InstructionsRow> instructionsRows(
  InstructionsInventory inv,
  InstructionsProof? proof, {
  required bool fallback,
  String? codexReason,
}) {
  final hasClaude = inv.claude != null;
  final single = inv.agentsState == AgentsMdState.singleSource;
  final claude = InstructionsRow(
    provider: 'Claude Code',
    reads: single
        ? '$claudeMdName + $agentsMdName (import)'
        : hasClaude
        ? claudeMdName
        : '—',
    state: hasClaude ? 'carregado' : 'sem CLAUDE.md',
    tone: hasClaude ? InstructionsTone.loaded : InstructionsTone.missing,
    proof: hasClaude
        ? 'lido pelo próprio CLI em toda execução'
        : 'o projeto não tem CLAUDE.md',
  );
  final proofText = proof == null
      ? 'nenhuma execução Codex ainda'
      : 'instructionSources da ${proof.where} · ${instructionsWhen(proof.at)}';
  final agents = inv.agentsState;
  final reads = switch (agents) {
    AgentsMdState.personal => 'AGENTS.md (no lugar do CLAUDE.md)',
    AgentsMdState.singleSource => 'AGENTS.md (fonte única)',
    AgentsMdState.fresh || AgentsMdState.stale => 'AGENTS.md gerado',
    AgentsMdState.absent when !hasClaude => '—',
    AgentsMdState.absent =>
      codexReadsClaudeMd(inv, proof, fallback: fallback)
          ? 'CLAUDE.md via override'
          : 'nada (não lê o CLAUDE.md)',
  };
  InstructionsRow codex(String state, InstructionsTone tone, [String? p]) =>
      InstructionsRow(
        provider: 'Codex',
        reads: reads,
        state: state,
        tone: tone,
        proof: p ?? proofText,
      );
  if (codexReason != null) {
    return [
      claude,
      codex('indisponível', InstructionsTone.missing, codexReason),
    ];
  }
  final loadedRoot =
      proof != null &&
      (proof.loaded(agentsMdName) || proof.loaded(claudeMdName));
  return [
    claude,
    switch (agents) {
      AgentsMdState.personal => codex('duas fontes', InstructionsTone.warning),
      // SPEC-113 R1: "carregado" only with the proof of a run.
      AgentsMdState.singleSource =>
        proof != null && proof.loaded(agentsMdName)
            ? codex('carregado', InstructionsTone.loaded)
            : codex('previsto', InstructionsTone.expected),
      AgentsMdState.stale => codex('desatualizado', InstructionsTone.warning),
      AgentsMdState.fresh =>
        proof != null && proof.loaded(agentsMdName)
            ? codex('carregado', InstructionsTone.loaded)
            : codex('previsto', InstructionsTone.expected),
      AgentsMdState.absent when !hasClaude => codex(
        'sem instruções',
        InstructionsTone.missing,
      ),
      AgentsMdState.absent
          when !codexReadsClaudeMd(inv, proof, fallback: fallback) =>
        codex('não carregado', InstructionsTone.warning),
      // R2: "carregado" only with the proof of a run.
      AgentsMdState.absent =>
        loadedRoot
            ? codex(
                'carregado na ${proof.where.split(' ').first} de '
                '${instructionsWhen(proof.at).replaceFirst('hoje ', '')}',
                InstructionsTone.loaded,
              )
            : proof == null
            ? codex('previsto', InstructionsTone.expected)
            : codex('não carregado', InstructionsTone.warning),
    },
  ];
}

/// Whether the tab offers "Unificar instruções" (SPEC-113 R3): only a
/// `CLAUDE.md`, two sources, or an `AGENTS.md` generated by the app.
bool instructionsNeedUnify(InstructionsInventory inv) => canUnify(inv);

/// What the tab of Projeto › Instruções shows (SPEC-113): the editor, the
/// interview (T5) or the proposal of the interview (T6).
enum InstructionsMode { editor, interview, proposal }

class InstructionsModeController extends Notifier<InstructionsMode> {
  InstructionsModeController(this.workspaceId);

  final int workspaceId;

  @override
  InstructionsMode build() => InstructionsMode.editor;

  /// The proposal the interview handed over (R16), shown by
  /// [InstructionsMode.proposal] (T6).
  InstructionProposal? proposal;

  void show(InstructionsMode mode) => state = mode;

  /// The interview ended with [p]: the tab shows the proposal (T6).
  void showProposal(InstructionProposal p) {
    proposal = p;
    state = InstructionsMode.proposal;
  }

  /// Back to the editor (after "Pausar", or when the proposal is done).
  void backToEditor() {
    proposal = null;
    state = InstructionsMode.editor;
  }
}

/// The mode of the tab, by workspace id.
final instructionsModeProvider =
    NotifierProvider.family<InstructionsModeController, InstructionsMode, int>(
      InstructionsModeController.new,
    );

/// Asked from outside the Projeto (Ferramentas › Instruções, the palette,
/// R7): the screen opens the tab (or, in the planning flow, the dialog) and
/// clears the request.
class ProjectInstructionsRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  /// True once per request.
  bool consume() {
    if (!state) return false;
    state = false;
    return true;
  }
}

final projectInstructionsRequestProvider =
    NotifierProvider<ProjectInstructionsRequest, bool>(
      ProjectInstructionsRequest.new,
    );

/// Goes to Projeto › Instruções (R7).
void openProjectInstructions(WidgetRef ref) {
  ref.read(projectInstructionsRequestProvider.notifier).request();
  unawaited(ref.read(navigationProvider.notifier).request(AppSection.project));
}

/// Projeto › Instruções in a dialog: the planning flow has no tabs (R6),
/// like Memória and Métricas.
Future<void> showInstructionsDialog(BuildContext context) =>
    showAppDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => const Dialog(
        key: ValueKey('instructions-dialog'),
        backgroundColor: AppColors.panel,
        child: SizedBox(width: 1180, height: 700, child: InstructionsView()),
      ),
    );

/// Ferramentas › Instruções (R7, mock `7-ferramentas-atalho.png`): a
/// shortcut to Projeto › Instruções.
class InstructionsShortcut extends ConsumerWidget {
  const InstructionsShortcut({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: AppColors.background,
    child: Center(
      child: Container(
        key: const ValueKey('instructions-shortcut'),
        width: 520,
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'As instruções agora ficam no Projeto',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Veja e edite o AGENTS.md e o CLAUDE.md, confira quem lê cada um '
              'e melhore o texto com IA.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      InstructionsTag(agentsMdName, warning: true),
                      _Pill('Claude Code', InstructionsTone.loaded),
                      _Pill('Codex', InstructionsTone.loaded),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AmberButton(
                  key: const ValueKey('instructions-shortcut-open'),
                  label: 'Abrir Projeto › Instruções',
                  height: 34,
                  onTap: () => openProjectInstructions(ref),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Projeto › Instruções (SPEC-113 R6–R12, mocks `1-editar-agents.png` and
/// `2-claude-importa.png`): the files, the editor, who reads each one (the
/// proof of SPEC-104) and the size against the Codex limit. It keeps the
/// states, the proof and the plano B of the old Ferramentas › Instruções
/// (SPEC-104 R2–R5).
class InstructionsView extends ConsumerStatefulWidget {
  const InstructionsView({super.key});

  @override
  ConsumerState<InstructionsView> createState() => _InstructionsViewState();
}

class _InstructionsViewState extends ConsumerState<InstructionsView> {
  /// Selected file, relative to the root (null = the default).
  String? _selected;
  bool _busy = false;
  String? _error;
  InstructionsEditing? _editing;
  InstructionsInventory? _synced;
  bool _syncing = false;
  InstructionsEditorMode _mode = InstructionsEditorMode.text;
  InstructionsWriteResult? _undo;
  bool _saved = false;
  bool _comparing = false;
  final _focus = FocusNode(debugLabel: 'instruções');
  late final InstructionsDrafts _drafts;

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(instructionsDraftsProvider.notifier);
  }

  @override
  void dispose() {
    _release();
    _focus.dispose();
    super.dispose();
  }

  /// Keeps the unsaved edits (R8) and lets the buffers go.
  void _release() {
    final e = _editing;
    if (e == null) return;
    final keep = e.drafts;
    final paths = [for (final b in e.buffers) b.path];
    final drafts = _drafts;
    // Providers cannot change while the tree is being finalized.
    scheduleMicrotask(() {
      try {
        for (final p in paths) {
          final d = keep[p];
          d == null ? drafts.drop(p) : drafts.keep(p, d);
        }
      } catch (_) {
        // The container went away with the app.
      }
    });
    e.dispose();
    _editing = null;
    _synced = null;
  }

  void _onText() {
    if (_syncing || !mounted) return;
    setState(() {
      if (_editing?.dirty ?? false) {
        _saved = false;
        _undo = null;
      }
    });
  }

  InstructionsEditing _editingFor(String root, InstructionsInventory inv) {
    var e = _editing;
    if (e == null || e.root != root) {
      _release();
      e = _editing = InstructionsEditing(root);
      for (final b in e.buffers) {
        b.controller.addListener(_onText);
      }
    }
    if (!identical(inv, _synced)) {
      _syncing = true;
      try {
        e.sync(inv, drafts: ref.read(instructionsDraftsProvider));
      } finally {
        _syncing = false;
      }
      _synced = inv;
    }
    return e;
  }

  void _refresh(String root) =>
      ref.invalidate(instructionsInventoryProvider(root));

  Future<void> _open(String root, List<String> paths) async {
    final launcher = ref.read(worktreeLauncherProvider);
    final editor = ProjectConfig.loadSync(root).editorCommand;
    for (final p in paths) {
      try {
        await launcher.editor('$root/$p', editor: editor, cwd: root);
      } catch (e) {
        if (mounted) setState(() => _error = 'Não foi possível abrir $p: $e');
      }
    }
  }

  /// Runs [action] with the busy state and the error box.
  Future<void> _run(String root, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on InstructionsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _refresh(root);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate(String root, {required bool replace}) =>
      _run(root, () => writeGeneratedAgentsMd(root, replaceGenerated: replace));

  Future<void> _save(String root, InstructionsEditing e) =>
      _run(root, () async {
        _syncing = true;
        try {
          final result = await e.save();
          _undo = result;
          _saved = true;
          _comparing = false;
        } finally {
          _syncing = false;
        }
      });

  Future<void> _undoLast(String root, InstructionsEditing e) =>
      _run(root, () async {
        final last = _undo;
        if (last == null) return;
        final result = await undoInstructionWrite(last);
        _syncing = true;
        try {
          for (final w in result.written) {
            e.byName(w.name)?.load(w.text);
          }
        } finally {
          _syncing = false;
        }
        _undo = null;
        _saved = false;
      });

  Future<void> _restoreImport(String root, InstructionsEditing e) =>
      _run(root, () async {
        _syncing = true;
        try {
          final result = await e.restoreImport();
          if (result != null) {
            _undo = result;
            _saved = true;
          }
        } finally {
          _syncing = false;
        }
      });

  /// "Unificar instruções" (R3, R4): the dialog of the T4; the files are
  /// read again when it closes.
  VoidCallback? _unify(String root) => () async {
    await showUnifyDialog(context, ref, workspacePath: root);
    if (mounted) _refresh(root);
  };

  /// "Começar entrevista" (R13): the interview (T5) takes the tab.
  VoidCallback? _interview(Workspace ws) =>
      () => ref
          .read(instructionsModeProvider(ws.id).notifier)
          .show(InstructionsMode.interview);

  void _goToCut(InstructionsBuffer b, InstructionsCut cut) {
    setState(() {
      _selected = b.name;
      _mode = InstructionsEditorMode.text;
    });
    b.controller.selection = TextSelection.collapsed(
      offset: cut.offset.clamp(0, b.controller.text.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const ColoredBox(
        color: AppColors.background,
        child: StepEmpty(
          title: 'Nenhum workspace',
          text: 'Abra um projeto para ver as instruções que os agentes leem.',
        ),
      );
    }
    final invAsync = ref.watch(instructionsInventoryProvider(ws.path));
    final inv = invAsync.value;
    if (inv == null) {
      return ColoredBox(
        color: AppColors.background,
        child: invAsync.hasError
            ? StepEmpty(
                title: 'Erro ao ler as instruções',
                text: '${invAsync.error}',
              )
            : const SizedBox.shrink(),
      );
    }
    final mode = ref.watch(instructionsModeProvider(ws.id));
    final modes = ref.read(instructionsModeProvider(ws.id).notifier);
    switch (mode) {
      case InstructionsMode.editor:
        break;
      case InstructionsMode.interview:
        return ColoredBox(
          color: AppColors.background,
          child: InstructionsInterviewView(
            key: ValueKey('instructions-interview-${ws.id}'),
            workspace: ws,
            autoStart: true,
            onProposalReady: modes.showProposal,
            onPaused: modes.backToEditor,
          ),
        );
      case InstructionsMode.proposal:
        // TODO(SPEC-113 T6): InstructionsProposalView(workspace: ws,
        // proposal: modes.proposal!, onDone: modes.backToEditor).
        return ColoredBox(
          color: AppColors.background,
          child: StepEmpty(
            key: const ValueKey('instructions-proposal-pending'),
            title: 'Proposta pronta',
            text:
                'A tela da proposta ainda não está nesta versão. Nada foi '
                'gravado nos arquivos.',
            action: SmallButton(
              label: 'Voltar ao editor',
              onTap: modes.backToEditor,
            ),
          ),
        );
    }
    final e = _editingFor(ws.path, inv);
    final proof = ref.watch(instructionsProofProvider(ws.id)).value;
    final caps = ref.watch(codexCapabilitiesProvider);
    final fallback = caps.supports(ProviderCapability.instructionsFallback);
    final flows = ref.watch(providerFlowsProvider);
    final availability = ref.watch(providerAvailabilityProvider('codex'));
    final codexReason = flows.isOff('codex')
        ? providerOffLabel
        : switch (availability.value) {
            final a? when !a.available => 'Codex ${a.label}: ${a.message}',
            _ => null,
          };
    final reads = codexReadsClaudeMd(inv, proof, fallback: fallback);
    final rows = instructionsRows(
      inv,
      proof,
      fallback: fallback,
      codexReason: codexReason,
    );
    final single = inv.agentsState == AgentsMdState.singleSource;
    final generated =
        inv.agentsState == AgentsMdState.fresh ||
        inv.agentsState == AgentsMdState.stale;
    final rootNames = {
      if (e.agents.exists || e.agents.dirty) agentsMdName,
      if (e.claude.exists || e.claude.dirty) claudeMdName,
    };
    final nested = {for (final f in inv.nested) f.path: f};
    var selected = _selected;
    if (selected == null ||
        (!rootNames.contains(selected) && !nested.containsKey(selected))) {
      selected = single || (inv.claude == null && inv.agents != null)
          ? agentsMdName
          : rootNames.contains(claudeMdName)
          ? claudeMdName
          : rootNames.firstOrNull;
    }
    final buffer = selected == null ? null : e.byName(selected);
    // The file the Codex reads: the AGENTS.md, or the CLAUDE.md by the
    // override (R11).
    final sized = e.agents.exists || e.agents.dirty ? e.agents : e.claude;
    final Widget center;
    if (buffer != null) {
      center = InstructionsEditor(
        key: ValueKey('instructions-editor-${buffer.name}'),
        editing: e,
        buffer: buffer,
        mode: _mode,
        busy: _busy,
        saved: _saved,
        readOnly: buffer.name == agentsMdName && generated,
        comparing: _comparing,
        focusNode: _focus,
        onCompare: () => setState(() => _comparing = !_comparing),
        onMode: (m) => setState(() => _mode = m),
        onOpenExternal: () => _open(ws.path, [buffer.name]),
        onSave: () => _save(ws.path, e),
        onDiscard: () => setState(() {
          _syncing = true;
          try {
            e.discard();
          } finally {
            _syncing = false;
          }
          _comparing = false;
        }),
        onUndo: _undo == null ? null : () => _undoLast(ws.path, e),
        onChanged: () => setState(() => _comparing = false),
        onOpenAgents: () => setState(() => _selected = agentsMdName),
        onRestoreImport: () => _restoreImport(ws.path, e),
      );
    } else if (selected != null && nested[selected] != null) {
      center = _NestedFile(
        root: ws.path,
        file: nested[selected]!,
        inv: inv,
        planB: !reads,
      );
    } else {
      center = Padding(
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topLeft,
          child: NoticeBox.warning(
            key: const ValueKey('instructions-no-claude'),
            text:
                'O projeto não tem AGENTS.md nem CLAUDE.md na raiz. Escreva '
                'as instruções no AGENTS.md: o Codex o lê, e o Claude Code o '
                'lê pelo import @AGENTS.md no CLAUDE.md.',
            action: SmallButton(
              key: const ValueKey('instructions-create-agents'),
              label: 'Criar AGENTS.md',
              onTap: () => setState(() {
                e.claude.importLine = claudeImportLine;
                _selected = agentsMdName;
              }),
            ),
          ),
        ),
      );
    }
    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FileList(
            inv: inv,
            editing: e,
            selected: selected,
            planB: !reads,
            onSelect: (p) => setState(() {
              _selected = p;
              _comparing = false;
            }),
          ),
          Expanded(child: center),
          Container(
            width: 312,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.border)),
            ),
            // A column (not a lazy list): the cards are few and the tests
            // and the screen reader see all of them.
            child: SingleChildScrollView(
              key: const ValueKey('instructions-detail'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (buffer != null &&
                      buffer.isClaude &&
                      buffer.importLine != null)
                    _Card(
                      key: const ValueKey('instructions-move-card'),
                      amber: true,
                      title: 'Regra repetida?',
                      text:
                          'Uma regra que vale para os dois agentes fica no '
                          'AGENTS.md.',
                      action: SmallButton(
                        key: const ValueKey('instructions-move-selection'),
                        label: 'Mover seleção para o AGENTS.md',
                        onTap: () => setState(() {
                          _error = e.moveSelectionToAgents()
                              ? null
                              : 'Selecione no trecho só do Claude o que vale '
                                    'para os dois agentes.';
                        }),
                      ),
                    )
                  else ...[
                    InterviewResumeCard(
                      workspace: ws,
                      onContinue: () => modes.show(InstructionsMode.interview),
                    ),
                    _Card(
                      key: const ValueKey('instructions-improve'),
                      lilac: true,
                      title: 'Melhorar com IA',
                      text:
                          'A IA lê o projeto e faz perguntas em rodadas, até '
                          'fechar o que falta nas instruções. Nada é gravado '
                          'sem você aceitar.',
                      action: SmallButton(
                        key: const ValueKey('instructions-interview'),
                        label: 'Começar entrevista',
                        expand: true,
                        color: projectLilac,
                        border: projectLilacBorder,
                        onTap: _interview(ws),
                      ),
                      footer: 'Planner e assistentes · somente leitura',
                    ),
                  ],
                  if (instructionsNeedUnify(inv)) ...[
                    const SizedBox(height: 12),
                    _Card(
                      key: const ValueKey('instructions-unify-card'),
                      title: 'Unificar instruções',
                      text: switch (inv.agentsState) {
                        AgentsMdState.personal =>
                          'Duas fontes: o Codex lê o AGENTS.md e o Claude Code '
                              'o CLAUDE.md. Unifique num AGENTS.md que os dois '
                              'leem.',
                        AgentsMdState.fresh || AgentsMdState.stale =>
                          'O AGENTS.md é uma cópia gerada pelo app. Unifique '
                              'para escrever as instruções uma vez só.',
                        _ =>
                          'Só o CLAUDE.md: fora do app o Codex não o lê. '
                              'Unifique para o AGENTS.md, que os dois leem.',
                      },
                      action: SmallButton(
                        key: const ValueKey('instructions-unify'),
                        label: 'Unificar instruções',
                        onTap: _unify(ws.path),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    NoticeBox.error(text: _error!),
                  ],
                  const SizedBox(height: 18),
                  const Text('QUEM LÊ', style: sectionTitleStyle),
                  const SizedBox(height: 8),
                  for (final r in rows) ...[
                    _ReaderCard(row: r),
                    const SizedBox(height: 8),
                  ],
                  ..._state(ws.path, inv, reads: reads),
                  if (fallback &&
                      inv.claude != null &&
                      inv.agentsState == AgentsMdState.absent) ...[
                    const SizedBox(height: 12),
                    _Mechanism(proof: proof),
                  ],
                  if (sized.exists || sized.dirty) ...[
                    const SizedBox(height: 18),
                    const Text('TAMANHO', style: sectionTitleStyle),
                    const SizedBox(height: 8),
                    _SizeCard(
                      name: sized.name,
                      size: instructionsSize(sized.fullText),
                      onGoToCut: (cut) => _goToCut(sized, cut),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The AGENTS.md cases (SPEC-104 R3, R4).
  List<Widget> _state(
    String root,
    InstructionsInventory inv, {
    required bool reads,
  }) {
    const gap = SizedBox(height: 6);
    switch (inv.agentsState) {
      case AgentsMdState.personal:
        return [
          gap,
          _Notice(
            key: const ValueKey('instructions-two-sources'),
            title: 'Duas fontes.',
            text:
                'Este repositório tem um AGENTS.md escrito por você: o Codex '
                'lê o AGENTS.md primeiro, e o Claude lê o CLAUDE.md. O app '
                'não sobrescreve um arquivo que não gerou.',
            actions: [
              SmallButton(
                key: const ValueKey('instructions-open-both'),
                label: 'Abrir os dois',
                onTap: () => _open(root, [claudeMdName, agentsMdName]),
              ),
            ],
          ),
        ];
      case AgentsMdState.singleSource:
        return [
          gap,
          NoticeBox(
            key: const ValueKey('instructions-single-source'),
            text:
                'Fonte única. O AGENTS.md tem as instruções, e o CLAUDE.md o '
                'importa com @AGENTS.md: o Codex e o Claude Code leem o mesmo '
                'texto.',
          ),
        ];
      case AgentsMdState.stale:
        final current = agentsMdBody(inv.agentsText ?? '');
        return [
          gap,
          _Notice(
            key: const ValueKey('instructions-stale'),
            title: 'AGENTS.md desatualizado.',
            text:
                'O CLAUDE.md mudou depois que o AGENTS.md foi gerado'
                '${inv.claude == null ? '' : ' (${instructionsWhen(inv.claude!.modified)})'}'
                '. O Codex está lendo a versão antiga. O app nunca atualiza '
                'sozinho.',
          ),
          const SizedBox(height: 12),
          Text('DIFERENÇA ANTES DE GRAVAR', style: sectionTitleStyle),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('instructions-diff'),
            decoration: BoxDecoration(
              color: SessionColors.terminalPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DiffView(
              rows: instructionsDiffRows(current, inv.claudeText ?? ''),
              collapseSame: 3,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AmberButton(
                key: const ValueKey('instructions-update-agents'),
                label: _busy ? 'Gravando…' : 'Atualizar AGENTS.md',
                onTap: _busy ? null : () => _generate(root, replace: true),
              ),
              SmallButton(
                key: const ValueKey('instructions-open-both'),
                label: 'Abrir os dois',
                onTap: () => _open(root, [claudeMdName, agentsMdName]),
              ),
            ],
          ),
        ];
      case AgentsMdState.fresh:
        return [
          gap,
          NoticeBox(
            key: const ValueKey('instructions-fresh'),
            text:
                'AGENTS.md gerado · em dia. É uma cópia do CLAUDE.md com aviso '
                'no topo: edite sempre o CLAUDE.md.',
          ),
        ];
      case AgentsMdState.absent:
        if (reads || inv.claude == null) return const [];
        // Plano B (SPEC-104 R3): the Codex does not read the CLAUDE.md.
        return [
          gap,
          _Notice(
            key: const ValueKey('instructions-plan-b'),
            title: 'O Codex não lê o CLAUDE.md nesta versão.',
            text:
                'Gere um AGENTS.md: uma cópia do CLAUDE.md com aviso no topo '
                'e o hash da origem. O app nunca o atualiza sozinho.',
            actions: [
              AmberButton(
                key: const ValueKey('instructions-generate-agents'),
                label: _busy ? 'Gerando…' : 'Gerar AGENTS.md',
                onTap: _busy ? null : () => _generate(root, replace: false),
              ),
            ],
          ),
        ];
    }
  }
}

/// A card of the right column (Melhorar com IA, Regra repetida?,
/// Unificar).
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.title,
    required this.text,
    this.action,
    this.footer,
    this.amber = false,
    this.lilac = false,
  });

  final String title;
  final String text;
  final Widget? action;
  final String? footer;
  final bool amber;
  final bool lilac;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = amber
        ? (
            SessionColors.approvalBg,
            SessionColors.approvalBorder,
            AppColors.amberLight,
          )
        : lilac
        ? (projectLilacBg, projectLilacBorder, AppColors.text)
        : (AppColors.panel, AppColors.border, AppColors.text);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: amber ? AppColors.amber : fg,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: amber ? fg : AppColors.textSecondary,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One provider in "Quem lê" (R10): what it reads, the state ("carregado"
/// only with the proof) and the proof.
class _ReaderCard extends StatelessWidget {
  const _ReaderCard({required this.row});

  final InstructionsRow row;

  @override
  Widget build(BuildContext context) {
    final color = row.provider == 'Codex'
        ? AppColors.providerCodex
        : AppColors.providerClaude;
    return Container(
      key: ValueKey('instructions-row-${row.provider}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: color.withValues(alpha: 0.7)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  row.provider,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
              const Spacer(),
              Flexible(child: _Pill(row.state, row.tone)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row.reads,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            row.proof,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// R11: bytes and lines against the 32 KiB the Codex reads, a warning from
/// 80% and where the cut falls past the limit.
class _SizeCard extends StatelessWidget {
  const _SizeCard({
    required this.name,
    required this.size,
    required this.onGoToCut,
  });

  final String name;
  final InstructionsSize size;
  final ValueChanged<InstructionsCut> onGoToCut;

  @override
  Widget build(BuildContext context) {
    final color = switch (size.level) {
      InstructionsSizeLevel.ok => AppColors.teal,
      InstructionsSizeLevel.warning => AppColors.amber,
      InstructionsSizeLevel.over => AppColors.red,
    };
    final cut = size.cut;
    return Container(
      key: const ValueKey('instructions-size'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_size(size.bytes)} · ${size.lines} linhas',
                  key: const ValueKey('instructions-size-label'),
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ),
              Text(
                'limite do Codex: ${size.limit ~/ 1024} KB',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: size.fraction.clamp(0.0, 1.0),
              minHeight: 5,
              color: color,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 8),
          switch (size.level) {
            InstructionsSizeLevel.ok => Text(
              '$name · curto é melhor: deixe os detalhes em docs/.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            InstructionsSizeLevel.warning => Text(
              'Perto do limite (${(size.fraction * 100).floor()}%): o Codex lê '
              'só os primeiros 32 KB do $name.',
              key: const ValueKey('instructions-size-warning'),
              style: const TextStyle(fontSize: 12, color: AppColors.amber),
            ),
            InstructionsSizeLevel.over => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Passou do limite: o Codex corta o $name na linha '
                  '${cut!.line}, coluna ${cut.column}'
                  '${cut.midLine ? ', no meio da linha' : ''}, sem avisar. '
                  'O que vem depois não chega a ele.',
                  key: const ValueKey('instructions-size-cut'),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.red,
                  ),
                ),
                const SizedBox(height: 8),
                SmallButton(
                  key: const ValueKey('instructions-go-to-cut'),
                  label: 'Ir para o corte',
                  onTap: () => onGoToCut(cut),
                ),
              ],
            ),
          },
        ],
      ),
    );
  }
}

/// A file of a subfolder (R12, SPEC-104 P3): read only, no write action.
class _NestedFile extends StatelessWidget {
  const _NestedFile({
    required this.root,
    required this.file,
    required this.inv,
    required this.planB,
  });

  final String root;
  final InstructionFile file;
  final InstructionsInventory inv;
  final bool planB;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('instructions-nested'),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            file.path,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const InstructionsTag('só leitura'),
          if (planB && file.name == claudeMdName)
            const _Pill('Só Claude Code', InstructionsTone.expected),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Arquivos de subpastas ficam só leitura no app · '
        'editado ${instructionsWhen(file.modified)} · ${file.lines} linhas',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 12),
      _Preview(root: root, path: file.path, inv: inv),
    ],
  );
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.inv,
    required this.editing,
    required this.selected,
    required this.planB,
    required this.onSelect,
  });

  final InstructionsInventory inv;
  final InstructionsEditing editing;
  final String? selected;
  final bool planB;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget item(String path, String sub, {Widget? tag}) {
      final on = path == selected;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? SessionColors.selectedBg : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: on ? SessionColors.selectedBorder : Colors.transparent,
            ),
          ),
          child: InkWell(
            key: ValueKey('instructions-file-$path'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          sub,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?tag,
                ],
              ),
            ),
          ),
        ),
      );
    }

    String unsaved(InstructionsBuffer b) => b.dirty ? ' · não salvo' : '';
    final state = inv.agentsState;
    final single = state == AgentsMdState.singleSource;
    final a = editing.agents, c = editing.claude;
    final agentsSub = switch (state) {
      AgentsMdState.personal => 'raiz · escrito por você',
      AgentsMdState.fresh => 'raiz · gerado · em dia',
      AgentsMdState.stale => 'raiz · gerado · desatualizado',
      _ => 'raiz',
    };
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text('ARQUIVOS', style: sectionTitleStyle),
                ),
                if (a.exists || a.dirty)
                  item(
                    agentsMdName,
                    '$agentsSub'
                    '${inv.agents == null ? '' : ' · ${_size(inv.agents!.size)}'}'
                    '${unsaved(a)}',
                    tag: single || (state == AgentsMdState.absent && a.dirty)
                        ? const InstructionsTag('fonte', warning: true)
                        : state == AgentsMdState.stale
                        ? const _Pill('desatualizado', InstructionsTone.warning)
                        : state == AgentsMdState.personal
                        ? const InstructionsTag('duas fontes', warning: true)
                        : null,
                  ),
                if (c.exists || c.dirty)
                  item(
                    claudeMdName,
                    'raiz'
                    '${inv.claude == null ? '' : ' · ${_size(inv.claude!.size)}'}'
                    '${unsaved(c)}',
                    tag: c.importLine != null
                        ? const InstructionsTag('importa', lilac: true)
                        : state == AgentsMdState.personal
                        ? null
                        : const InstructionsTag('fonte', warning: true),
                  ),
                if (!a.exists && !a.dirty && !c.exists && !c.dirty)
                  const _Muted('Nenhum arquivo na raiz.'),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text(
                    'SUBPASTAS · SÓ LEITURA',
                    style: sectionTitleStyle,
                  ),
                ),
                if (inv.nested.isEmpty) const _Muted('Nenhum.'),
                for (final f in inv.nested)
                  item(
                    f.path,
                    _size(f.size),
                    // P3: in plano B only the root gets an AGENTS.md.
                    tag: planB && f.name == claudeMdName
                        ? const _Pill(
                            'Só Claude Code',
                            InstructionsTone.expected,
                          )
                        : null,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Text(
              single
                  ? 'Escreva uma vez no AGENTS.md. O CLAUDE.md só o importa.'
                  : 'O CLAUDE.md é a fonte. O app não grava nada em ~/.codex '
                        'nem altera o repositório para o Codex lê-lo.',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _size(int bytes) => bytes < 1024
    ? '$bytes B'
    : '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB';

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.tone);

  final String text;
  final InstructionsTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = switch (tone) {
      InstructionsTone.loaded => (
        AppColors.teal,
        SessionColors.runningToolBg,
        SessionColors.runningToolBorder,
      ),
      InstructionsTone.warning => (
        AppColors.amber,
        SessionColors.approvalBg,
        SessionColors.approvalBorder,
      ),
      InstructionsTone.expected => (
        AppColors.textSecondary,
        AppColors.surfaceRaised,
        AppColors.border,
      ),
      InstructionsTone.missing => (
        AppColors.textMuted,
        AppColors.surfaceRaised,
        AppColors.border,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.title,
    required this.text,
    this.actions = const [],
  });

  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: SessionColors.approvalBg,
      border: Border.all(color: SessionColors.approvalBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$title ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: text),
            ],
          ),
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: AppColors.amberLight,
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    ),
  );
}

class _Mechanism extends StatelessWidget {
  const _Mechanism({required this.proof});

  final InstructionsProof? proof;

  @override
  Widget build(BuildContext context) {
    final p = proof;
    Widget line(String k, String v, {bool mono = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontFamily: mono ? AppFonts.mono : null,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('instructions-mechanism'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'COMO O CODEX RECEBE O CLAUDE.MD',
            style: sectionTitleStyle,
          ),
          const SizedBox(height: 10),
          line(
            'Mecanismo',
            '-c project_doc_fallback_filenames=["CLAUDE.md"]',
            mono: true,
          ),
          line('Grava em', 'nada · vale só para cada execução do app'),
          line(
            'Última conferência',
            p == null
                ? 'nenhuma execução Codex ainda'
                : '${instructionsWhen(p.at)} · '
                      '${p.sources.isEmpty ? 'nenhum arquivo' : p.sources.join(', ')}',
            mono: p != null,
          ),
          line(
            'Sem execução ainda',
            'a linha mostra “previsto”, nunca “carregado”',
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.root, required this.path, required this.inv});

  final String root;
  final String path;
  final InstructionsInventory inv;

  String _text() {
    if (path == claudeMdName) return inv.claudeText ?? '';
    if (path == agentsMdName) return inv.agentsText ?? '';
    try {
      return File('$root/$path').readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _text().split('\n');
    final shown = lines.length > 200 ? lines.sublist(0, 200) : lines;
    return Container(
      key: const ValueKey('instructions-preview'),
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SessionColors.terminalPanel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        [
          ...shown,
          if (lines.length > shown.length)
            '… (${lines.length - shown.length} linhas)',
        ].join('\n'),
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12,
          height: 1.6,
          color: AppColors.text,
        ),
      ),
    );
  }
}
