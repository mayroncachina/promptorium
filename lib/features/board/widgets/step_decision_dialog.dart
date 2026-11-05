import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/session_manager.dart';
import '../board_rules.dart';
import '../board_screen.dart' show openSession, specStepsProvider;
import '../spec_runner.dart' show pendingEscalationProvider, specRunnerProvider;
import '../step_decision.dart';
import '../step_decision_apply.dart';
import '../step_decision_choices.dart';
import '../step_decision_compiler.dart';
import 'duel_dialog.dart' show openDuelsProvider, showDuelDialog;
import 'spec_canvas.dart' show attentionPulsePeriod;
import 'step_decision_chrome.dart';
import 'step_decision_compile.dart';
import 'step_decision_parts.dart';
import 'step_decision_preview.dart';
import 'step_live_dialog.dart';

export 'step_decision_compile.dart'
    show
        StepDecisionCompileBuilder,
        StepDecisionCompileRequest,
        StepDecisionUndoToast,
        buildStepDecisionCompile;
export 'step_decision_preview.dart' show StepDecisionPreview;

/// Scale the modal grows from (R2).
const stepDecisionOpenScale = 0.92;

/// Time to see the confirmation before the next decision (R8).
const stepDecisionAdvanceDelay = Duration(milliseconds: 250);

/// Width of the modal, and of the screen under which the preview leaves.
const _modalWidth = 900.0;
const _modalHeight = 644.0;
const _previewWidth = 330.0;
const _keysMinWidth = 640.0;

/// Opening sequence (R2), in ms since the modal started to open. The last
/// line is "Outra resposta", the fifth at most.
const _firstRowMs = 120;
const _rowGapMs = 40;
const _previewMs = 260;
const _sequenceMs = _firstRowMs + _rowGapMs * stepDecisionOtherRow + 160;

/// The rect of [context] on the screen: where the modal grows from.
Rect stepOrigin(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : Rect.zero;
}

/// Opens [step] from a balloon, a segment, a row or an inbox item (R1): the
/// comparison of a duel that is ready, the decision modal of a step waiting
/// for the person, or the step followed live.
///
/// [returnFocus] is the node of what was pressed, which gets the focus back.
Future<void> openStep(
  BuildContext context,
  Spec spec,
  StepView step,
  Rect origin, {
  FocusNode? returnFocus,
}) {
  if (step.status != StepStatus.needsInput) {
    return showStepLiveDialog(context, spec: spec, step: step.id);
  }
  final duel = ProviderScope.containerOf(context, listen: false)
      .read(openDuelsProvider(spec.workspaceId))
      .value
      ?.where((d) => d.specId == spec.id && d.state == 'pronto')
      .firstOrNull;
  if (duel != null) return showDuelDialog(context, duel);
  return showStepDecision(
    context,
    spec,
    step,
    origin: origin,
    returnFocus: returnFocus,
  );
}

/// The decision modal of [step] (SPEC-033), growing out of [origin].
Future<void> showStepDecision(
  BuildContext context,
  Spec spec,
  StepView step, {
  required Rect origin,
  FocusNode? returnFocus,
}) async {
  final toSession = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    origin: origin,
    originScale: stepDecisionOpenScale,
    builder: (_) => StepDecisionDialog(spec: spec, step: step),
  );
  // "Abrir sessão" leaves the focus to the message field. No parent = what
  // opened the modal is gone (the item left the inbox).
  if (toSession == true || returnFocus?.parent == null) return;
  returnFocus!.requestFocus();
}

/// Gives what opens a step a focus node of its own (R15): the modal hands the
/// focus back to it, even when it was opened with the mouse.
class StepFocusAnchor extends StatefulWidget {
  const StepFocusAnchor({super.key, required this.builder});

  final Widget Function(BuildContext context, FocusNode focus) builder;

  @override
  State<StepFocusAnchor> createState() => _StepFocusAnchorState();
}

class _StepFocusAnchorState extends State<StepFocusAnchor> {
  final _focus = FocusNode(debugLabel: 'etapa');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _focus);
}

enum StepDecisionPhase { deciding, compile }

