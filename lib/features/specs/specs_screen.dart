import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_provider.dart' show PromptMode;
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/code_editor/app_code_editor.dart';
import '../../ui/shell/editor_zoom.dart';
import '../../ui/widgets/zoom_control.dart';
import '../prompt/conversation_manager.dart';
import '../prompt/refine_origin.dart';
import '../prompt/spec_from_answer.dart' show DiffOp, lineDiff;
import '../project/project_config.dart';
import '../sessions/widgets/session_style.dart';
import 'spec_design.dart';
import 'prototype/prototype_files.dart';
import 'prototype/prototype_service.dart';
import 'prototype/prototype_view.dart';
import 'spec_lint.dart';
import 'spec_service.dart';
import 'widgets/spec_sync_bar.dart';
import 'widgets/spec_warnings_bar.dart';
import 'widgets/spec_actions.dart';
import 'widgets/spec_list.dart';
import 'widgets/step_trace_panel.dart';
import 'widgets/subagents_editor.dart';
import '../board/widgets/subagent_status.dart' show specSubagentsProvider;
import '../board/board_rules.dart'
    show canArchiveSpec, canDeleteSpec, specStageLabel, stepsOf;
import '../board/board_screen.dart' show specStepsProvider;
import '../board/widgets/spec_steps_panel.dart';

/// Editor modes of the mockup (Editar / Dividido / Visualizar) and the
/// prototype of the screens (SPEC-022 R1).
enum SpecViewMode {
  edit('Editar'),
  split('Dividido'),
  preview('Visualizar'),
  prototype('Protótipo');

  const SpecViewMode(this.label);

  final String label;
}

/// First message of "Refinar com IA" (Prompt screen, mode
/// [PromptMode.refine]: edits ask for approval inline — DT-35).
String refineSpecPrompt(Spec spec) =>
    'Refine a spec @${spec.path} (${spec.code}). Melhore o objetivo, '
    'deixe os requisitos verificáveis (um por linha, no formato '
    '"- R1 · texto", de preferência no estilo EARS: "Quando <gatilho>, o '
    'sistema deve <resposta>"), complete os critérios de aceite (marque o '
    'requisito de cada um, ex.: [R2], e um "verificar: <comando>" quando '
    'houver), escreva a seção "Fora do escopo" com o que a spec não faz e '
    'deixe as dúvidas sem resposta como itens de "Perguntas em aberto", em '
    'vez de transformá-las em requisitos. Edite somente esse arquivo e '
    'mantenha o frontmatter (id, status). Antes de editar, resuma o que '
    'pretende mudar.';

/// Whether the open spec has unsaved changes (asked before switching).
class SpecDirty extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) {
    if (state != v) state = v;
  }
}

final specDirtyProvider = NotifierProvider<SpecDirty, bool>(SpecDirty.new);

/// Unsaved editor text per spec id, kept when the Specs screen is left with
/// changes (the screen is rebuilt on every visit) and offered back by
/// `_load` (SPEC-021 R9).
class SpecUnsaved extends Notifier<Map<int, String>> {
  @override
  Map<int, String> build() => const {};

  void keep(int specId, String text) => state = {...state, specId: text};

  /// Removes and returns the draft of [specId].
  String? take(int specId) {
    final text = state[specId];
    if (text != null) state = {...state}..remove(specId);
    return text;
  }
}

final specUnsavedProvider = NotifierProvider<SpecUnsaved, Map<int, String>>(
  SpecUnsaved.new,
);

/// "Alterações não salvas" (R9): diff disk → [draft]; true keeps the draft,
/// false loads the file. Closing the dialog keeps the draft.
Future<bool> showSpecConflictDialog(
  BuildContext context, {
  required String code,
  required String disk,
  required String draft,
}) async {
  final lines = lineDiff(disk, draft);
  final keep = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('specs-unsaved-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        '$code tem alterações não salvas',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 640,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'O arquivo no disco mudou enquanto você tinha edições no '
              'editor. Linhas com + são suas; com −, as do disco.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView(
                  key: const ValueKey('specs-unsaved-diff'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final l in lines)
                      if (l.op != DiffOp.same)
                        Container(
                          color: l.op == DiffOp.add
                              ? SessionColors.addBg
                              : SessionColors.delBg,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '${l.op == DiffOp.add ? '+' : '−'} ${l.text}',
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 12,
                              color: l.op == DiffOp.add
                                  ? AppColors.teal
                                  : AppColors.red,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('specs-unsaved-disk'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Carregar do disco'),
        ),
        TextButton(
          key: const ValueKey('specs-unsaved-keep'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Manter minhas alterações'),
        ),
      ],
    ),
  );
  return keep ?? true;
}

