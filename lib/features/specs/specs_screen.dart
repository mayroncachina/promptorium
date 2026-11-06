import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_provider.dart' show PromptMode;
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/app_toast.dart';
import '../../ui/widgets/code_editor/app_code_editor.dart';
import '../../ui/shell/editor_zoom.dart';
import '../../ui/widgets/zoom_control.dart';
import '../prompt/conversation_manager.dart';
import '../prompt/refine_origin.dart';
import '../prompt/spec_from_answer.dart' show DiffOp, lineDiff;
import '../project/project_config.dart';
import 'spec_action.dart';
import 'spec_answers.dart';
import 'spec_design.dart';
import '../project/spec_auto_planner.dart';
import 'prototype/prototype_delete.dart';
import 'prototype/prototype_files.dart';
import 'prototype/prototype_service.dart';
import 'prototype/prototype_view.dart';
import 'spec_lint.dart';
import 'spec_service.dart';
import 'widgets/spec_sync_bar.dart';
import 'widgets/spec_warnings_bar.dart';
import 'widgets/spec_actions.dart';
import 'widgets/spec_action_banner.dart';
import 'widgets/spec_header.dart';
import 'widgets/spec_questions_panel.dart';
import 'widgets/spec_skeleton.dart';

export 'widgets/spec_header.dart' show SpecViewMode;
import 'widgets/spec_list.dart';
import 'widgets/step_trace_panel.dart';
import 'widgets/subagents_editor.dart';
import '../board/widgets/subagent_status.dart' show specSubagentsProvider;
import '../board/board_rules.dart'
    show canArchiveSpec, canDeleteSpec, specStageLabel, stepsOf;
import '../board/board_screen.dart' show specStepsProvider;
import '../board/widgets/spec_steps_panel.dart';