/// Decides a step that stopped in "aguardando você" without opening the
/// session (SPEC-033): summary, options, preview and, when every decision is
/// answered, the phase of [compileBuilder].
class StepDecisionDialog extends ConsumerStatefulWidget {
  const StepDecisionDialog({
    super.key,
    required this.spec,
    required this.step,
    this.compileBuilder = buildStepDecisionCompile,
  });

  final Spec spec;
  final StepView step;

  /// The Compilar phase (R9–R11): `Compilar` and `Ctrl+Enter` show it.
  final StepDecisionCompileBuilder compileBuilder;

  @override
  ConsumerState<StepDecisionDialog> createState() => _StepDecisionDialogState();
}

class _StepDecisionDialogState extends ConsumerState<StepDecisionDialog>
    with TickerProviderStateMixin {
  // Above the text field in the focus tree, so these see every key first.
  static const _compileKeys = [
    SingleActivator(LogicalKeyboardKey.enter, control: true),
    SingleActivator(LogicalKeyboardKey.numpadEnter, control: true),
  ];
  static const _sessionKey = SingleActivator(
    LogicalKeyboardKey.keyO,
    control: true,
  );
  static const _closeKey = SingleActivator(LogicalKeyboardKey.escape);
  static const _enterKeys = [
    SingleActivator(LogicalKeyboardKey.enter),
    SingleActivator(LogicalKeyboardKey.numpadEnter),
  ];
  static const _upKey = SingleActivator(LogicalKeyboardKey.arrowUp);
  static const _downKey = SingleActivator(LogicalKeyboardKey.arrowDown);
  static const _backKey = SingleActivator(
    LogicalKeyboardKey.backspace,
    includeRepeats: false,
  );

  /// Key `n` is at index `n - 1`, on both rows of digits.
  static const _digitKeys = [
    [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
    [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
    [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
    [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
    [LogicalKeyboardKey.digit5, LogicalKeyboardKey.numpad5],
  ];

  late final StepDecisionOptions _options;
  late final StepDecisionChoices _choices;

  /// The spec file when the modal opened (R11).
  late final Future<SpecFileStamp?> _opened;

  /// Keeps the focus inside and sees every key, even when no row has it (a
  /// click outside a text field leaves the focus on this scope).
  final _root = FocusScopeNode(debugLabel: 'decisão', skipTraversal: true);
  final _rows = [
    for (var i = 0; i <= stepDecisionOtherRow; i++)
      FocusNode(debugLabel: 'opção ${i + 1}'),
  ];
  final _otherField = FocusNode(debugLabel: 'outra resposta');
  final _other = TextEditingController();
  final _submit = _Signal();

  /// Opening sequence, and the bubble's single pulse (R2).
  late final AnimationController _sequence = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _sequenceMs),
  );
  AnimationController? _pulse;
  Animation<double>? _routeAnimation;
  var _motionReady = false;

  var _phase = StepDecisionPhase.deciding;

  /// The choices that went to Compilar: they are forgotten before the modal
  /// finishes closing, and it must not show that.
  List<StepDecisionChoice> _reviewed = const [];
  var _index = 0;
  var _otherOpen = false;

  /// Row of the preview when no row has the focus.
  var _lastRow = 0;
  Timer? _advance;

  Spec get _spec => widget.spec;
  StepView get _step => widget.step;
  StepDecisionTarget get _target => (_spec.id, _step.id);
  StepDecisionChoiceKey get _key => stepDecisionChoiceKey(_spec.id, _step);

  StepDecisionState get _state => ref.read(stepDecisionProvider(_target));
  List<StepDecision> get _decisions =>
      _state.result?.decisions ?? const <StepDecision>[];

  /// Before the options, "Outra resposta" answers one implicit decision.
  int get _total => math.max(_decisions.length, 1);
  StepDecision? get _decision =>
      _index < _decisions.length ? _decisions[_index] : null;

  /// Row indexes in order: the options and then "Outra resposta".
  List<int> get _order => [
    if (_decision case final d?) ...[
      for (var i = 0; i < d.options.length; i++) i,
    ],
    stepDecisionOtherRow,
  ];

  StepDecisionChoice? _choiceAt(int decision) {
    final d = decision < _decisions.length ? _decisions[decision] : null;
    final saved = ref.read(stepDecisionChoicesProvider)[_key] ?? const [];
    final choice = saved.where((c) => c.decision == decision).firstOrNull;
    return choice != null && choice.fits(d) ? choice : null;
  }

  List<StepDecisionChoice> get _answers => [
    for (var i = 0; i < _total; i++) ?_choiceAt(i),
  ];

  int get _missing => _total - _answers.length;

  /// The row of what is chosen in the current decision, if any.
  int? get _chosenRow {
    final choice = _choiceAt(_index);
    if (choice == null) return null;
    if (choice.isOther) return stepDecisionOtherRow;
    final i = _decision?.options.indexWhere(
      (o) => o.title == choice.option!.title,
    );
    return i == null || i < 0 ? null : i;
  }

  int? get _focusedRow {
    if (_otherField.hasFocus) return stepDecisionOtherRow;
    final i = _rows.indexWhere((n) => n.hasPrimaryFocus);
    return i < 0 ? null : i;
  }

  /// Text fields keep the keys that write and move the caret (R6).
  bool get _typing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool get _isCurrent => mounted && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _options = ref.read(stepDecisionOptionsProvider.notifier);
    _choices = ref.read(stepDecisionChoicesProvider.notifier);
    _opened = ref.read(stepDecisionApplierProvider).stamp(_spec);
    unawaited(_options.generate(_spec, _step));
    if (_state.result case final result? when result.error == null) {
      _showDecisions();
    } else {
      _syncOther();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) return;
    _motionReady = true;
    if (!AppMotion.animate(context)) {
      _sequence.value = 1;
      return;
    }
    unawaited(_sequence.forward());
    _pulse = AnimationController(vsync: this, duration: attentionPulsePeriod);
    _routeAnimation = ModalRoute.of(context)?.animation
      ?..addStatusListener(_onRoute);
  }

  /// The bubble pulses once the modal is in place.
  void _onRoute(AnimationStatus status) {
    if (status.isCompleted) unawaited(_pulse?.forward());
  }

  @override
  void dispose() {
    _advance?.cancel();
    _routeAnimation?.removeStatusListener(_onRoute);
    _options.cancel(_spec.id, _step.id);
    _pulse?.dispose();
    _sequence.dispose();
    _root.dispose();
    for (final node in _rows) {
      node.dispose();
    }
    _otherField.dispose();
    _other.dispose();
    _submit.dispose();
    super.dispose();
  }

  void _onState(StepDecisionState? _, StepDecisionState next) {
    if (next.status != StepDecisionStatus.ready) {
      _keepFocus();
      return;
    }
    // Options that arrive after the opening still come in sequence.
    const first = _firstRowMs / _sequenceMs;
    if (_sequence.value > first) unawaited(_sequence.forward(from: first));
    setState(_showDecisions);
  }

  /// Goes to the first open decision and puts the focus on the list, unless
  /// the person is already writing "Outra resposta".
  void _showDecisions() {
    if (_typing) return;
    final open = [
      for (var i = 0; i < _total; i++)
        if (_choiceAt(i) == null) i,
    ];
    _index = open.firstOrNull ?? _total - 1;
    _syncOther();
    _lastRow = _chosenRow ?? 0;
    _focusList();
  }

  /// The field shows what was written for the current decision.
  void _syncOther() {
    final choice = _choiceAt(_index);
    final other = choice?.isOther ?? false;
    _otherOpen = other;
    _other.text = other ? choice!.text : '';
  }

  /// What had the focus may be gone: the keys must keep working (R6).
  void _keepFocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_isCurrent && !_root.hasFocus) _root.requestFocus();
  });

  void _focusList() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent) return;
      final row = _chosenRow ?? _order.first;
      if (row == stepDecisionOtherRow && _otherOpen) {
        _otherField.requestFocus();
      } else {
        _rows[row].requestFocus();
      }
    });
  }

  void _goTo(int index) {
    _advance?.cancel();
    if (!_isCurrent) return;
    setState(() {
      _phase = StepDecisionPhase.deciding;
      _index = index;
      _syncOther();
      _lastRow = _chosenRow ?? 0;
    });
    _focusList();
    if (_total > 1) _announce('Decisão ${index + 1} de $_total');
  }

  void _announce(String text) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
      assertiveness: Assertiveness.polite,
    ),
  );

  void _nextSoon() {
    _advance?.cancel();
    if (_index + 1 >= _total) return;
    _advance = Timer(stepDecisionAdvanceDelay, () => _goTo(_index + 1));
  }

  void _choose(int row) {
    final decision = _decision;
    if (decision == null || row >= decision.options.length) return;
    _choices.set(
      _key,
      StepDecisionChoice(
        decision: _index,
        question: decision.question,
        option: decision.options[row],
      ),
    );
    _rows[row].requestFocus();
    setState(() {
      _otherOpen = false;
      _lastRow = row;
    });
    _nextSoon();
  }

  void _openOther() {
    _advance?.cancel();
    setState(() {
      _otherOpen = true;
      _lastRow = stepDecisionOtherRow;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent) _otherField.requestFocus();
    });
  }

  /// What is written is the answer already: closing the modal keeps it.
  void _onOther(String text) {
    _advance?.cancel();
    final answer = text.trim();
    if (answer.isEmpty) {
      _choices.remove(_key, _index);
    } else {
      _choices.set(
        _key,
        StepDecisionChoice(
          decision: _index,
          question: _decision?.question ?? '',
          text: answer,
        ),
      );
    }
    setState(() {});
  }

  void _onRowFocus(int row, bool focused) {
    if (focused) _lastRow = row;
    setState(() {});
  }

  void _move(int delta) {
    final order = _order;
    final at = order.indexOf(_focusedRow ?? _lastRow);
    final row = order[(at + delta) % order.length];
    if (row == stepDecisionOtherRow && _otherOpen) {
      _otherField.requestFocus();
    } else {
      _rows[row].requestFocus();
    }
  }

  void _back() {
    if (_phase == StepDecisionPhase.compile) {
      _goTo(_index);
    } else if (_index > 0) {
      _goTo(_index - 1);
    }
  }

  void _close() {
    _advance?.cancel();
    if (mounted) unawaited(Navigator.of(context).maybePop());
  }

  /// The way to the Compilar phase (R9), which [StepDecisionDialog.compileBuilder]
  /// draws. Inside the phase, `Ctrl+Enter` is its primary button.
  void _compile() {
    if (_phase == StepDecisionPhase.compile) {
      _submit.fire();
    } else if (_missing == 0) {
      _advance?.cancel();
      setState(() {
        _phase = StepDecisionPhase.compile;
        _reviewed = _answers;
      });
      _keepFocus();
    }
  }

  var _escalating = false;

  /// "Escalar para Opus" (SPEC-035 R12): the step goes up one rung, in a new
  /// session at its start, and the modal closes.
  Future<void> _escalate() async {
    _advance?.cancel();
    setState(() => _escalating = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final runner = ref.read(specRunnerProvider);
    try {
      await runner.escalate(_spec.id, _step.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _escalating = false);
      messenger?.showAppToast(SnackBar(content: Text('$e')));
    }
  }

  void _openSession() {
    final id = _step.sessionId;
    if (id == null) return;
    _advance?.cancel();
    final alive = ref.read(sessionManagerProvider).isAlive(id);
    final manager = ref.read(sessionManagerProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final draft = stepDecisionDraft(_decisions, _answers);
    Navigator.of(context).pop(true);
    openSession(ref, id, draft: draft);
    if (alive) return;
    // Nothing is sent: the session only comes back to wait for the message.
    unawaited(
      manager.resume(id).catchError((Object e) {
        messenger?.showAppToast(SnackBar(content: Text('$e')));
      }),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    bool on(SingleActivator key) => key.accepts(event, keyboard);
    KeyEventResult run(VoidCallback action) {
      action();
      return KeyEventResult.handled;
    }

    if (_compileKeys.any(on)) return run(_compile);
    if (on(_sessionKey)) return run(_openSession);
    if (on(_closeKey)) return run(_close);
    if (_typing) return _onFieldKey(on);
    if (on(_backKey)) return run(_back);
    if (_phase != StepDecisionPhase.deciding) return KeyEventResult.ignored;

    final digit = _digitOf(event, keyboard);
    if (digit != null) {
      if (digit == stepDecisionOtherRow) return run(_openOther);
      _advance?.cancel();
      return run(() => _choose(digit));
    }
    if (on(_upKey)) return run(() => _moveNow(-1));
    if (on(_downKey)) return run(() => _moveNow(1));
    // A focused button keeps its own Enter.
    final row = _focusedRow;
    if (row != null && _enterKeys.any(on)) {
      return run(
        () => row == stepDecisionOtherRow ? _openOther() : _choose(row),
      );
    }
    return KeyEventResult.ignored;
  }

  void _moveNow(int delta) {
    _advance?.cancel();
    _move(delta);
  }

  /// Keys of the "Outra resposta" field: `Enter` confirms (`Shift+Enter` is a
  /// new line) and `↑` at the start goes back to the options. The message
  /// field of the Compilar phase keeps them all.
  KeyEventResult _onFieldKey(bool Function(SingleActivator) on) {
    if (!_otherField.hasFocus) return KeyEventResult.ignored;
    if (_enterKeys.any(on)) {
      if (_other.text.trim().isNotEmpty) {
        _nextSoon();
      }
      return KeyEventResult.handled;
    }
    final atStart =
        _other.selection.isCollapsed && _other.selection.baseOffset <= 0;
    if (on(_upKey) && atStart && _order.length > 1) {
      _moveNow(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Index of a digit key with no modifier (`Shift+1` is `!`).
  int? _digitOf(KeyEvent event, HardwareKeyboard keyboard) {
    if (event is! KeyDownEvent ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return null;
    }
    final i = _digitKeys.indexWhere((k) => k.contains(event.logicalKey));
    return i < 0 ? null : i;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stepDecisionProvider(_target));
    ref.listen(stepDecisionProvider(_target), _onState);
    ref.watch(stepDecisionChoicesProvider.select((m) => m[_key]));
    final size = MediaQuery.sizeOf(context);
    final number = stepNumber(_step.id);
    final compiling = _phase == StepDecisionPhase.compile;
    return Semantics(
      role: SemanticsRole.dialog,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Decidir a etapa $number da ${_spec.code}',
      child: FocusScope(
        node: _root,
        autofocus: true,
        includeSemantics: false,
        onKeyEvent: _onKey,
        child: Dialog(
          key: const ValueKey('step-decision-dialog'),
          backgroundColor: AppColors.panel,
          insetPadding: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: SessionColors.selectedBorder),
          ),
          child: SizedBox(
            width: math.min(_modalWidth, size.width - 24),
            height: math.min(_modalHeight, size.height - 24),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.text,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StepDecisionHeader(
                    spec: _spec,
                    step: _step,
                    state: state,
                    index: _index,
                    total: _total,
                    pulse: _pulse,
                    onClose: _close,
                    ready: compiling ? stepDecisionReady(_reviewed) : null,
                  ),
                  Expanded(
                    child: compiling
                        ? widget.compileBuilder(context, _compileRequest(state))
                        : _body(state, size),
                  ),
                  if (!compiling)
                    StepDecisionFooter(
                      status: state.status,
                      missing: _missing,
                      otherOpen: _otherOpen,
                      showKeys: size.width >= _keysMinWidth,
                      onRetry: () => _options.retry(_spec, _step),
                      onOther: _openOther,
                      onOpenSession: _sessionAction,
                      onCompile: _compile,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  StepDecisionCompileRequest _compileRequest(StepDecisionState state) =>
      StepDecisionCompileRequest(
        spec: _spec,
        step: _step,
        summary: state.result?.summary ?? '',
        decisions: _decisions,
        choices: _reviewed,
        onBack: _back,
        onChange: _goTo,
        onClose: _close,
        onSubmit: _submit,
        opened: _opened,
        onOpenSession: _sessionAction,
      );

  VoidCallback? get _sessionAction =>
      _step.sessionId == null ? null : _openSession;

  Widget _body(StepDecisionState state, Size size) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _optionsColumn(state)),
      if (size.width > _modalWidth)
        StepDecisionEnter(
          sequence: _sequence,
          startMs: _previewMs,
          totalMs: _sequenceMs,
          child: _previewColumn(state),
        ),
    ],
  );

  Widget _optionsColumn(StepDecisionState state) {
    final decision = state.status == StepDecisionStatus.ready
        ? _decision
        : null;
    final options = decision?.options ?? const <StepDecisionOption>[];
    final chosen = _chosenRow;
    Widget enter(int line, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StepDecisionEnter(
        sequence: _sequence,
        startMs: _firstRowMs + _rowGapMs * line,
        totalMs: _sequenceMs,
        child: child,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'O que fazer',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (decision != null && decision.question.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    decision.question,
                    key: const ValueKey('step-decision-question'),
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
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                role: SemanticsRole.radioGroup,
                label: 'O que fazer',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (ref.watch(pendingEscalationProvider(_target)).value
                        case final rung?) ...[
                      StepDecisionEscalateRow(
                        rung: rung,
                        onTap: _escalating ? null : _escalate,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (state.status == StepDecisionStatus.loading) ...[
                      const StepDecisionGenerating(),
                      const SizedBox(height: 8),
                      const StepDecisionRowsSkeleton(),
                    ],
                    if (state.result?.error case final error?) ...[
                      StepDecisionFailure(reason: error),
                      const SizedBox(height: 8),
                    ],
                    for (final (i, option) in options.indexed)
                      enter(
                        i,
                        StepDecisionOptionRow(
                          key: ValueKey('step-decision-option-${i + 1}'),
                          number: i + 1,
                          total: options.length,
                          option: option,
                          focusNode: _rows[i],
                          chosen: chosen == i,
                          onTap: () => _choose(i),
                          onFocusChange: (f) => _onRowFocus(i, f),
                        ),
                      ),
                    if (state.status != StepDecisionStatus.loading ||
                        _otherOpen)
                      enter(
                        options.length,
                        StepDecisionOtherRow(
                          key: const ValueKey('step-decision-other'),
                          focusNode: _rows[stepDecisionOtherRow],
                          fieldFocus: _otherField,
                          controller: _other,
                          open: _otherOpen,
                          chosen: chosen == stepDecisionOtherRow,
                          onOpen: _openOther,
                          onChanged: _onOther,
                          onFocusChange: (f) =>
                              _onRowFocus(stepDecisionOtherRow, f),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The focused row, or the chosen one, or the last one that had the focus.
  int get _previewRow => _focusedRow ?? _chosenRow ?? _lastRow;

  Widget _previewColumn(StepDecisionState state) {
    final rows =
        ref.watch(specStepsProvider(_spec.workspaceId)).value ??
        const <SpecStep>[];
    final queue = stepsOf(_spec, rows);
    final steps = queue.any((s) => s.id == _step.id) ? queue : [_step];
    final options = state.status == StepDecisionStatus.ready
        ? _decision?.options ?? const <StepDecisionOption>[]
        : const <StepDecisionOption>[];
    final row = _previewRow;
    final option = row < options.length ? options[row] : null;
    final hasAnswer = _otherOpen || option != null;
    return Semantics(
      container: true,
      label: 'Como a etapa fica',
      child: Container(
        key: const ValueKey('step-decision-preview'),
        width: _previewWidth,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(left: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'Como a etapa fica',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                if (hasAnswer)
                  Expanded(
                    child: Text(
                      option == null
                          ? 'outra resposta'
                          : 'opção ${row + 1} · '
                                '${option.kind.label.toLowerCase()}',
                      key: const ValueKey('step-decision-preview-caption'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.quick),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: SingleChildScrollView(
                  key: ValueKey(
                    hasAnswer ? (_index, option == null ? -1 : row) : 'vazio',
                  ),
                  child: hasAnswer
                      ? StepDecisionPreview(
                          option,
                          step: _step,
                          steps: steps,
                          answer: _other.text,
                        )
                      : const Text(
                          'A prévia aparece junto com as opções.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `Ctrl+Enter` inside the Compilar phase.
class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}
