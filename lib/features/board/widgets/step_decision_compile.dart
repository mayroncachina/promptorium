import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/system/worktree_launcher.dart';
import '../../../core/text/line_diff.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../../ui/widgets/diff_view.dart';
import '../../project/project_config.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/timeline_provider.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart';
import '../board_rules.dart';
import '../step_decision.dart';
import '../step_decision_apply.dart';
import '../step_decision_choices.dart';
import '../step_decision_compiler.dart';
import 'step_decision_chrome.dart';
import 'step_decision_parts.dart';

/// How long "Desfazer" stays offered (R10).
const stepDecisionUndoWindow = Duration(seconds: 8);

/// Width of the column with the decisions and the message.
const _decisionsWidth = 300.0;

/// Its buttons fill the bar: the keys only fit with the modal at full width.
const _keysMinWidth = 924.0;

/// What the Compilar phase of the modal gets (SPEC-033 R9–R11).
@immutable
class StepDecisionCompileRequest {
  const StepDecisionCompileRequest({
    required this.spec,
    required this.step,
    required this.summary,
    required this.decisions,
    required this.choices,
    required this.onBack,
    required this.onChange,
    required this.onClose,
    required this.onSubmit,
    required this.opened,
    required this.onOpenSession,
  });

  final Spec spec;
  final StepView step;
  final String summary;

  /// Empty when the options failed or did not arrive: the only answer is
  /// "Outra resposta".
  final List<StepDecision> decisions;

  /// Every decision has one, in order.
  final List<StepDecisionChoice> choices;

  /// "Voltar" (also `Backspace`, outside a text field).
  final VoidCallback onBack;

  /// "Mudar": back to the decision of that index.
  final ValueChanged<int> onChange;

  /// Closes the modal and gives the focus back to the balloon.
  final VoidCallback onClose;

  /// Fires on `Ctrl+Enter` during the phase: the primary button.
  final Listenable onSubmit;

  /// The spec file when the modal opened (R11).
  final Future<SpecFileStamp?> opened;

  /// "Abrir sessão" (R12); null when the step has no session.
  final VoidCallback? onOpenSession;
}

/// Builds the Compilar phase; [StepDecisionDialog] shows it in place of the
/// options, the preview and their bar, under the header.
typedef StepDecisionCompileBuilder = Widget Function(
  BuildContext context,
  StepDecisionCompileRequest request,
);

Widget buildStepDecisionCompile(
  BuildContext context,
  StepDecisionCompileRequest request,
) => StepDecisionCompilePhase(
  key: const ValueKey('step-decision-compile'),
  request: request,
);

/// What the header says in the phase: "Duas decisões tomadas. …".
String stepDecisionReady(List<StepDecisionChoice> choices) {
  const words = {1: 'Uma decisão tomada', 2: 'Duas decisões tomadas'};
  final done = words[choices.length] ?? '${choices.length} decisões tomadas';
  final place = stepDecisionNeedsCompiler(choices)
      ? 'o que muda na spec e '
      : stepDecisionSplitBodies(choices).isNotEmpty
      ? 'o que muda na fila e '
      : '';
  return '$done. Revise ${place}a mensagem que o agente vai receber.';
}

/// `R3.1 e R3.2`, `R3.1, R3.2 e R3.3`.
String _subStepList(String step, int count) {
  final ids = [for (var i = 1; i <= count; i++) '$step.$i'];
  return '${ids.sublist(0, count - 1).join(', ')} e ${ids.last}';
}

enum _CompileStatus { compiling, ready, failed, conflict }

/// The review before the step goes on (R9): the decisions, what changes in
/// the spec, the message, and what approves them (R10, R11).
class StepDecisionCompilePhase extends ConsumerStatefulWidget {
  const StepDecisionCompilePhase({super.key, required this.request});

  final StepDecisionCompileRequest request;

  @override
  ConsumerState<StepDecisionCompilePhase> createState() =>
      _StepDecisionCompilePhaseState();
}