/// Choice of [showApproveChecksDialog].
enum ApproveCheck { cancel, refine, assume, showWarnings, approve }

/// "Aprovar spec" with open questions (SPEC-023 R6) or structure warnings
/// (R10): the questions and the count, before the Design dialog. Null =
/// closed (same as cancel).
Future<ApproveCheck?> showApproveChecksDialog(
  BuildContext context, {
  required List<String> questions,
  required int warnings,
}) => showDialog<ApproveCheck>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (ctx) {
    void pick(ApproveCheck c) => Navigator.of(ctx).pop(c);
    final hasQuestions = questions.isNotEmpty;
    return AlertDialog(
      key: const ValueKey('spec-approve-checks-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        hasQuestions
            ? (questions.length == 1
                  ? 'A spec tem 1 pergunta em aberto'
                  : 'A spec tem ${questions.length} perguntas em aberto')
            : 'A spec tem ${SpecWarningsBar.countLabel(warnings)}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasQuestions) ...[
              const Text(
                'Responda antes de aprovar, ou aprove assumindo cada uma '
                'como premissa (elas vão para "Premissas", com a data).',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    key: const ValueKey('spec-approve-questions'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, q) in questions.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${i + 1}. $q',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (warnings > 0) ...[
              if (hasQuestions) const SizedBox(height: 8),
              Text(
                hasQuestions
                    ? 'Há também ${SpecWarningsBar.countLabel(warnings)}.'
                    : 'Os avisos não impedem a aprovação. Veja a lista ou '
                          'aprove mesmo assim.',
                key: const ValueKey('spec-approve-warnings'),
                style: const TextStyle(fontSize: 13, color: AppColors.amber),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('spec-approve-checks-cancel'),
          autofocus: true,
          onPressed: () => pick(ApproveCheck.cancel),
          child: const Text('Cancelar'),
        ),
        if (warnings > 0)
          TextButton(
            key: const ValueKey('spec-approve-show-warnings'),
            onPressed: () => pick(ApproveCheck.showWarnings),
            child: const Text('Ver avisos'),
          ),
        if (hasQuestions) ...[
          TextButton(
            key: const ValueKey('spec-approve-refine'),
            onPressed: () => pick(ApproveCheck.refine),
            child: const Text('Refinar com IA'),
          ),
          TextButton(
            key: const ValueKey('spec-approve-assume'),
            onPressed: () => pick(ApproveCheck.assume),
            child: const Text('Aprovar assumindo premissas'),
          ),
        ] else
          TextButton(
            key: const ValueKey('spec-approve-anyway'),
            onPressed: () => pick(ApproveCheck.approve),
            child: const Text('Aprovar mesmo assim'),
          ),
      ],
    );
  },
);

/// Specs screen (plano, Fase 8; docs/mockups/Specs.dc.html): list of
/// `specs/SPEC-*.md`, re_editor with modes, generated tasks + traceability.
class SpecsScreen extends ConsumerStatefulWidget {
  const SpecsScreen({super.key});

  static const editorKey = 'specs';

  @override
  ConsumerState<SpecsScreen> createState() => _SpecsScreenState();
}

class _SpecsScreenState extends ConsumerState<SpecsScreen> {
  SpecViewMode _mode = SpecViewMode.split;
  int? _syncedWorkspace;
  int? _loadedSpecId;
  CodeLineEditingController? _controller;
  String _saved = '';
  bool _missing = false;
  bool _loading = false;
  bool _busy = false;

  /// Structure warnings of the editor text (SPEC-023 R8), recomputed
  /// [_lintDelay] after the last edit.
  List<SpecWarning> _warnings = const [];
  bool _warningsOpen = false;
  Timer? _lintTimer;
  static const _lintDelay = Duration(milliseconds: 300);
  final _editorFocus = FocusNode(debugLabel: 'spec-editor');

  late final SpecUnsaved _unsaved;

  @override
  void initState() {
    super.initState();
    _unsaved = ref.read(specUnsavedProvider.notifier);
  }