/// First message of "Refinar com IA" (Prompt screen, mode
/// [PromptMode.refine]: edits ask for approval inline — DT-35).
String refineSpecPrompt(Spec spec) =>
    'Refine a spec @${spec.path} (${spec.code}). $specRefineRules '
    'Edite somente esse arquivo e '
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
  final keep = await showAppDialog<bool>(
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

/// "Sair da `código` durante a geração?" (SPEC-025 R7): true = cancel the
/// generation and open [destination]; "Continuar aqui", Esc or closing the
/// dialog stay (false).
Future<bool> confirmLeaveDuringAction(
  BuildContext context, {
  required String code,
  required SpecActionKind kind,
  required String destination,
  bool toSpec = true,
}) async {
  final leave = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('spec-leave-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        'Sair da $code durante a geração?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 400,
        child: Text(
          '${kind.stillRunning} Se você '
          '${toSpec ? 'abrir a $destination' : 'abrir $destination'} agora, a '
          'geração é cancelada e a $code não muda.',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      actions: [
        OutlinedButton(
          key: const ValueKey('spec-leave-cancel-action'),
          onPressed: () => Navigator.of(ctx).pop(true),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
          ),
          child: Text('Cancelar geração e abrir $destination'),
        ),
        FilledButton(
          key: const ValueKey('spec-leave-stay'),
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: AppColors.onAmber,
          ),
          child: const Text(
            'Continuar aqui',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return leave ?? false;
}

/// Failure of an action shown above the editor (SPEC-025 R8).
typedef SpecActionFailure = ({SpecActionKind kind, int specId, String cause});

/// Choice of [showApproveChecksDialog]. `answer` = "Responder perguntas"
/// (SPEC-028 R4, in place of "Refinar com IA").
enum ApproveCheck { cancel, answer, assume, showWarnings, approve }

/// "R7 sem critério de aceite; R8 sem "deve"" (SPEC-028 R4): the warnings
/// by name, the first [max] of them.
String namedWarnings(List<SpecWarning> warnings, {int max = 3}) {
  final names = [for (final w in warnings.take(max)) w.message];
  final rest = warnings.length - names.length;
  return [...names, if (rest > 0) 'e mais $rest'].join('; ');
}

/// "Aprovar spec" with open questions (SPEC-023 R6, SPEC-028 R4) or
/// structure warnings (SPEC-023 R10): the questions with their suggestions
/// and the warnings by name, before the Plano dialog. Null = closed (same
/// as cancel).
Future<ApproveCheck?> showApproveChecksDialog(
  BuildContext context, {
  required String code,
  required List<OpenQuestion> questions,
  required List<SpecWarning> warnings,
}) => showAppDialog<ApproveCheck>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (ctx) {
    void pick(ApproveCheck c) => Navigator.of(ctx).pop(c);
    final hasQuestions = questions.isNotEmpty;
    final count = SpecWarningsBar.countLabel(warnings.length);
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: AppColors.text,
      side: const BorderSide(color: AppColors.border),
    );
    return AlertDialog(
      key: const ValueKey('spec-approve-checks-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        hasQuestions
            ? (questions.length == 1
                  ? 'A $code tem 1 pergunta em aberto'
                  : 'A $code tem ${questions.length} perguntas em aberto')
            : 'A spec tem $count',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasQuestions) ...[
              const Text(
                'Responda numa sessão guiada antes de aprovar, ou aprove '
                'assumindo as sugestões. Elas vão para "Premissas", com a '
                'data.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      key: const ValueKey('spec-approve-questions'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, q) in questions.indexed) ...[
                          if (i > 0)
                            const Divider(height: 1, color: AppColors.border),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${q.id} ',
                                        style: const TextStyle(
                                          color: AppColors.amber,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextSpan(text: q.text),
                                    ],
                                  ),
                                  key: ValueKey(
                                    'spec-approve-question-${q.id}',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: AppColors.text,
                                  ),
                                ),
                                if (q.suggestion != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 28,
                                      top: 3,
                                    ),
                                    child: Text(
                                      'Sugestão: ${q.suggestion}',
                                      key: ValueKey(
                                        'spec-approve-suggestion-${q.id}',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline,
                      size: 15,
                      color: AppColors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasQuestions
                          ? 'Há também $count: ${namedWarnings(warnings)}.'
                          : '${namedWarnings(warnings)}. Os avisos não '
                                'impedem a aprovação. Veja a lista ou aprove '
                                'mesmo assim.',
                      key: const ValueKey('spec-approve-warnings'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        // Esc closes the dialog (null = cancel).
        OutlinedButton(
          key: const ValueKey('spec-approve-checks-cancel'),
          autofocus: true,
          style: secondary,
          onPressed: () => pick(ApproveCheck.cancel),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cancelar'),
              SizedBox(width: 8),
              ExcludeSemantics(child: Kbd('Esc')),
            ],
          ),
        ),
        if (!hasQuestions) ...[
          OutlinedButton(
            key: const ValueKey('spec-approve-show-warnings'),
            style: secondary,
            onPressed: () => pick(ApproveCheck.showWarnings),
            child: const Text('Ver avisos'),
          ),
          OutlinedButton(
            key: const ValueKey('spec-approve-anyway'),
            style: secondary,
            onPressed: () => pick(ApproveCheck.approve),
            child: const Text('Aprovar mesmo assim'),
          ),
        ] else ...[
          OutlinedButton(
            key: const ValueKey('spec-approve-assume'),
            style: secondary,
            onPressed: () => pick(ApproveCheck.assume),
            child: const Text('Aprovar com as sugestões'),
          ),
          FilledButton.icon(
            key: const ValueKey('spec-approve-answer'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.onAmber,
            ),
            onPressed: () => pick(ApproveCheck.answer),
            icon: const Icon(Icons.help_outline, size: 16),
            label: const Text(
              'Responder perguntas',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
  bool _loading = false;

  /// The spec whose text is in [_controller]. It differs from [_loadedSpecId]
  /// while another spec is on the way: that text is never saved, edited or
  /// kept as a draft of the spec being opened (SPEC-034 R10).
  int? _docSpecId;

  /// Bumped by each [_load]: a newer one cancels the wait of the older.
  int _loadTurn = 0;

  /// R10: how long the current document stays before the skeleton comes.
  static const _skeletonDelay = Duration(milliseconds: 300);
  Timer? _skeletonTimer;
  bool _skeletonDue = false;

  /// Why the spec did not open (R10), shown in the place of the document.
  ({int specId, String message})? _openError;

  /// Changes when a text enters, which fades it in (R10).
  int _fadeTurn = 0;

  /// The last document shown: during the wait it stays as it was, with
  /// [hold] true, so nothing in it acts on the spec being opened (R10).
  Widget Function({required bool hold})? _shownBody;

  /// Last failed action (SPEC-025 R8), shown while its spec is open.
  SpecActionFailure? _failure;
  final _cancelFocus = FocusNode(debugLabel: 'spec-action-cancel');
  late final SpecActionController _actions;
  late final NavigationController _nav;

  /// Structure warnings of the editor text (SPEC-023 R8), recomputed
  /// [_lintDelay] after the last edit.
  List<SpecWarning> _warnings = const [];
  bool _warningsOpen = false;
  Timer? _lintTimer;
  static const _lintDelay = Duration(milliseconds: 300);
  final _editorFocus = FocusNode(debugLabel: 'spec-editor');

  /// "Responder perguntas" open beside the editor (SPEC-028 R6).
  bool _questionsOpen = false;

  /// First-level suggestions counted as questions, marked in the editor
  /// (SPEC-028 R2), by 0-based line.
  final _questionMarks = ValueNotifier<Map<int, Color>>(const {});

  late final SpecUnsaved _unsaved;
  late final PrototypeUndoController _undo;

  @override
  void initState() {
    super.initState();
    _unsaved = ref.read(specUnsavedProvider.notifier);
    _undo = ref.read(prototypeUndoProvider.notifier);
    _actions = ref.read(specActionProvider.notifier);
    _nav = ref.read(navigationProvider.notifier);
    _nav.leaveGuard = _guardLeave;
  }

  @override
  void dispose() {
    // R9: the screen is rebuilt on every visit; keep what was not saved.
    final id = _loadedSpecId, text = _controller?.text;
    if (id != null && text != null && _dirty) {
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
    if (_nav.leaveGuard == _guardLeave) _nav.leaveGuard = null;
    // SPEC-027 R6: leaving the screen makes a deletion final.
    _undo.discardLater();
    // Leaving the screen stops a long action: its result would have nowhere
    // to go (R7).
    final a = _actions.current;
    if (a != null && a.kind.long && !a.cancel.isCompleted) a.cancel.complete();
    _lintTimer?.cancel();
    _skeletonTimer?.cancel();
    _controller?.removeListener(_onText);
    _controller?.dispose();
    _editorFocus.dispose();
    _cancelFocus.dispose();
    _questionMarks.dispose();
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
    // SPEC-027 R6: another spec makes the deletion final.
    if (_loadedSpecId != spec.id) _undo.discardLater();
    _loadedSpecId = spec.id;
    final turn = ++_loadTurn;
    bool stale() => turn != _loadTurn || _loadedSpecId != spec.id;
    // A skeleton already on screen stays: going back to the old document
    // would blink.
    if (!_skeletonDue) {
      _skeletonTimer?.cancel();
      _skeletonTimer = Timer(_skeletonDelay, () {
        if (mounted) setState(() => _skeletonDue = true);
      });
    }
    setState(() {
      _loading = true;
      _openError = null;
    });
    ref.read(specDirtyProvider.notifier).set(_dirty);
    String? text;
    String? failure;
    try {
      text = await ref.read(specServiceProvider).read(ws, spec);
      if (text == null) failure = 'o arquivo não está mais na pasta de specs.';
    } catch (e) {
      failure = switch (e) {
        FileSystemException(:final osError?) => osError.message,
        _ => '$e',
      };
    }
    if (!mounted || stale()) return;
    if (failure != null) {
      _skeletonTimer?.cancel();
      setState(() {
        _openError = (
          specId: spec.id,
          message: 'Não foi possível abrir a ${spec.code}: $failure',
        );
        _shownBody = null;
        _questionsOpen = false;
        _loading = false;
        _skeletonDue = false;
        _fadeTurn++;
      });
      return;
    }
    // R9: unsaved text left in the editor differs from the file: show the
    // diff and ask (never overwritten without confirmation).
    var shown = text!;
    final draft = ref.read(specUnsavedProvider.notifier).take(spec.id);
    if (draft != null && draft != text) {
      final keep = await showSpecConflictDialog(
        context,
        code: spec.code,
        disk: text,
        draft: draft,
      );
      if (!mounted || stale()) return;
      if (keep) shown = draft;
    }
    // The editor on screen still uses the old controller until the next
    // frame takes it away.
    final old = _controller?..removeListener(_onText);
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _lastText = shown;
    _controller = CodeLineEditingController.fromText(shown)
      ..addListener(_onText);
    _lintTimer?.cancel();
    _skeletonTimer?.cancel();
    _setWarnings(shown);
    setState(() {
      // A reload of the same text, with nothing covering it, just stays.
      if (_docSpecId != spec.id || _skeletonDue) _fadeTurn++;
      _docSpecId = spec.id;
      _questionsOpen = false;
      _saved = text!;
      _loading = false;
      _skeletonDue = false;
    });
    ref.read(specDirtyProvider.notifier).set(_dirty);
    if (ref.read(pendingDesignProvider) == spec.id) {
      ref.read(pendingDesignProvider.notifier).select(null);
      await _design(ws, spec);
    }
  }

  String? _lastText;

  /// Structure warnings of [text] and the editor marks of the suggestions
  /// counted as questions (SPEC-028 R2).
  void _setWarnings(String text) {
    _warnings = lintSpec(text);
    final scan = SpecDocument.parse(text).openQuestionsScan;
    _questionMarks.value = {
      for (final l in scan.suggestionLines) l - 1: AppColors.amber,
    };
  }

  /// Controller listener: re_editor may notify while it builds, so the
  /// rebuild (preview + unsaved indicator) is deferred to after the frame.
  void _onText() {
    final text = _controller?.text;
    if (text == _lastText) return;
    _lastText = text;
    _lintTimer?.cancel();
    _lintTimer = Timer(_lintDelay, () {
      if (!mounted) return;
      setState(() => _setWarnings(_controller?.text ?? ''));
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

  bool get _dirty =>
      _controller != null &&
      _docSpecId == _loadedSpecId &&
      _controller!.text != _saved;

  Future<Spec?> _save(Workspace ws, Spec spec) async {
    final c = _controller;
    if (c == null) return spec;
    // SPEC-034 R10: during a wait the text on screen is the old one.
    if (_loading || _docSpecId != spec.id || _loadedSpecId != spec.id) {
      return null;
    }
    // R1: nothing is written while an action holds the spec.
    if (_held(spec.id)) return null;
    try {
      // Saved by hand, the text is the person's: the second round of the
      // automatic plan no longer touches it (SPEC-037 R13, D7).
      final doc = SpecDocument.parse(c.text);
      if (doc.autoPlanned) c.text = doc.withAutoPlan(false);
      final text = c.text;
      final saved = await ref.read(specServiceProvider).save(ws, spec, text);
      if (!mounted || _docSpecId != spec.id) return saved;
      setState(() => _saved = text);
      ref.read(specDirtyProvider.notifier).set(_dirty);
      ref.invalidate(specSubagentsProvider);
      return saved;
    } catch (e) {
      _snack('Falha ao salvar: $e');
      return null;
    }
  }

  /// The agent wrote the open spec (SPEC-037 R10): the editor shows the new
  /// text; what was left unsaved goes through the usual conflict dialog.
  Future<void> _reloadPlanned(Workspace ws, Spec spec) async {
    final text = _controller?.text;
    if (text != null && _dirty) _unsaved.keep(spec.id, text);
    await _load(ws, spec);
  }

  Future<void> _select(Spec spec) async {
    if (spec.id == _loadedSpecId) return;
    // R7: a generation of the open spec asks first.
    final a = _actions.current;
    if (a != null && a.kind.long && a.specId == _loadedSpecId) {
      final leave = await confirmLeaveDuringAction(
        context,
        code: a.specCode,
        kind: a.kind,
        destination: spec.code,
      );
      if (!leave || !mounted) return;
      _actions.cancel();
    }
    if (_dirty && !await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() => _failure = null);
    ref.read(selectedSpecProvider.notifier).select(spec.id);
  }

  /// Leaving the Specs screen during a generation (R7).
  Future<bool> _guardLeave(AppSection to) async {
    final a = _actions.current;
    if (!mounted || a == null || !a.kind.long) return true;
    final leave = await confirmLeaveDuringAction(
      context,
      code: a.specCode,
      kind: a.kind,
      destination: to.navLabel,
      toSpec: false,
    );
    if (leave) _actions.cancel();
    return leave;
  }

  /// An action is running on [specId] (R1).
  bool _held(int specId) =>
      _actions.current?.specId == specId ||
      ref.read(specAutoPlannerProvider).lockOf(specId) != null;

  /// Runs [body] as [kind] on [spec] (R1–R8): the spec is held until it
  /// ends; a cancel shows the R5 notice, a failure the R8 alert.
  Future<void> _runAction(
    SpecActionKind kind,
    Spec spec,
    Future<void> Function(SpecActionState a) body,
  ) async {
    final a = _actions.start(
      kind,
      specId: spec.id,
      specCode: spec.code,
      fromKeyboard:
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
    );
    if (a == null) return;
    if (mounted) setState(() => _failure = null);
    if (kind.long && a.fromKeyboard) {
      // R11: from the keyboard, the focus goes to "Cancelar geração".
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cancelFocus.context != null) {
          _cancelFocus.requestFocus();
        }
      });
    }
    try {
      await body(a);
    } on SpecActionCancelled {
      _snack('Geração cancelada. A spec não foi alterada.');
    } catch (e) {
      if (a.cancelled) {
        _snack('Geração cancelada. A spec não foi alterada.');
      } else {
        debugPrint('${kind.name} de ${spec.code}: $e');
        if (mounted) {
          setState(
            () =>
                _failure = (kind: kind, specId: spec.id, cause: errorCause(e)),
          );
        }
      }
    } finally {
      _actions.finish(a);
    }
  }

  /// [run], or [SpecActionCancelled] as soon as [a] is cancelled (R5: the
  /// spec is released at once, even if the agent takes a moment to stop).
  Future<T> _orCancel<T>(SpecActionState a, Future<T> run) => Future.any([
    run,
    a.cancelledFuture.then<T>((_) => throw const SpecActionCancelled()),
  ]);

  /// "Tentar de novo" (R8): the same action with the current text.
  void _retry(Workspace ws, Spec spec, SpecActionKind kind) {
    setState(() => _failure = null);
    unawaited(switch (kind) {
      SpecActionKind.design => _design(ws, spec),
      SpecActionKind.approve => _approve(ws, spec),
      SpecActionKind.clone => _clone(ws, spec),
      SpecActionKind.refine => _refine(ws, spec),
      SpecActionKind.screens => _generateScreens(ws, spec),
      SpecActionKind.answers => Future.sync(_openQuestions),
    });
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showAppDialog<bool>(
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
  /// (SPEC-023 R6, R10); approving needs a `## Plano` or "sem plano (spec
  /// trivial)" (F7).
  Future<void> _approve(Workspace ws, Spec spec) async {
    final c = _controller;
    if (c == null || _actions.current != null) return;
    var doc = SpecDocument.parse(c.text);
    final questions = doc.openQuestions;
    // The format notice has its own strip (SPEC-028 R3).
    final warnings = [
      for (final w in lintSpec(c.text))
        if (w.kind != SpecWarningKind.openQuestionsFormat) w,
    ];
    if (questions.isNotEmpty || warnings.isNotEmpty) {
      final choice = await showApproveChecksDialog(
        context,
        code: spec.code,
        questions: questions,
        warnings: warnings,
      );
      if (choice == null || choice == ApproveCheck.cancel || !mounted) return;
      switch (choice) {
        case ApproveCheck.answer:
          return _openQuestions();
        case ApproveCheck.showWarnings:
          setState(() {
            _setWarnings(c.text);
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
      final choice = await showAppDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('spec-no-design-dialog'),
          backgroundColor: AppColors.panel,
          title: const Text(
            'A spec não tem Plano',
            style: TextStyle(fontSize: 16),
          ),
          content: const SizedBox(
            width: 440,
            child: Text(
              'As sessões recebem o trecho do Plano ligado a cada etapa. '
              'Planeje agora ou aprove sem ele, se a spec for trivial.',
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
              child: const Text('Aprovar sem plano (spec trivial)'),
            ),
            TextButton(
              key: const ValueKey('spec-approve-design'),
              onPressed: () => Navigator.of(ctx).pop('design'),
              child: const Text('Planejar'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'design') return _design(ws, spec);
      c.text = doc.withMeta(designWaived: true);
    }
    if (!mounted || _controller != c) return;
    final text = c.text;
    await _runAction(SpecActionKind.approve, spec, (a) async {
      final r = await ref.read(specServiceProvider).approve(ws, spec, text);
      // R7: never applied to another spec.
      if (!mounted || _loadedSpecId != spec.id || _controller == null) return;
      _saved = r.text;
      _controller!.text = r.text;
      ref.read(specDirtyProvider.notifier).set(false);
      _snack('${spec.code} aprovada.');
    });
  }

  Future<void> _clone(Workspace ws, Spec spec) async {
    if (_actions.current != null) return;
    await _runAction(SpecActionKind.clone, spec, (a) async {
      final rows = await ref.read(specStepsRepoProvider).bySpec(spec.id);
      // The rows, not the visible steps: a split requirement is hidden
      // behind its sub-steps, and the clone removes requirements.
      final done = {
        for (final r in rows)
          if (r.status == StepStatus.done) r.step,
      };
      final created = await ref
          .read(specServiceProvider)
          .cloneForChange(ws, spec, doneIds: done);
      ref.read(selectedSpecProvider.notifier).select(created.id);
      _snack('${created.code} criada a partir de ${spec.code}.');
    });
  }

  /// "Planejar": the read-only planner writes `## Plano` and
  /// `## Etapas` into the editor (saved by the user).
  /// The spec is held meanwhile (SPEC-025 R1, R3).
  Future<void> _design(Workspace ws, Spec spec) async {
    final c = _controller;
    if (c == null || _actions.current != null || _held(spec.id)) return;
    final source = c.text;
    final designer = ref.read(specDesignerProvider);
    await _runAction(SpecActionKind.design, spec, (a) async {
      final text = await _orCancel(
        a,
        designer.generate(ws, source, cancelled: a.cancelledFuture),
      );
      // R7: the result never goes to another spec.
      if (!mounted || _loadedSpecId != spec.id || _controller == null) {
        debugPrint(
          'Planejar: resultado de ${spec.code} descartado (a spec aberta '
          'mudou).',
        );
        return;
      }
      _controller!.text = text;
      _snack('Plano pronto. Revise e salve.');
    });
  }

  /// Holds the spec only until the conversation opens.
  Future<void> _refine(Workspace ws, Spec spec) async {
    if (_actions.current != null) return;
    // A conversation is the person's edit too (D7): saving drops the mark.
    final marked = SpecDocument.parse(_controller?.text ?? '').autoPlanned;
    if ((_dirty || marked) && await _save(ws, spec) == null) return;
    await _runAction(SpecActionKind.refine, spec, (a) async {
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
    });
  }

  // --- perguntas em aberto (SPEC-028) ---------------------------------------------

  /// "Responder perguntas" (R6): the panel beside the editor, in the place
  /// of the steps panel (the Protótipo mode goes back to the split view).
  void _openQuestions() {
    if (!mounted || _controller == null) return;
    setState(() {
      if (_mode == SpecViewMode.prototype) _mode = SpecViewMode.split;
      _questionsOpen = true;
    });
  }

  /// R12: Esc / "Fechar" keep the answers (R8); the focus goes back to the
  /// editor.
  void _closeQuestions() {
    if (!mounted) return;
    setState(() => _questionsOpen = false);
    _editorFocus.requestFocus();
  }

  /// "Corrigir formato" (R3): the section in the R1 format, in the editor
  /// (saved by the user), the texts unchanged.
  void _fixQuestionsFormat() {
    final c = _controller;
    if (c == null) return;
    final doc = SpecDocument.parse(c.text);
    c.text = doc.withOpenQuestions(doc.openQuestions);
    setState(() => _setWarnings(c.text));
    _snack('Formato das perguntas corrigido. Revise e salve.');
  }

  /// "Aplicar respostas" (R10): `## Decisões` written on the editor text
  /// and, with [update], the Claude's update of the requirements (read-only
  /// run, the text comes back by structured output; the spec is held
  /// meanwhile, SPEC-025). Nothing is saved here (R11).
  Future<AppliedAnswers?> _applyAnswers(
    Workspace ws,
    Spec spec,
    Map<String, Answer> answers,
    bool update,
  ) async {
    final c = _controller;
    if (c == null || _actions.current != null) return null;
    final before = c.text;
    final doc = SpecDocument.parse(before);
    final withDecisions = doc.withAnswers({
      for (final MapEntry(:key, :value) in answers.entries)
        if (value.answered) key: value.text,
    }, DateTime.now());
    if (!update) {
      return (before: before, after: withDecisions, updated: false);
    }
    final byQuestion = {
      for (final q in doc.openQuestions)
        if (answers[q.id] case final a? when a.answered) q: a,
    };
    AppliedAnswers? out;
    final applier = ref.read(specAnswerApplierProvider);
    await _runAction(SpecActionKind.answers, spec, (a) async {
      final text = await _orCancel(
        a,
        applier.apply(
          ws,
          withDecisions,
          byQuestion,
          cancelled: a.cancelledFuture,
        ),
      );
      // SPEC-025 R7: never applied to another spec.
      if (!mounted || _loadedSpecId != spec.id) return;
      out = (before: before, after: text, updated: true);
    });
    return out;
  }

  /// "Salvar na spec" (R11): the text reviewed in the diff is written; the
  /// status is the one it had. The answers of the session are done.
  Future<bool> _saveAnswers(Workspace ws, Spec spec, String text) async {
    final c = _controller;
    if (c == null || _held(spec.id) || _loadedSpecId != spec.id) return false;
    text = SpecDocument.parse(text).withAutoPlan(false);
    try {
      await ref.read(specServiceProvider).save(ws, spec, text);
    } catch (e) {
      _snack('Falha ao salvar: $e');
      return false;
    }
    if (!mounted) return true;
    _saved = text;
    c.text = text;
    _setWarnings(text);
    ref.read(specDirtyProvider.notifier).set(_dirty);
    ref.read(specAnswersProvider.notifier).clear(spec.id);
    setState(() {});
    _snack('Respostas salvas na ${spec.code}.');
    return true;
  }

  // --- protótipo (SPEC-022) -------------------------------------------------------

  PrototypeKey _protoKey(Workspace ws, Spec spec) =>
      (root: ws.path, code: spec.code);

  /// "Gerar telas da spec" (R2); the spec is held meanwhile (SPEC-025 R9).
  /// [only]: "Gerar tela do `R<n>`" of an empty requirement (SPEC-027 R7).
  Future<void> _generateScreens(
    Workspace ws,
    Spec spec, {
    Set<String>? only,
  }) async {
    final c = _controller;
    if (c == null || _actions.current != null) return;
    final text = c.text;
    final service = ref.read(prototypeServiceProvider);
    await _runAction(SpecActionKind.screens, spec, (a) async {
      final r = await _orCancel(
        a,
        service.generate(
          ws,
          spec,
          text,
          cancelled: a.cancelledFuture,
          only: only,
        ),
      );
      _snack(_outcomeText(r, 'Nenhuma tela nova.'));
    });
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

  /// Approved file names of [screens] (by `## Protótipo` of the editor).
  Set<String> _approvedOf(List<MockupScreen> screens) {
    final approved = SpecDocument.parse(_controller?.text ?? _saved).prototypes;
    return {
      for (final x in screens)
        if (approvedFile(approved, x.requirement) == x.file) x.file,
    };
  }

  /// Sets ([path]) or removes (null) the `## Protótipo` line of [req] on
  /// disk and in the editor, which keeps unsaved changes unsaved (SPEC-027
  /// R5, as [_approveScreen]). [only]: changed only while it points to that
  /// file.
  Future<void> _setPrototypeLine(
    Workspace ws,
    Spec spec,
    String req,
    String? path, {
    String? only,
  }) async {
    bool applies(String text) =>
        only == null ||
        SpecDocument.parse(text).prototypes[req]?.split('/').last == only;
    final service = ref.read(specServiceProvider);
    final disk = await service.read(ws, spec) ?? _saved;
    final next = applies(disk)
        ? SpecDocument.parse(disk).withPrototype(req, path)
        : disk;
    if (next != disk) await service.save(ws, spec, next);
    if (!mounted || _loadedSpecId != spec.id) return;
    final c = _controller;
    if (c == null) return;
    final dirty = _dirty;
    _saved = next;
    if (!dirty) {
      c.text = next;
    } else if (applies(c.text)) {
      c.text = SpecDocument.parse(c.text).withPrototype(req, path);
    }
    ref.read(specDirtyProvider.notifier).set(_dirty);
    setState(() {});
  }

  /// "Apagar tela…" / "Apagar N telas…" (SPEC-027 R2–R6, R10): asks,
  /// deletes, removes the approved lines and offers "Desfazer".
  Future<void> _deleteScreens(
    Workspace ws,
    Spec spec,
    List<MockupScreen> screens,
  ) async {
    if (screens.isEmpty || _controller == null) return;
    final key = _protoKey(ws, spec);
    final before = ref.read(prototypeScreensProvider(key)).screens;
    final approved = _approvedOf(screens);
    if (approved.isNotEmpty && spec.stage != SpecStage.backlog) {
      _snack(
        '${spec.code} já foi iniciada: a tela aprovada não pode ser apagada.',
      );
      return;
    }
    final ok = await showDeleteScreensDialog(
      context,
      screens: screens,
      specCode: spec.code,
      approved: approved,
      thumbs: ref.read(prototypeScreensProvider(key)).thumbs,
    );
    if (!ok || !mounted) return;
    // R8: a generation that started meanwhile wins.
    if (ref.read(prototypeJobsProvider).containsKey(spec.id) ||
        _held(spec.id)) {
      _snack(deleteBusyHint);
      return;
    }
    final service = ref.read(prototypeServiceProvider);
    final uiCtrl = ref.read(prototypeUiProvider(spec.id).notifier);
    try {
      var removed = await service.removeAll(
        ws,
        spec,
        screens,
        approved: approved,
      );
      final lines = <String, String>{};
      for (final x in screens) {
        if (!approved.contains(x.file)) continue;
        await _setPrototypeLine(ws, spec, x.requirement, null, only: x.file);
        lines[x.requirement] = '${mockupDir(spec.code)}/${x.file}';
      }
      removed = removed.withLines(lines);
      if (!mounted) return;
      // R10: out of the selection and the comparison; the focus goes to
      // the next card (or the empty slot).
      final files = {for (final x in screens) x.file};
      final left = [
        for (final x in before)
          if (!files.contains(x.file)) x,
      ];
      uiCtrl.forget(files, left);
      final target = _focusAfterDelete(before, screens, left);
      if (target != null) uiCtrl.focusOn(target);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          deletedAnnouncement(screens.length),
          TextDirection.ltr,
        ),
      );
      _undo.offer(
        PrototypeUndo(
          specId: spec.id,
          message: deletedMessage(screens),
          undo: () => _restoreScreens(ws, spec, removed),
        ),
      );
    } catch (e) {
      _snack('Falha ao apagar: $e');
    }
  }

  /// Card that gets the focus after deleting [gone] (R10): the next one
  /// after the last deleted, else the previous; the empty slot when the
  /// requirement was left without screens.
  String? _focusAfterDelete(
    List<MockupScreen> before,
    List<MockupScreen> gone,
    List<MockupScreen> left,
  ) {
    final files = {for (final x in gone) x.file};
    final last = before.lastIndexWhere((x) => files.contains(x.file));
    if (last < 0) return null;
    final req = before[last].requirement;
    if (!left.any((x) => x.requirement == req)) return req;
    for (var i = last + 1; i < before.length; i++) {
      if (!files.contains(before[i].file)) return before[i].file;
    }
    for (var i = last - 1; i >= 0; i--) {
      if (!files.contains(before[i].file)) return before[i].file;
    }
    return null;
  }

  /// "Desfazer" (SPEC-027 R6): files, index and `## Protótipo` lines.
  Future<void> _restoreScreens(
    Workspace ws,
    Spec spec,
    RemovedScreens removed,
  ) async {
    try {
      await ref.read(prototypeServiceProvider).restore(ws, spec, removed);
      for (final MapEntry(key: req, value: path)
          in removed.prototypeLines.entries) {
        await _setPrototypeLine(ws, spec, req, path);
      }
      if (!mounted || removed.screens.isEmpty) return;
      ref
          .read(prototypeUiProvider(spec.id).notifier)
          .focusOn(removed.screens.first.file);
    } catch (e) {
      _snack('Falha ao desfazer: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(msg)));
  }

  /// The status strip of a long action (R3; in Protótipo the generation
  /// card has it, R9) and the failure alert (R8), above [child].
  Widget _withActionStrips({
    required Workspace ws,
    required Spec? spec,
    required SpecActionState? action,
    required bool proto,
    required SpecActionFailure? failure,
    required SpecPlanLock? planLock,
    required Widget child,
  }) {
    final strip =
        spec != null &&
        action != null &&
        action.kind.long &&
        !(proto && action.kind == SpecActionKind.screens);
    // Always the same two children: the editor below is never remounted
    // when a strip comes or goes (it would lose its scroll and focus).
    // Tab goes strip → editor, in the visual order (R11).
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: strip
                ? SpecActionBanner(
                    title: action.kind.title(spec.code),
                    startedAt: action.startedAt,
                    onCancel: _actions.cancel,
                    cancelFocus: _cancelFocus,
                  )
                : planLock != null
                ? _PlanLockStrip(text: planLock.strip)
                : failure != null && spec != null
                ? SpecActionError(
                    title: failure.kind.failure,
                    cause: failure.cause,
                    onRetry: () => _retry(ws, spec, failure.kind),
                    onClose: () => setState(() => _failure = null),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  // --- build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return _Shell(
        header: const SpecHeader(
          title: 'Specs',
          zoom: ZoomControl(editorKey: SpecsScreen.editorKey),
        ),
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
      _shownBody = null;
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
    // While another spec is on the way the controller has the old text,
    // which says nothing about [spec].
    final current =
        spec != null && _controller != null && _docSpecId == spec.id;
    final text = current ? _controller!.text : '';
    final doc = SpecDocument.parse(text);
    // Traceability of the step clicked in the steps panel (U5).
    final selectedStep = ref.watch(selectedStepProvider);
    final tracedStep = spec == null || selectedStep?.specId != spec.id
        ? null
        : stepsOf(
            spec,
            stepRows,
          ).where((st) => st.id == selectedStep!.step).firstOrNull;
    final openError = spec != null && _openError?.specId == spec.id
        ? _openError
        : null;
    final ready = current && !_loading && openError == null;
    final notReadyReason = openError != null
        ? 'A spec não abriu.'
        : 'Aguarde a spec carregar.';
    // Started specs are a record of what was delivered: changes go to a
    // clone ("Clonar para alterar").
    final locked = spec != null && spec.stage != SpecStage.backlog;
    // SPEC-025 R1: an action in progress holds the spec too.
    final action = ref.watch(specActionProvider);
    final held = spec != null && action?.specId == spec.id;
    // SPEC-037 R10, R13: so does the automatic plan.
    final planLock = spec == null
        ? null
        : ref.watch(specAutoPlannerProvider.select((s) => s.lockOf(spec.id)));
    if (spec != null) {
      ref.listen(specAutoPlannerProvider, (previous, next) {
        if (spec.id != _loadedSpecId) return;
        final was = previous?.lockOf(spec.id), now = next.lockOf(spec.id);
        if (was?.writing == true && now?.writing != true) {
          unawaited(_reloadPlanned(ws, spec));
        }
      });
    }
    final readOnly =
        spec != null &&
        (planLock != null ||
            specLocked(specId: spec.id, stageLocked: locked, action: action));
    final failure = spec != null && _failure?.specId == spec.id
        ? _failure
        : null;
    final proto = _mode == SpecViewMode.prototype && spec != null;
    final protoState = proto
        ? ref.watch(prototypeScreensProvider(_protoKey(ws, spec)))
        : null;
    final protoUi = proto ? ref.watch(prototypeUiProvider(spec.id)) : null;
    final protoBusy =
        proto && ref.watch(prototypeJobsProvider).containsKey(spec.id);
    final approvedScreens = doc.prototypes;
    final compareReq = proto ? compareTarget(protoState!, protoUi!) : null;
    // SPEC-027 R8: deleting waits for a generation (or another action).
    final generatingScreens =
        protoBusy || (held && action!.kind == SpecActionKind.screens);
    final deleteReason = !ready
        ? notReadyReason
        : generatingScreens
        ? deleteBusyHint
        : held
        ? 'Aguarde a ação terminar'
        : null;
    final DeleteScreens? onDeleteScreens = spec != null && deleteReason == null
        ? (screens) => _deleteScreens(ws, spec, screens)
        : null;
    // SPEC-028: the questions of the editor text and the format notice.
    final questions = doc.openQuestions;
    final questionsOpen = _questionsOpen && ready && !proto;
    final formatNotice = locked || readOnly
        ? null
        : _warnings
              .where((w) => w.kind == SpecWarningKind.openQuestionsFormat)
              .firstOrNull;
    final undoBindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          unawaited(ref.read(prototypeUndoProvider.notifier).undo()),
    };

    if (ready) {
      final controller = _controller!;
      _shownBody = ({required bool hold}) => IgnorePointer(
        ignoring: hold,
        child: ExcludeFocus(
          excluding: hold,
          child: proto
              ? CallbackShortcuts(
                  bindings: undoBindings,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child:
                            (protoUi!.comparing != null &&
                                protoState!
                                    .variationsOf(protoUi.comparing!)
                                    .isNotEmpty
                            ? PrototypeCompare(
                                ws: ws,
                                spec: spec,
                                approved: approvedScreens,
                                onApprove: readOnly
                                    ? null
                                    : (x) => _approveScreen(ws, spec, x),
                                onViewSpec: () {
                                  ref
                                      .read(
                                        prototypeUiProvider(spec.id).notifier,
                                      )
                                      .compare(null);
                                  setState(() => _mode = SpecViewMode.preview);
                                },
                              )
                            : PrototypeCanvas(
                                ws: ws,
                                spec: spec,
                                approved: approvedScreens,
                                onDelete: onDeleteScreens,
                                deleteReason: deleteReason,
                                onGenerate:
                                    ready && !protoBusy && action == null
                                    ? (req) => _generateScreens(
                                        ws,
                                        spec,
                                        only: {req},
                                      )
                                    : null,
                              )),
                      ),
                      Positioned(
                        left: 20,
                        bottom: 20,
                        child: PrototypeUndoToast(specId: spec.id),
                      ),
                    ],
                  ),
                )
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
                    key: ObjectKey(controller),
                    controller: controller,
                    text: text,
                    onSave: () => _save(ws, spec),
                    readOnly: readOnly || hold,
                    dimmed: held,
                    focusNode: _editorFocus,
                    warnings: locked
                        ? const []
                        : [
                            for (final w in _warnings)
                              if (w.kind != SpecWarningKind.openQuestionsFormat)
                                w,
                          ],
                    lineMarks: _questionMarks,
                    questionsNotice: formatNotice?.message,
                    onFixQuestions: _fixQuestionsFormat,
                    onAnswerQuestions: _openQuestions,
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
      );
    }

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
                header: SpecHeader(
                  path: spec?.path,
                  title: spec == null ? 'Specs' : (doc.title ?? spec.title),
                  status: spec == null ? null : (doc.status ?? spec.status),
                  locked: locked,
                  mode: _mode,
                  onMode: (m) {
                    // SPEC-027 R6: leaving the Protótipo mode makes a
                    // deletion final.
                    if (m != SpecViewMode.prototype) _undo.dismiss();
                    setState(() => _mode = m);
                  },
                  showSaveState: ready,
                  dirty: _dirty,
                  onSave: ready && !readOnly ? () => _save(ws, spec) : null,
                  lockLabel: held ? action!.kind.lockLabel : planLock?.reason,
                  statusLabel: planLock?.chip,
                  lockAlert: (held && action!.kind.long) || planLock != null,
                  zoom: const ZoomControl(editorKey: SpecsScreen.editorKey),
                  actions: spec == null
                      ? null
                      : SpecHeaderState(
                          locked: locked,
                          approved: doc.status == SpecStatus.approved,
                          hasPlan: doc.design != null,
                          prototype: proto,
                          archived: spec.status == SpecStatus.archived,
                          unavailableReason:
                              planLock?.reason ??
                              (!ready ? notReadyReason : null),
                          // R2: the running action shows its gerund label;
                          // one on another spec only disables these.
                          runningId: action == null
                              ? null
                              : held
                              ? action.kind.headerId
                              : '',
                          runningLabel: held ? action!.kind.running : null,
                          generateReason: protoBusy
                              ? 'As telas desta spec já estão sendo geradas.'
                              : null,
                          onArchive:
                              (canArchiveSpec(spec) ||
                                  spec.status == SpecStatus.archived)
                              ? () => archiveSpecAction(
                                  context,
                                  ref,
                                  spec,
                                  restore: spec.status == SpecStatus.archived,
                                )
                              : null,
                          onDelete: canDeleteSpec(spec) && planLock == null
                              ? () => deleteSpecAction(context, ref, spec)
                              : null,
                          onAnswer:
                              ready &&
                                  !locked &&
                                  action == null &&
                                  planLock == null &&
                                  questions.isNotEmpty
                              ? _openQuestions
                              : null,
                          onClone: ready && locked && action == null
                              ? () => _clone(ws, spec)
                              : null,
                          onRefine:
                              ready &&
                                  !locked &&
                                  action == null &&
                                  planLock == null
                              ? () => _refine(ws, spec)
                              : null,
                          onDesign:
                              ready &&
                                  !locked &&
                                  action == null &&
                                  planLock == null
                              ? () => _design(ws, spec)
                              : null,
                          onApprove:
                              ready &&
                                  !locked &&
                                  action == null &&
                                  planLock == null &&
                                  doc.status != SpecStatus.approved
                              ? () => _approve(ws, spec)
                              : null,
                          onCompare: proto && compareReq != null
                              ? () => ref
                                    .read(prototypeUiProvider(spec.id).notifier)
                                    .compare(
                                      compareReq,
                                      chosen: protoState!.screens
                                          .where(
                                            (x) =>
                                                x.requirement == compareReq &&
                                                protoUi!.selected.contains(
                                                  x.file,
                                                ),
                                          )
                                          .firstOrNull
                                          ?.file,
                                    )
                              : null,
                          onGenerate:
                              proto && ready && !protoBusy && action == null
                              ? () => _generateScreens(ws, spec)
                              : null,
                        ),
                ),
                body: _withActionStrips(
                  ws: ws,
                  spec: spec,
                  action: held ? action : null,
                  proto: proto,
                  failure: failure,
                  planLock: planLock,
                  child: spec == null
                      ? const Center(
                          child: Text(
                            'Crie uma spec com "Nova spec".',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : SpecTextFade(
                          turn: _fadeTurn,
                          child: openError != null
                              ? SpecOpenError(
                                  key: const ValueKey('spec-open-error'),
                                  message: openError.message,
                                  onRetry: () => _load(ws, spec),
                                )
                              : ready
                              ? _shownBody!(hold: false)
                              : _skeletonDue
                              ? const SpecSkeleton(
                                  key: ValueKey('spec-skeleton'),
                                )
                              : _shownBody?.call(hold: true) ??
                                    const SizedBox.shrink(),
                        ),
                ),
              ),
            ),
            SizedBox(
              width: questionsOpen ? 440 : sideW,
              child: spec == null
                  ? const ColoredBox(color: AppColors.panel)
                  : questionsOpen
                  ? SpecQuestionsPanel(
                      key: ValueKey('spec-questions-${spec.id}'),
                      ws: ws,
                      specId: spec.id,
                      specCode: spec.code,
                      specText: () => _controller?.text ?? '',
                      questions: questions,
                      onClose: _closeQuestions,
                      onApply: (answers, update) =>
                          _applyAnswers(ws, spec, answers, update),
                      onSave: (text) => _saveAnswers(ws, spec, text),
                    )
                  : proto
                  ? CallbackShortcuts(
                      bindings: undoBindings,
                      child: PrototypePanel(
                        ws: ws,
                        spec: spec,
                        approved: approvedScreens,
                        onSend: ready
                            ? (request) => _sendRequest(ws, spec, request)
                            : null,
                        onDelete: onDeleteScreens,
                        deleteReason: deleteReason,
                      ),
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
                                  locked: readOnly,
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
          canVerify: !_dirty && action == null,
          onUpdated: () {
            if (spec != null && !_dirty && !held) _load(ws, spec);
          },
        ),
        Expanded(
          // R5: Esc cancels a generation (local to the screen, not global).
          // Always wrapped (no bindings when idle): the subtree is not
          // remounted when an action starts.
          child: CallbackShortcuts(
            bindings: {
              if (held && action!.kind.long)
                const SingleActivator(LogicalKeyboardKey.escape):
                    _actions.cancel,
            },
            child: content,
          ),
        ),
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

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    super.key,
    required this.mode,
    required this.controller,
    required this.text,
    required this.onSave,
    this.readOnly = false,
    this.dimmed = false,
    this.lockedBanner,
    this.focusNode,
    this.warnings = const [],
    this.warningsOpen = false,
    this.onToggleWarnings,
    this.onWarning,
    this.lineMarks,
    this.questionsNotice,
    this.onFixQuestions,
    this.onAnswerQuestions,
  });

  final FocusNode? focusNode;

  /// Suggestions counted as questions, marked in the editor (SPEC-028 R2).
  final ValueListenable<Map<int, Color>>? lineMarks;

  /// "Perguntas em aberto" outside the format (SPEC-028 R3): the notice
  /// above the editor with "Corrigir formato" and "Responder perguntas".
  final String? questionsNotice;
  final VoidCallback? onFixQuestions;
  final VoidCallback? onAnswerQuestions;

  /// Structure warnings (SPEC-023 R8): the strip below the editor, hidden
  /// when there are none.
  final List<SpecWarning> warnings;
  final bool warningsOpen;
  final VoidCallback? onToggleWarnings;
  final ValueChanged<SpecWarning>? onWarning;
  final bool readOnly;

  /// Held by an action (SPEC-025 R4).
  final bool dimmed;
  final String? lockedBanner;
  final SpecViewMode mode;
  final CodeLineEditingController controller;
  final String text;
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
      dimmed: dimmed,
      focusNode: focusNode,
      lineMarks: lineMarks,
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
    if (questionsNotice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpecQuestionsFormatNotice(
            message: questionsNotice!,
            onFix: onFixQuestions,
            onAnswer: onAnswerQuestions,
          ),
          Expanded(child: body),
        ],
      );
    }
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

/// Why the spec is held by the automatic plan (SPEC-037 R10, R13).
class _PlanLockStrip extends StatelessWidget {
  const _PlanLockStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('spec-plan-lock'),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    decoration: const BoxDecoration(
      color: AppColors.amberTint,
      border: Border(bottom: BorderSide(color: SessionColors.approvalBorder)),
    ),
    child: Row(
      children: [
        const ActionSpinner(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.amber),
          ),
        ),
      ],
    ),
  );
}

/// "Em 'Perguntas em aberto', N itens são sugestões…" (SPEC-028 R3), above
/// the editor: "Corrigir formato" (secondary, not to compete with
/// "Aprovar") and "Responder perguntas".
class SpecQuestionsFormatNotice extends StatelessWidget {
  const SpecQuestionsFormatNotice({
    super.key,
    required this.message,
    this.onFix,
    this.onAnswer,
  });

  final String message;
  final VoidCallback? onFix;
  final VoidCallback? onAnswer;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('spec-questions-format'),
    padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
    decoration: const BoxDecoration(
      color: SessionColors.approvalBg,
      border: Border(bottom: BorderSide(color: SessionColors.approvalBorder)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 16, color: AppColors.amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            key: const ValueKey('spec-questions-format-text'),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.text,
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const ValueKey('spec-questions-fix'),
          onPressed: onFix,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.amber),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text(
            'Corrigir formato',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const ValueKey('spec-questions-format-answer'),
          onPressed: onAnswer,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.help_outline, size: 15),
          label: const Text(
            'Responder perguntas',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
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