class _StepDecisionCompilePhaseState
    extends ConsumerState<StepDecisionCompilePhase> {
  final _message = TextEditingController();
  final _stop = Completer<void>();

  var _status = _CompileStatus.ready;
  late Future<SpecFileStamp?> _opened = _request.opened;
  StepCompilation? _compiled;
  List<DiffRow> _rows = const [];
  String _changes = '';

  /// Reason of [_CompileStatus.failed].
  String _reason = '';

  /// The failure is in the choices: another run gives the same.
  var _splitRefused = false;

  /// "Compilar e continuar" or "Só alterar a spec" are writing.
  var _busy = false;

  /// Why the last "Compilar e continuar" could not resume the step.
  String? _resumeError;

  StepDecisionCompileRequest get _request => widget.request;
  Spec get _spec => _request.spec;
  StepView get _step => _request.step;
  List<StepDecisionChoice> get _choices => _request.choices;

  bool _has(StepDecisionKind kind) => _choices.any((c) => c.kind == kind);

  /// Only "Responder": P3.
  bool get _answersOnly =>
      _choices.every((c) => c.kind == StepDecisionKind.answer);

  bool get _changesSpec => _compiled?.changesSpec ?? false;

  bool get _canSubmit =>
      _status == _CompileStatus.ready &&
      !_busy &&
      _message.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _request.onSubmit.addListener(_continue);
    _prepare();
    _message.addListener(_onMessage);
  }

  @override
  void dispose() {
    _request.onSubmit.removeListener(_continue);
    if (!_stop.isCompleted) _stop.complete();
    _message.dispose();
    super.dispose();
  }

  void _onMessage() => setState(() {});

  /// Runs the compiler when something touches the file; the message of the
  /// other choices is ready already.
  void _prepare() {
    final refused = stepDecisionSplitProblem(_step, _choices);
    if (refused != null) {
      _status = _CompileStatus.failed;
      _reason = refused;
      _splitRefused = true;
    } else if (stepDecisionNeedsCompiler(_choices)) {
      _status = _CompileStatus.compiling;
      unawaited(_compile());
    } else {
      _status = _CompileStatus.ready;
      _message.text = stepDecisionDraft(_request.decisions, _choices);
    }
  }

  Future<void> _compile() async {
    try {
      final compiled = await ref
          .read(stepDecisionCompilerProvider)
          .compile(_spec, _step, _choices, cancelled: _stop.future);
      if (!mounted) return;
      setState(() {
        _compiled = compiled;
        _rows = specDiffRows(compiled.before, compiled.after);
        _changes = specChangeSummary(compiled.before, compiled.after);
        _status = _CompileStatus.ready;
      });
      _message.text = compiled.message;
    } catch (e) {
      debugPrint('compilar a etapa: $e');
      if (!mounted) return;
      setState(() {
        _status = _CompileStatus.failed;
        _reason = stepDecisionReason(e);
      });
    }
  }

  void _retry() => setState(_prepare);

  /// "Recompilar" (R11): what is on the disk now is the new starting point.
  void _recompile() {
    final applier = ref.read(stepDecisionApplierProvider);
    setState(() {
      _opened = applier.stamp(_spec);
      _resumeError = null;
      _prepare();
    });
  }

  Future<StepDecisionPlan> _plan() async => StepDecisionPlan(
    spec: _spec,
    step: _step,
    choices: _choices,
    message: _message.text.trim(),
    opened: await _opened,
    compiled: _compiled,
  );

  /// Runs [write] with the buttons off; when it ends well, closes the modal
  /// and shows what it returns. A conflict and a step that did not resume
  /// stay in the phase.
  Future<void> _write(Future<SnackBar> Function(StepDecisionPlan) write) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _resumeError = null;
    });
    try {
      final toast = await write(await _plan());
      _request.onClose();
      messenger
        ?..hideCurrentSnackBar()
        ..showAppToast(toast);
      return;
    } on StepDecisionConflict {
      if (mounted) setState(() => _status = _CompileStatus.conflict);
    } on StepDecisionResumeFailed catch (e) {
      if (mounted) setState(() => _resumeError = e.message);
    } catch (e) {
      debugPrint('gravar a decisão: $e');
      if (mounted) setState(() => _resumeError = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _continue() {
    if (!_canSubmit) return;
    final applier = ref.read(stepDecisionApplierProvider);
    unawaited(
      _write((plan) async {
        final undo = await applier.continueStep(plan);
        return SnackBar(
          duration: stepDecisionUndoWindow,
          content: StepDecisionUndoToast(text: plan.notice, undo: undo),
        );
      }),
    );
  }

  void _saveOnly() {
    if (!_canSubmit) return;
    final applier = ref.read(stepDecisionApplierProvider);
    unawaited(
      _write((plan) async {
        await applier.saveSpec(plan);
        return SnackBar(
          content: Text(
            '${_spec.code}: spec alterada · etapa ${_step.id} segue '
            'aguardando você',
          ),
        );
      }),
    );
  }

  Future<void> _openEditor() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final launcher = ref.read(worktreeLauncherProvider);
    final service = ref.read(specServiceProvider);
    final ws = await ref
        .read(workspacesRepoProvider)
        .getById(_spec.workspaceId);
    if (ws == null) return;
    final editor = ProjectConfig.loadSync(ws.path).editorCommand;
    try {
      final used = await launcher.editor(
        service.fileOf(ws, _spec).path,
        editor: editor,
        cwd: ws.path,
      );
      if (used != 'xdg-open') return;
      messenger?.showAppToast(
        SnackBar(
          content: Text(
            'Editor "${editor ?? 'code'}" não encontrado: a spec abriu no '
            'programa padrão.',
          ),
        ),
      );
    } catch (e) {
      messenger?.showAppToast(SnackBar(content: Text('$e')));
    }
  }

  /// The line under the diff: what the queue and the session will do.
  String _queueNote(bool alive) {
    final id = _step.id;
    final ended = alive ? ' A sessão aberta é encerrada.' : '';
    final news = 'numa sessão nova, com esta mensagem.$ended';
    if (_has(StepDecisionKind.defer)) {
      return 'Fila de etapas: o $id vai para o fim, pendente. A próxima etapa '
          'começa $news';
    }
    if (_has(StepDecisionKind.split)) {
      final count = stepDecisionSplitBodies(_choices).length;
      return 'Fila de etapas: o $id vira ${_subStepList(id, count)}. A '
          'primeira começa $news';
    }
    return alive
        ? 'Fila de etapas: não muda. O $id volta a “em execução” na mesma '
              'sessão, que ainda está aberta.'
        : 'Fila de etapas: não muda. A sessão terminou: o $id volta $news';
  }

  @override
  Widget build(BuildContext context) {
    final showKeys = MediaQuery.sizeOf(context).width >= _keysMinWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DecisionsColumn(
                choices: _choices,
                message: _message,
                waiting: _status == _CompileStatus.compiling,
                onChange: _request.onChange,
              ),
              Expanded(child: _changesColumn()),
            ],
          ),
        ),
        _bar(showKeys),
      ],
    );
  }

  Widget _changesColumn() {
    final id = _step.sessionId;
    final alive = ref.watch(
      sessionManagerProvider.select((s) => id != null && s.isAlive(id)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_resumeError case final error?) ...[
            StepDecisionFailure(
              key: const ValueKey('step-decision-resume-error'),
              lead: 'Não consegui retomar a etapa',
              reason:
                  '${error.replaceFirst(RegExp(r'\.+$'), '')}. A spec e a fila '
                  'voltaram ao que eram.',
            ),
            const SizedBox(height: 8),
          ],
          ...switch (_status) {
            _CompileStatus.compiling => _compiling(),
            _CompileStatus.failed => _failed(),
            _CompileStatus.conflict => _conflict(),
            _CompileStatus.ready when _changesSpec => _diff(alive),
            _CompileStatus.ready => _unchanged(alive),
          },
        ],
      ),
    );
  }

  Widget _title(String text, [String detail = '']) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      if (detail.isNotEmpty) ...[
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            detail,
            key: const ValueKey('step-decision-changes'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ],
  );

  List<Widget> _compiling() => [
    _title('O que muda na spec'),
    const SizedBox(height: 10),
    const StepDecisionGenerating(
      label: 'A IA está aplicando as decisões à spec…',
    ),
    const SizedBox(height: 10),
    const StepDecisionRowsSkeleton(),
  ];

  List<Widget> _failed() => [
    _title('O que muda na spec'),
    const SizedBox(height: 10),
    StepDecisionFailure(
      lead: _splitRefused ? 'Não dá para dividir' : 'Não consegui compilar',
      reason: _reason,
    ),
    if (!_splitRefused) ...[
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: IntrinsicWidth(
          child: AmberButton(
            key: const ValueKey('step-decision-compile-retry'),
            label: 'Tentar de novo',
            height: 34,
            onTap: _retry,
          ),
        ),
      ),
    ],
  ];

  List<Widget> _conflict() => [
    _title('O que muda na spec'),
    const SizedBox(height: 10),
    Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('step-decision-conflict'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SessionColors.approvalBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SessionColors.approvalBorder),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.amber),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A spec mudou enquanto você decidia',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Nada foi gravado. Recompile a partir do arquivo atual.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        IntrinsicWidth(
          child: AmberButton(
            key: const ValueKey('step-decision-recompile'),
            label: 'Recompilar',
            height: 34,
            onTap: _recompile,
          ),
        ),
        IntrinsicWidth(
          child: SmallButton(
            key: const ValueKey('step-decision-open-editor'),
            label: 'Abrir no editor',
            height: 34,
            fontSize: 13,
            background: AppColors.surfaceRaised,
            onTap: _openEditor,
          ),
        ),
      ],
    ),
  ];

  Widget _note(bool alive) => Text(
    _queueNote(alive),
    key: const ValueKey('step-decision-queue'),
    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
  );

  List<Widget> _diff(bool alive) => [
    _title('O que muda na spec', _changes),
    const SizedBox(height: 6),
    Text(
      _spec.path,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        color: AppColors.textSecondary,
      ),
    ),
    const SizedBox(height: 8),
    Expanded(
      child: Container(
        key: const ValueKey('step-decision-diff'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: DiffView(rows: _rows, collapseSame: 3, scrollable: true),
      ),
    ),
    const SizedBox(height: 8),
    _note(alive),
  ];

  List<Widget> _unchanged(bool alive) => [
    _title('O que muda na spec'),
    const SizedBox(height: 10),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.check, size: 16, color: AppColors.teal),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'O requisito não muda',
              key: ValueKey('step-decision-unchanged'),
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 8),
    _note(alive),
  ];

  Widget _bar(bool showKeys) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    decoration: const BoxDecoration(
      color: AppColors.background,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: showKeys ? const StepDecisionCompileKeys() : const SizedBox(),
        ),
        const SizedBox(width: 12),
        // Wraps instead of overflowing in a narrow window.
        Expanded(
          flex: 4,
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              StepDecisionSessionButton(onTap: _request.onOpenSession),
              IntrinsicWidth(
                child: SmallButton(
                  key: const ValueKey('step-decision-compile-back'),
                  label: 'Voltar',
                  height: 34,
                  fontSize: 13,
                  background: Colors.transparent,
                  border: Colors.transparent,
                  trailing: const StepKbd('⌫'),
                  onTap: _busy ? null : _request.onBack,
                ),
              ),
              if (_changesSpec)
                IntrinsicWidth(
                  child: SmallButton(
                    key: const ValueKey('step-decision-only-spec'),
                    label: 'Só alterar a spec',
                    height: 34,
                    fontSize: 13,
                    background: AppColors.surfaceRaised,
                    onTap: _canSubmit ? _saveOnly : null,
                  ),
                ),
              IntrinsicWidth(
                child: SmallButton(
                  key: const ValueKey('step-decision-submit'),
                  label: _busy
                      ? 'Retomando…'
                      : _answersOnly
                      ? 'Enviar e continuar'
                      : 'Compilar e continuar',
                  height: 34,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onAmber,
                  background: AppColors.amber,
                  border: AppColors.amber,
                  icon: Icons.check,
                  trailing: const StepKbd('Ctrl+Enter', onAmber: true),
                  onTap: _canSubmit ? _continue : null,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// "Suas decisões" and "Mensagem para o agente".
class _DecisionsColumn extends StatelessWidget {
  const _DecisionsColumn({
    required this.choices,
    required this.message,
    required this.waiting,
    required this.onChange,
  });

  final List<StepDecisionChoice> choices;
  final TextEditingController message;

  /// The compiler writes the message: nothing to edit yet.
  final bool waiting;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color),
    );
    return Container(
      width: _decisionsWidth,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Suas decisões',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final c in choices)
              _DecisionRow(choice: c, onChange: () => onChange(c.decision)),
            const SizedBox(height: 12),
            const Text(
              'Mensagem para o agente',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Semantics(
              label: 'Mensagem para o agente',
              child: TextField(
                key: const ValueKey('step-decision-message'),
                controller: message,
                enabled: !waiting,
                minLines: 5,
                maxLines: 5,
                style: const TextStyle(fontSize: 13, height: 1.5),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.background,
                  hintText: waiting ? 'A mensagem vem com o diff.' : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: border(AppColors.textMuted),
                  enabledBorder: border(AppColors.textMuted),
                  disabledBorder: border(AppColors.border),
                  focusedBorder: border(AppColors.amber),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Você pode editar antes de enviar.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of "Suas decisões": what was chosen and "Mudar".
class _DecisionRow extends StatelessWidget {
  const _DecisionRow({required this.choice, required this.onChange});

  final StepDecisionChoice choice;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final number = choice.decision + 1;
    const small = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      key: ValueKey('step-decision-decided-$number'),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.check, size: 16, color: AppColors.amber),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  choice.question.isEmpty
                      ? '$number'
                      : '$number · ${choice.question}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
                Text(
                  choice.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      stepDecisionKindIcon(choice.kind),
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        choice.kind.label,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Mudar a decisão $number',
            excludeSemantics: true,
            child: TextButton(
              key: ValueKey('step-decision-change-$number'),
              onPressed: onChange,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amber,
                minimumSize: Size.zero,
                padding: const EdgeInsets.all(4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Mudar', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The notice of R10: [text] and "Desfazer", which leaves at the first event
/// of the session, when the agent has started (P4).
class StepDecisionUndoToast extends ConsumerStatefulWidget {
  const StepDecisionUndoToast({
    super.key,
    required this.text,
    required this.undo,
  });

  final String text;
  final StepDecisionUndo undo;

  @override
  ConsumerState<StepDecisionUndoToast> createState() =>
      _StepDecisionUndoToastState();
}

class _StepDecisionUndoToastState extends ConsumerState<StepDecisionUndoToast> {
  /// An event may come between the message and this toast.
  late var _offered = !_started(
    ref.read(sessionTimelineProvider(widget.undo.sessionId)),
  );

  bool _started(TimelineSnapshot timeline) =>
      timeline.version > widget.undo.eventVersion;

  Future<void> _undo() async {
    final messenger = ScaffoldMessenger.of(context);
    final applier = ref.read(stepDecisionApplierProvider);
    setState(() => _offered = false);
    String text;
    try {
      await applier.undo(widget.undo);
      text = 'Decisão desfeita: a spec e a fila voltaram ao que eram.';
    } on StepDecisionConflict {
      text = 'A spec mudou depois de compilar: nada foi desfeito.';
    } catch (e) {
      debugPrint('desfazer a decisão: $e');
      text = 'Não consegui desfazer: $e';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionTimelineProvider(widget.undo.sessionId), (_, timeline) {
      if (_offered && _started(timeline)) setState(() => _offered = false);
    });
    return Row(
      children: [
        Expanded(
          child: Text(widget.text, key: const ValueKey('step-decision-toast')),
        ),
        if (_offered)
          TextButton(
            key: const ValueKey('step-decision-undo'),
            onPressed: _undo,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.amber,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Desfazer'),
          ),
      ],
    );
  }
}