  @override
  void dispose() {
    // R9: the screen is rebuilt on every visit; keep what was not saved.
    final id = _loadedSpecId, text = _controller?.text;
    if (id != null && text != null && _dirty && !_missing) {
      // Providers cannot change while the tree is being finalized.
      final unsaved = _unsaved;
      scheduleMicrotask(() {
        try {
          unsaved.keep(id, text);
        } catch (_) {
          // The container went away with the app.
        }
      });
    }
    _lintTimer?.cancel();
    _controller?.removeListener(_onText);
    _controller?.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  // --- data --------------------------------------------------------------------

  Future<void> _sync(Workspace ws) async {
    try {
      await ref.read(specServiceProvider).sync(ws);
    } catch (e) {
      _snack('Falha ao ler specs/: $e');
    }
  }

  Future<void> _load(Workspace ws, Spec spec) async {
    _loadedSpecId = spec.id;
    setState(() => _loading = true);
    String? text;
    try {
      text = await ref.read(specServiceProvider).read(ws, spec);
    } catch (e) {
      _snack('Falha ao abrir ${spec.path}: $e');
    }
    if (!mounted || _loadedSpecId != spec.id) return;
    // R9: unsaved text left in the editor differs from the file: show the
    // diff and ask (never overwritten without confirmation).
    var shown = text ?? '';
    final draft = ref.read(specUnsavedProvider.notifier).take(spec.id);
    if (text != null && draft != null && draft != text) {
      final keep = await showSpecConflictDialog(
        context,
        code: spec.code,
        disk: text,
        draft: draft,
      );
      if (!mounted || _loadedSpecId != spec.id) return;
      if (keep) shown = draft;
    }
    _controller?.removeListener(_onText);
    _controller?.dispose();
    _lastText = shown;
    _controller = CodeLineEditingController.fromText(shown)
      ..addListener(_onText);
    _lintTimer?.cancel();
    setState(() {
      _warnings = lintSpec(shown);
      _saved = text ?? '';
      _missing = text == null;
      _loading = false;
    });
    ref.read(specDirtyProvider.notifier).set(_dirty);
    if (text != null && ref.read(pendingDesignProvider) == spec.id) {
      ref.read(pendingDesignProvider.notifier).select(null);
      await _design(ws, spec);
    }
  }

  String? _lastText;

  /// Controller listener: re_editor may notify while it builds, so the
  /// rebuild (preview + unsaved indicator) is deferred to after the frame.
  void _onText() {
    final text = _controller?.text;
    if (text == _lastText) return;
    _lastText = text;
    _lintTimer?.cancel();
    _lintTimer = Timer(_lintDelay, () {
      if (!mounted) return;
      setState(() => _warnings = lintSpec(_controller?.text ?? ''));
    });
    void apply() {
      if (!mounted) return;
      ref.read(specDirtyProvider.notifier).set(_dirty);
      setState(() {});
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  bool get _dirty => _controller != null && _controller!.text != _saved;

  Future<Spec?> _save(Workspace ws, Spec spec) async {
    final c = _controller;
    if (c == null) return spec;
    try {
      final text = c.text;
      final saved = await ref.read(specServiceProvider).save(ws, spec, text);
      if (!mounted) return saved;
      setState(() {
        _saved = text;
        _missing = false;
      });
      ref.read(specDirtyProvider.notifier).set(_dirty);
      ref.invalidate(specSubagentsProvider);
      return saved;
    } catch (e) {
      _snack('Falha ao salvar: $e');
      return null;
    }
  }

  Future<void> _select(Spec spec) async {
    if (spec.id == _loadedSpecId) return;
    if (_dirty && !await _confirmDiscard()) return;
    ref.read(selectedSpecProvider.notifier).select(spec.id);
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Descartar alterações?'),
        content: const Text('A spec aberta tem alterações não salvas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // --- actions -------------------------------------------------------------------

  /// R9: the warning's line in the editor, with the cursor and the focus
  /// there (the preview alone goes to the split view first).
  void _goToLine(SpecWarning w) {
    final c = _controller;
    if (c == null) return;
    if (_mode == SpecViewMode.preview) {
      setState(() => _mode = SpecViewMode.split);
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller != c) return;
      final i = (w.line - 1).clamp(0, c.lineCount - 1);
      try {
        c.selection = CodeLineSelection.collapsed(index: i, offset: 0);
        c.makeCursorVisible();
      } catch (_) {
        // Not laid out yet: the cursor is still set.
      }
      _editorFocus.requestFocus();
    });
  }

  /// Approving with open questions or structure warnings asks first
  /// (SPEC-023 R6, R10); approving needs a `## Design` or "sem design (spec
  /// trivial)" (F7).
  Future<void> _approve(Workspace ws, Spec spec) async {
    final c = _controller;
    if (c == null || _busy) return;
    var doc = SpecDocument.parse(c.text);
    final questions = doc.openQuestions;
    final warnings = lintSpec(c.text);
    if (questions.isNotEmpty || warnings.isNotEmpty) {
      final choice = await showApproveChecksDialog(
        context,
        questions: questions,
        warnings: warnings.length,
      );
      if (choice == null || choice == ApproveCheck.cancel || !mounted) return;
      switch (choice) {
        case ApproveCheck.refine:
          return _refine(ws, spec);
        case ApproveCheck.showWarnings:
          setState(() {
            _warnings = warnings;
            _warningsOpen = true;
          });
          return;
        case ApproveCheck.assume:
          c.text = doc.withAssumptions(questions, DateTime.now());
          doc = SpecDocument.parse(c.text);
        case ApproveCheck.approve || ApproveCheck.cancel:
          break;
      }
    }
    if (doc.design == null && !doc.designWaived) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('spec-no-design-dialog'),
          backgroundColor: AppColors.panel,
          title: const Text(
            'A spec não tem Design',
            style: TextStyle(fontSize: 16),
          ),
          content: const SizedBox(
            width: 440,
            child: Text(
              'As sessões recebem o trecho do Design ligado a cada etapa. '
              'Gere o design agora ou aprove sem ele, se a spec for trivial.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              key: const ValueKey('spec-approve-no-design'),
              onPressed: () => Navigator.of(ctx).pop('trivial'),
              child: const Text('Aprovar sem design (spec trivial)'),
            ),
            TextButton(
              key: const ValueKey('spec-approve-design'),
              onPressed: () => Navigator.of(ctx).pop('design'),
              child: const Text('Gerar design'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'design') return _design(ws, spec);
      c.text = doc.withMeta(designWaived: true);
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(specServiceProvider).approve(ws, spec, c.text);
      if (!mounted) return;
      _saved = r.text;
      c.text = r.text;
      ref.read(specDirtyProvider.notifier).set(false);
      _snack('${spec.code} aprovada.');
    } catch (e) {
      _snack('Falha ao aprovar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clone(Workspace ws, Spec spec) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rows = await ref.read(specStepsRepoProvider).bySpec(spec.id);
      final done = {
        for (final s in stepsOf(spec, rows))
          if (s.isDone) s.id,
      };
      final created = await ref
          .read(specServiceProvider)
          .cloneForChange(ws, spec, doneIds: done);
      ref.read(selectedSpecProvider.notifier).select(created.id);
      _snack('${created.code} criada a partir de ${spec.code}.');
    } catch (e) {
      _snack('Falha ao clonar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Gerar design": the read-only planner writes `## Design` and
  /// `## Etapas` into the editor (saved by the user).
  Future<void> _design(Workspace ws, Spec spec) async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    _snack('Gerando o design de ${spec.code}…');
    try {
      final text = await ref.read(specDesignerProvider).generate(ws, c.text);
      if (!mounted) return;
      c.text = text;
      _snack('Design gerado. Revise e salve.');
    } catch (e) {
      _snack('Falha ao gerar o design: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refine(Workspace ws, Spec spec) async {
    if (_busy) return;
    if (_dirty && await _save(ws, spec) == null) return;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(conversationManagerProvider.notifier)
          .create(
            workspace: ws,
            text: refineSpecPrompt(spec),
            mode: PromptMode.refine,
            origin: (specCode: spec.code, source: RefineSource.specs),
          );
      ref.read(selectedConversationProvider.notifier).select(id);
      ref.read(navigationProvider.notifier).go(AppSection.prompt);
    } catch (e) {
      _snack('Falha ao abrir a conversa: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- protótipo (SPEC-022) -------------------------------------------------------

  PrototypeKey _protoKey(Workspace ws, Spec spec) =>
      (root: ws.path, code: spec.code);

  /// "Gerar telas da spec" (R2).
  Future<void> _generateScreens(Workspace ws, Spec spec) async {
    final c = _controller;
    if (c == null) return;
    _snack('Gerando as telas de ${spec.code}…');
    try {
      final r = await ref
          .read(prototypeServiceProvider)
          .generate(ws, spec, c.text);
      _snack(_outcomeText(r, 'Nenhuma tela nova.'));
    } catch (e) {
      _snack('Falha ao gerar as telas: $e');
    }
  }

  /// "Enviar" of "Pedir ao Claude" (R7).
  Future<bool> _sendRequest(Workspace ws, Spec spec, String request) async {
    final c = _controller;
    if (c == null) return false;
    final s = ref.read(prototypeScreensProvider(_protoKey(ws, spec)));
    final ui = ref.read(prototypeUiProvider(spec.id));
    final selected = [
      for (final x in s.screens)
        if (ui.selected.contains(x.file)) x,
    ];
    try {
      final run = ref
          .read(prototypeServiceProvider)
          .vary(ws, spec, c.text, selected: selected, request: request);
      final r = await run;
      _snack(_outcomeText(r, 'O agente não criou variação.'));
      return true;
    } catch (e) {
      _snack('Falha no pedido: $e');
      return false;
    }
  }

  String _outcomeText(PrototypeOutcome r, String none) => [
    r.created.isEmpty ? none : 'Criadas: ${r.created.join(', ')}.',
    if (r.restored.isNotEmpty)
      'Restauradas (o agente alterou): ${r.restored.join(', ')}.',
  ].join(' ');

  /// "Aprovar e anexar à spec" (R9): `## Protótipo` gets the line of the
  /// requirement; the status does not change.
  Future<void> _approveScreen(Workspace ws, Spec spec, MockupScreen x) async {
    final c = _controller;
    if (c == null) return;
    final path = '${mockupDir(spec.code)}/${x.file}';
    try {
      final disk = await ref.read(specServiceProvider).read(ws, spec) ?? _saved;
      final next = SpecDocument.parse(disk).withPrototype(x.requirement, path);
      await ref.read(specServiceProvider).save(ws, spec, next);
      if (!mounted) return;
      final dirty = _dirty;
      _saved = next;
      c.text = dirty
          ? SpecDocument.parse(c.text).withPrototype(x.requirement, path)
          : next;
      ref.read(specDirtyProvider.notifier).set(_dirty);
      setState(() {});
      _snack('${x.requirement} → $path anexada à spec.');
    } catch (e) {
      _snack('Falha ao aprovar a tela: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return _Shell(
        header: const _Header(path: null, title: 'Specs'),
        body: const Center(
          child: Text(
            'Selecione um workspace na barra de título.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (_syncedWorkspace != ws.id) {
      _syncedWorkspace = ws.id;
      _loadedSpecId = null;
      Future.microtask(() => _sync(ws));
    }
    final allSpecs = ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final showArchived = ref.watch(showArchivedProvider);
    final archivedCount = allSpecs
        .where((s) => s.status == SpecStatus.archived)
        .length;
    final specs = [
      for (final s in allSpecs)
        if (showArchived || s.status != SpecStatus.archived) s,
    ];
    final stepRows =
        ref.watch(specStepsProvider(ws.id)).value ?? const <SpecStep>[];
    final selectedId = ref.watch(selectedSpecProvider);
    final spec =
        specs.where((s) => s.id == selectedId).firstOrNull ?? specs.firstOrNull;
    if (spec != null && spec.id != _loadedSpecId) {
      _loadedSpecId = spec.id;
      Future.microtask(() => _load(ws, spec));
    }
    final text = _controller?.text ?? '';
    final doc = SpecDocument.parse(text);
    // Traceability of the step clicked in the steps panel (U5).
    final selectedStep = ref.watch(selectedStepProvider);
    final tracedStep = spec == null || selectedStep?.specId != spec.id
        ? null
        : stepsOf(
            spec,
            stepRows,
          ).where((st) => st.id == selectedStep!.step).firstOrNull;
    final ready = spec != null && _controller != null && !_loading;
    // Started specs are a record of what was delivered: changes go to a
    // clone ("Clonar para alterar").
    final locked = spec != null && spec.stage != SpecStage.backlog;
    final proto = _mode == SpecViewMode.prototype && spec != null;
    final protoState = proto
        ? ref.watch(prototypeScreensProvider(_protoKey(ws, spec)))
        : null;
    final protoUi = proto ? ref.watch(prototypeUiProvider(spec.id)) : null;
    final protoBusy =
        proto && ref.watch(prototypeJobsProvider).containsKey(spec.id);
    final approvedScreens = doc.prototypes;
    final compareReq = proto ? compareTarget(protoState!, protoUi!) : null;

    final content = LayoutBuilder(
      builder: (context, c) {
        final listW = c.maxWidth < 1150 ? 220.0 : 260.0;
        final sideW = c.maxWidth < 1150 ? 280.0 : 320.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listW,
              child: SpecList(
                specs: specs,
                folder: ProjectConfig.loadSync(ws.path).specsDir,
                selectedId: spec?.id,
                stepRows: stepRows,
                onSelect: _select,
                archived: archivedCount,
                showArchived: showArchived,
                onToggleArchived: () =>
                    ref.read(showArchivedProvider.notifier).toggle(),
              ),
            ),
            Expanded(
              child: _Shell(
                header: _Header(
                  path: spec?.path,
                  title: spec == null ? 'Specs' : (doc.title ?? spec.title),
                  dirty: _dirty,
                  mode: _mode,
                  onMode: (m) => setState(() => _mode = m),
                  locked: locked,
                  archiveLabel: spec?.status == SpecStatus.archived
                      ? 'Desarquivar'
                      : 'Arquivar',
                  onArchive:
                      spec != null &&
                          !_busy &&
                          (canArchiveSpec(spec) ||
                              spec.status == SpecStatus.archived)
                      ? () => archiveSpecAction(
                          context,
                          ref,
                          spec,
                          restore: spec.status == SpecStatus.archived,
                        )
                      : null,
                  onDelete: spec != null && !_busy && canDeleteSpec(spec)
                      ? () => deleteSpecAction(context, ref, spec)
                      : null,
                  onClone: ready && locked && !_busy
                      ? () => _clone(ws, spec)
                      : null,
                  onSave: ready && !locked ? () => _save(ws, spec) : null,
                  onRefine: ready && !locked && !_busy
                      ? () => _refine(ws, spec)
                      : null,
                  onDesign: ready && !locked && !_busy
                      ? () => _design(ws, spec)
                      : null,
                  onApprove:
                      ready &&
                          !locked &&
                          !_busy &&
                          doc.status != SpecStatus.approved
                      ? () => _approve(ws, spec)
                      : null,
                  approved: doc.status == SpecStatus.approved,
                  prototype: proto,
                  onCompare: proto && compareReq != null
                      ? () => ref
                            .read(prototypeUiProvider(spec.id).notifier)
                            .compare(
                              compareReq,
                              chosen: protoState!.screens
                                  .where(
                                    (x) =>
                                        x.requirement == compareReq &&
                                        protoUi!.selected.contains(x.file),
                                  )
                                  .firstOrNull
                                  ?.file,
                            )
                      : null,
                  onGenerate: proto && ready && !protoBusy
                      ? () => _generateScreens(ws, spec)
                      : null,
                ),
                body: spec == null
                    ? const Center(
                        child: Text(
                          'Crie uma spec com "Nova spec".',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : !ready
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : proto
                    ? (protoUi!.comparing != null &&
                              protoState!
                                  .variationsOf(protoUi.comparing!)
                                  .isNotEmpty
                          ? PrototypeCompare(
                              ws: ws,
                              spec: spec,
                              approved: approvedScreens,
                              onApprove: locked
                                  ? null
                                  : (x) => _approveScreen(ws, spec, x),
                              onViewSpec: () {
                                ref
                                    .read(prototypeUiProvider(spec.id).notifier)
                                    .compare(null);
                                setState(() => _mode = SpecViewMode.preview);
                              },
                            )
                          : PrototypeCanvas(ws: ws, spec: spec))
                    : CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.keyS,
                            control: true,
                          ): () =>
                              _save(ws, spec),
                        },
                        child: _EditorBody(
                          mode: _mode,
                          controller: _controller!,
                          text: text,
                          missing: _missing,
                          onSave: () => _save(ws, spec),
                          readOnly: locked,
                          focusNode: _editorFocus,
                          warnings: locked ? const [] : _warnings,
                          warningsOpen: _warningsOpen,
                          onToggleWarnings: () =>
                              setState(() => _warningsOpen = !_warningsOpen),
                          onWarning: _goToLine,
                          lockedBanner: locked
                              ? '${spec.code} já foi iniciada (${specStageLabel(spec.stage)}): '
                                    'não é editável. Use "Clonar para alterar" '
                                    'ou mova o cartão de volta ao Backlog.'
                              : null,
                        ),
                      ),
              ),
            ),
            SizedBox(
              width: sideW,
              child: spec == null
                  ? const ColoredBox(color: AppColors.panel)
                  : proto
                  ? PrototypePanel(
                      ws: ws,
                      spec: spec,
                      approved: approvedScreens,
                      onSend: ready
                          ? (request) => _sendRequest(ws, spec, request)
                          : null,
                    )
                  : Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.panel,
                        border: Border(
                          left: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: tracedStep == null ? 1 : 2,
                            child: SpecStepsPanel(specId: spec.id),
                          ),
                          if (tracedStep != null) ...[
                            const Divider(height: 24, color: AppColors.border),
                            Expanded(
                              flex: 3,
                              child: StepTracePanel(
                                spec: spec,
                                step: tracedStep,
                                text: text,
                                sessions:
                                    [
                                      for (final x
                                          in ref
                                                  .watch(
                                                    sessionsProvider(ws.id),
                                                  )
                                                  .value ??
                                              const <Session>[])
                                        if (x.specId == spec.id) x,
                                    ]..sort(
                                      (a, b) =>
                                          a.startedAt.compareTo(b.startedAt),
                                    ),
                              ),
                            ),
                          ] else if (ready) ...[
                            const Divider(height: 24, color: AppColors.border),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 280),
                              child: SingleChildScrollView(
                                child: SubagentsEditor(
                                  mainAgent: spec.agentName,
                                  workspacePath: ws.path,
                                  subagents: doc.subagents,
                                  requirements: doc.requirements,
                                  locked: locked,
                                  onChange: (list) {
                                    _controller!.text = SpecDocument.parse(
                                      _controller!.text,
                                    ).withSubagents(list);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecSyncBar(
          workspace: ws,
          specs: allSpecs,
          selected: spec,
          canVerify: !_dirty && !_busy,
          onUpdated: () {
            if (spec != null && !_dirty) _load(ws, spec);
          },
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.header, required this.body});

  final Widget header;
  final Widget body;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.background,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: body),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.path,
    required this.title,
    this.dirty = false,
    this.mode,
    this.onMode,
    this.onSave,
    this.onRefine,
    this.onDesign,
    this.onApprove,
    this.approved = false,
    this.locked = false,
    this.onClone,
    this.onArchive,
    this.onDelete,
    this.archiveLabel = 'Arquivar',
    this.prototype = false,
    this.onCompare,
    this.onGenerate,
  });

  /// Protótipo mode: "Comparar variações" / "Gerar telas da spec" replace
  /// the editor actions (SPEC-022 R1).
  final bool prototype;
  final VoidCallback? onCompare;
  final VoidCallback? onGenerate;

  final String? path;
  final String title;
  final bool dirty;
  final SpecViewMode? mode;
  final ValueChanged<SpecViewMode>? onMode;
  final VoidCallback? onSave;
  final VoidCallback? onRefine;
  final VoidCallback? onDesign;
  final VoidCallback? onApprove;
  final bool approved;
  final bool locked;
  final VoidCallback? onClone;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final String archiveLabel;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (path != null)
          Row(
            children: [
              Flexible(
                child: Text(
                  path!,
                  key: const ValueKey('spec-path'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (dirty) ...[
                const SizedBox(width: 8),
                const Text(
                  '● não salvo',
                  key: ValueKey('spec-unsaved'),
                  style: TextStyle(fontSize: 11, color: AppColors.amber),
                ),
              ],
            ],
          ),
        const SizedBox(height: 2),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
    final hasActions =
        prototype ||
        onSave != null ||
        onRefine != null ||
        onApprove != null ||
        locked ||
        onDelete != null;
    final actions = prototype
        ? <Widget>[
            Flexible(
              child: ProtoButton(
                key: const ValueKey('proto-compare'),
                label: 'Comparar variações',
                onTap: onCompare,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ProtoButton(
                key: const ValueKey('proto-generate'),
                label: 'Gerar telas da spec',
                primary: true,
                onTap: onGenerate,
              ),
            ),
          ]
        : <Widget>[
            if (locked)
              Flexible(
                child: SmallButton(
                  key: const ValueKey('spec-clone'),
                  label: 'Clonar para alterar',
                  color: AppColors.amber,
                  onTap: onClone,
                ),
              ),
            if (locked && onArchive != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: SmallButton(
                  key: const ValueKey('spec-archive'),
                  label: archiveLabel,
                  onTap: onArchive,
                ),
              ),
            ],
            if (!locked) ...[
              Flexible(
                child: SmallButton(
                  key: const ValueKey('spec-save'),
                  label: 'Salvar',
                  onTap: dirty ? onSave : null,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: SmallButton(
                  key: const ValueKey('spec-refine'),
                  label: 'Refinar com IA',
                  onTap: onRefine,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: SmallButton(
                  key: const ValueKey('spec-design'),
                  label: 'Gerar design',
                  onTap: onDesign,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: SmallButton(
                  key: const ValueKey('spec-approve'),
                  label: approved ? 'Aprovada' : 'Aprovar spec',
                  color: AppColors.teal,
                  border: SessionColors.runningToolBorder,
                  background: SessionColors.runningToolBg,
                  onTap: onApprove,
                ),
              ),
            ],
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: SmallButton(
                  key: const ValueKey('spec-delete'),
                  label: 'Excluir',
                  color: AppColors.red,
                  onTap: onDelete,
                ),
              ),
            ],
          ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Narrow (1100×700 window): actions go to a second row.
          if (c.maxWidth >= 900 || mode == null) {
            return Row(
              children: [
                Expanded(child: titleBlock),
                if (mode != null) ...[
                  const SizedBox(width: 10),
                  _ModeSwitch(mode: mode!, onMode: onMode!),
                ],
                const SizedBox(width: 10),
                const ZoomControl(editorKey: SpecsScreen.editorKey),
                if (hasActions) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 10),
                  const ZoomControl(editorKey: SpecsScreen.editorKey),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ModeSwitch(mode: mode!, onMode: onMode!, compact: true),
                  if (hasActions) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.onMode,
    this.compact = false,
  });

  /// Narrow header (1100×700): less padding per mode.
  final bool compact;
  final SpecViewMode mode;
  final ValueChanged<SpecViewMode> onMode;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final m in SpecViewMode.values)
          Semantics(
            button: true,
            selected: m == mode,
            label: 'Modo ${m.label}',
            child: InkWell(
              key: ValueKey('spec-mode-${m.name}'),
              onTap: () => onMode(m),
              borderRadius: BorderRadius.circular(4),
              focusColor: AppColors.amber.withValues(alpha: .25),
              child: Container(
                height: 26,
                padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m == mode ? AppColors.amberTint : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    m.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: m == mode
                          ? AppColors.amber
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.mode,
    required this.controller,
    required this.text,
    required this.missing,
    required this.onSave,
    this.readOnly = false,
    this.lockedBanner,
    this.focusNode,
    this.warnings = const [],
    this.warningsOpen = false,
    this.onToggleWarnings,
    this.onWarning,
  });

  final FocusNode? focusNode;

  /// Structure warnings (SPEC-023 R8): the strip below the editor, hidden
  /// when there are none.
  final List<SpecWarning> warnings;
  final bool warningsOpen;
  final VoidCallback? onToggleWarnings;
  final ValueChanged<SpecWarning>? onWarning;
  final bool readOnly;
  final String? lockedBanner;
  final SpecViewMode mode;
  final CodeLineEditingController controller;
  final String text;
  final bool missing;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final editor = AppCodeEditor(
      controller: controller,
      editorKey: SpecsScreen.editorKey,
      language: CodeLanguage.markdown,
      baseFontSize: 12,
      wordWrap: true,
      onSave: onSave,
      readOnly: readOnly,
      focusNode: focusNode,
      hint: missing ? 'Arquivo ausente — salvar recria o arquivo.' : null,
    );
    // The same zoom as the editor ("− 100% +", Ctrl -/=): reading the
    // rendered spec is where small text hurts most.
    final preview = Consumer(
      builder: (context, ref, _) => SpecPreview(
        text: text,
        scale: ref.watch(editorZoomProvider(SpecsScreen.editorKey)) / 100,
      ),
    );
    final view = switch (mode) {
      SpecViewMode.edit => editor,
      SpecViewMode.preview || SpecViewMode.prototype => preview,
      SpecViewMode.split => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: editor),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: preview),
        ],
      ),
    };
    // The strip is below the editor but comes first for Tab (SPEC-023 R14):
    // the editor keeps Tab for indenting. Same tree with or without
    // warnings, so the editor is not rebuilt (and keeps the focus).
    final body = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: view,
            ),
          ),
          if (warnings.isNotEmpty)
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: SpecWarningsBar(
                warnings: warnings,
                open: warningsOpen,
                onToggle: onToggleWarnings ?? () {},
                onSelect: onWarning ?? (_) {},
              ),
            ),
        ],
      ),
    );
    if (lockedBanner == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('spec-locked'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: AppColors.amberTint,
          child: Text(
            lockedBanner!,
            style: const TextStyle(fontSize: 12, color: AppColors.amber),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// Rendered spec (frontmatter shown as a status line, like the mockup).
class SpecPreview extends StatelessWidget {
  const SpecPreview({super.key, required this.text, this.scale = 1});

  final String text;

  /// Text scale (editor zoom / 100).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final doc = SpecDocument.parse(text);
    final theme = Theme.of(context);
    final style = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.text),
      h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      h2: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.amber,
      ),
      h3: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.amber,
      ),
      listBullet: const TextStyle(fontSize: 13, color: AppColors.text),
      code: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        color: AppColors.teal,
        backgroundColor: AppColors.surfaceRaised,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
      ),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border, width: 3)),
      ),
      a: const TextStyle(color: AppColors.amber),
      textScaler: TextScaler.linear(scale),
    );
    final status = doc.status;
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        key: const ValueKey('spec-preview'),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        children: [
          if (doc.hasFrontmatter)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                [
                  if (doc.id != null) doc.id!,
                  'Status: ${status == null ? (doc.rawStatus ?? '—') : specStatusLabel(status)}',
                ].join(' · '),
                textScaler: TextScaler.linear(scale),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          MarkdownBody(data: doc.body, styleSheet: style),
        ],
      ),
    );
  }
}
