import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../timeline_provider.dart';
import '../widgets/session_style.dart';
import '../widgets/timeline_view.dart' show sessionEditDiffs;
import 'replay_data.dart';
import 'replay_state.dart';
import 'replay_step.dart';
import 'widgets/replay_scrubber.dart';
import 'widgets/replay_side_panel.dart';
import 'widgets/replay_step_list.dart';
import 'widgets/replay_step_panel.dart';
import 'widgets/replay_style.dart';

/// Geometry of the scrubber per steps list (R11: once per session).
final _axisOf = Expando<ReplayAxis>('replay axis');

/// Per-steps caches that don't depend on the cursor (R11: moving the
/// cursor must not walk the whole session again).
final _resultsOf = Expando<List<ReplayResultFile>>('replay results');
final _turnTextOf = Expando<Map<int, String>>('replay turn text');

/// "Replay" tab of a finished session (SPEC-082): the draggable timeline,
/// the steps, the step under the cursor and the state at that point.
class ReplayView extends ConsumerStatefulWidget {
  const ReplayView({
    super.key,
    required this.session,
    required this.onOpenInTimeline,
  });

  final Session session;

  /// "Abrir na Timeline" (R5): the tab changes, focused on the step.
  final ValueChanged<ReplayStep> onOpenInTimeline;

  @override
  ConsumerState<ReplayView> createState() => _ReplayViewState();
}

/// Speeds of "tocar" (P6).
const replaySpeeds = [1, 2, 4];

class _ReplayViewState extends ConsumerState<ReplayView> {
  final _focus = FocusNode(debugLabel: 'replay');
  final _searchFocus = FocusNode(debugLabel: 'replay search');
  Timer? _timer;
  var _speed = 1;
  var _sideTab = 0;

  /// The center shows the final diff of the chosen file (R8) until the
  /// cursor moves.
  var _finalDiff = false;

  /// Bumped to open "Arquivo neste ponto" of the step (from "Quem
  /// escreveu?").
  ReplayStep? _openFileAt;

  String get _id => widget.session.id;
  String get _root => widget.session.worktreePath;

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  ReplayCursor get _cursor => ref.read(replayCursorProvider(_id));

  void _setCursor(ReplayCursor c) =>
      ref.read(replayCursorProvider(_id).notifier).set(c);

  List<ReplayStep> get _steps =>
      replayStepsOf(ref.read(sessionTimelineProvider(_id)), _root);

  int _currentOf(List<ReplayStep> steps, ReplayCursor c) {
    if (steps.isEmpty) return 0;
    return (c.index ?? steps.length - 1).clamp(0, steps.length - 1);
  }

  /// Last visible list, reused while the steps and the filter are the same
  /// (R11).
  List<ReplayStep>? _visSteps;
  (ReplayFilter, String, String?)? _visKey;
  List<int> _vis = const [];

  List<int> _visibleOf(List<ReplayStep> steps, ReplayCursor c) {
    final key = (c.filter, c.query, c.file);
    if (identical(steps, _visSteps) && key == _visKey) return _vis;
    _visSteps = steps;
    _visKey = key;
    return _vis = List.unmodifiable([
      for (final s in steps)
        if (replayStepVisible(
          s,
          filter: c.filter,
          query: c.query,
          file: c.file,
          root: _root,
        ))
          s.index,
    ]);
  }

  /// Moves the cursor to top-level step [i] (closing an open subagent
  /// elsewhere).
  void _seek(int i, {bool keepFinal = false}) {
    final c = _cursor;
    _setCursor(
      c.copyWith(
        index: () => i,
        child: () => null,
        openSubagent: () => c.openSubagent == i ? i : null,
      ),
    );
    if (!keepFinal && _finalDiff) setState(() => _finalDiff = false);
  }

  /// One step forward / back among the visible ones; inside an open
  /// subagent, through its steps (P7).
  bool _move(int delta) {
    final steps = _steps;
    if (steps.isEmpty) return false;
    final c = _cursor;
    final cur = _currentOf(steps, c);
    if (c.openSubagent == cur) {
      final kids = steps[cur].children;
      final pos = (c.child ?? -1) + delta;
      if (pos >= -1 && pos < kids.length) {
        _setCursor(c.copyWith(child: () => pos < 0 ? null : pos));
        if (_finalDiff) setState(() => _finalDiff = false);
        return true;
      }
    }
    final vis = _visibleOf(steps, c);
    int? next;
    if (delta > 0) {
      for (final i in vis) {
        if (i > cur) {
          next = i;
          break;
        }
      }
    } else {
      for (final i in vis.reversed) {
        if (i < cur) {
          next = i;
          break;
        }
      }
    }
    if (next == null) return false;
    _seek(next);
    return true;
  }

  /// Shift+← →: the start of the next / this-or-previous turn (R4).
  void _moveTurn(int delta) {
    final steps = _steps;
    if (steps.isEmpty) return;
    final c = _cursor;
    final cur = _currentOf(steps, c);
    final vis = _visibleOf(steps, c);
    final turn = steps[cur].turn;
    int? target;
    if (delta > 0) {
      target = vis.where((i) => steps[i].turn > turn).firstOrNull;
    } else {
      final startOfThis = vis.where((i) => steps[i].turn == turn).firstOrNull;
      if (startOfThis != null && startOfThis < cur) {
        target = startOfThis;
      } else {
        final prevTurn = vis.where((i) => steps[i].turn < turn).lastOrNull;
        if (prevTurn != null) {
          final t = steps[prevTurn].turn;
          target = vis.where((i) => steps[i].turn == t).firstOrNull;
        }
      }
    }
    if (target != null) _seek(target);
  }

  void _edge(bool end) {
    final steps = _steps;
    final vis = _visibleOf(steps, _cursor);
    if (vis.isEmpty) return;
    _seek(end ? vis.last : vis.first);
  }

  /// "erro anterior" / "próximo erro" (R4).
  void _jumpError(int delta) {
    final steps = _steps;
    final c = _cursor;
    final cur = _currentOf(steps, c);
    final errs = [
      for (final i in _visibleOf(steps, c))
        if (steps[i].isProblem) i,
    ];
    final next = delta > 0
        ? errs.where((i) => i > cur).firstOrNull
        : errs.where((i) => i < cur).lastOrNull;
    if (next != null) _seek(next);
  }

  void _togglePlay() {
    if (_timer != null) {
      _stop();
      return;
    }
    final steps = _steps;
    final vis = _visibleOf(steps, _cursor);
    // At the end, playing starts over.
    if (vis.isNotEmpty && _currentOf(steps, _cursor) >= vis.last) {
      _seek(vis.first);
    }
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: 1000 ~/ _speed),
      (_) => _tick(),
    );
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() {});
  }

  /// One step per tick; stops at the end or at an error (P6).
  void _tick() {
    if (!mounted) return _stop();
    if (!_move(1)) return _stop();
    final steps = _steps;
    final c = _cursor;
    final cur = _currentOf(steps, c);
    final s = c.openSubagent == cur && c.child != null
        ? steps[cur].children[c.child!]
        : steps[cur];
    if (s.isProblem) _stop();
  }

  void _setSpeed(int s) {
    setState(() => _speed = s);
    if (_timer != null) _start();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowDown) {
      shift && k == LogicalKeyboardKey.arrowRight ? _moveTurn(1) : _move(1);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowUp) {
      shift && k == LogicalKeyboardKey.arrowLeft ? _moveTurn(-1) : _move(-1);
    } else if (k == LogicalKeyboardKey.home) {
      _edge(false);
    } else if (k == LogicalKeyboardKey.end) {
      _edge(true);
    } else if (k == LogicalKeyboardKey.space && e is KeyDownEvent) {
      _togglePlay();
    } else if (k == LogicalKeyboardKey.escape && _cursor.openSubagent != null) {
      _setCursor(_cursor.copyWith(openSubagent: () => null, child: () => null));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _goTo(ReplayStep step, {bool showFile = false}) {
    final top = step.parent ?? step;
    final c = _cursor;
    // Leaves a filter that would hide the step.
    final hidden = !replayStepVisible(
      top,
      filter: c.filter,
      query: c.query,
      file: c.file,
      root: _root,
    );
    _setCursor(
      ReplayCursor(
        index: top.index,
        child: step.parent == null ? null : step.index,
        openSubagent: step.parent == null ? null : top.index,
        filter: hidden ? ReplayFilter.all : c.filter,
        query: hidden ? '' : c.query,
        file: c.file,
      ),
    );
    setState(() {
      _finalDiff = false;
      _openFileAt = showFile ? step : null;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(sessionTimelineProvider(_id));
    final c = ref.watch(replayCursorProvider(_id));
    if (snap.loading) {
      return const Center(
        child: Text(
          'Carregando a sessão…',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    final steps = replayStepsOf(snap, _root);
    if (steps.isEmpty) {
      return const Center(
        child: Text(
          'Esta sessão não tem passos para rever.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    final axis = _axisOf[steps] ??= ReplayAxis(steps);
    final cur = _currentOf(steps, c);
    final vis = _visibleOf(steps, c);
    final visSet = vis.length == steps.length ? null : vis.toSet();
    final top = steps[cur];
    final open = c.openSubagent == cur && top.children.isNotEmpty;
    final step = open && c.child != null && c.child! < top.children.length
        ? top.children[c.child!]
        : top;
    final diffs = sessionEditDiffs(snap, _root);
    final state = replayStateAt(
      steps,
      cur,
      context: snap.timeline.contextTokens,
    );
    final local = _resultsOf[steps] ??= replayResultFiles(steps, _root);
    final results = _sideTab == 1
        ? (ref.watch(replayResultFilesProvider(_id)).value ?? local)
        : local;
    final turnText = _turnTextOf[steps] ??= {
      for (final e in turnStarts(steps).entries)
        if (e.value != null) e.key: e.value!.target,
    };

    final toolbar = _Toolbar(
      playing: _timer != null,
      speed: _speed,
      step: step,
      total: steps.length,
      filterInfo: c.file != null
          ? 'só ${baseName(c.file!)}: ${vis.indexOf(cur) + 1} de ${vis.length}'
          : c.filter != ReplayFilter.all
          ? '${c.filter.label}: ${vis.indexOf(cur) + 1} de ${vis.length}'
          : null,
      file: c.file,
      onClearFile: () => _setCursor(c.copyWith(file: () => null)),
      onFirst: () => _edge(false),
      onPrev: () => _move(-1),
      onPlay: _togglePlay,
      onNext: () => _move(1),
      onLast: () => _edge(true),
      onSpeed: _setSpeed,
      onPrevError: () => _jumpError(-1),
      onNextError: () => _jumpError(1),
    );

    final center = _finalDiff && c.file != null
        ? ReplayFinalDiffView(
            key: ValueKey('replay-final-${c.file}'),
            sessionId: _id,
            path: c.file!,
            steps: steps,
            root: _root,
            onGoTo: _goTo,
          )
        : ReplayStepPanel(
            key: ValueKey('replay-panel-$_id'),
            sessionId: _id,
            step: step,
            steps: steps,
            diffs: diffs,
            root: _root,
            openFileAt: _openFileAt,
            onOpenInTimeline: () => widget.onOpenInTimeline(step),
            onSeek: _seek,
            onOpenSubagent: (child) => _setCursor(
              c.copyWith(openSubagent: () => cur, child: () => child),
            ),
          );

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (!_searchFocus.hasFocus) _focus.requestFocus();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            toolbar,
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 2),
              child: ReplayScrubber(
                key: ValueKey('replay-scrubber-$_id'),
                axis: axis,
                current: cur,
                visible: visSet?.contains,
                root: _root,
                turnText: turnText,
                onSeek: (i) {
                  _focus.requestFocus();
                  _seek(i);
                },
              ),
            ),
            if (open)
              ReplaySubagentLane(
                step: top,
                child: c.child,
                onSeek: (i) => _setCursor(c.copyWith(child: () => i)),
                onClose: () => _setCursor(
                  c.copyWith(openSubagent: () => null, child: () => null),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final narrow = box.maxWidth < 980;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: narrow ? 250 : 300,
                        child: ReplayStepList(
                          steps: steps,
                          visible: vis,
                          current: cur,
                          filter: c.filter,
                          query: c.query,
                          file: c.file,
                          root: _root,
                          searchFocus: _searchFocus,
                          onFilter: (f) {
                            _setCursor(c.copyWith(filter: f));
                            _focus.requestFocus();
                          },
                          onQuery: (q) => _setCursor(c.copyWith(query: q)),
                          onSelect: (i) {
                            _focus.requestFocus();
                            _seek(i);
                          },
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: center),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: narrow ? 240 : 280,
                        child: ReplaySidePanel(
                          state: state,
                          steps: steps,
                          current: cur,
                          results: results,
                          tab: _sideTab,
                          root: _root,
                          file: c.file,
                          visibleCount: vis.length,
                          onTab: (t) => setState(() => _sideTab = t),
                          onSeek: (i) {
                            _focus.requestFocus();
                            _seek(i);
                          },
                          onFile: (path) {
                            _setCursor(c.copyWith(file: () => path));
                            setState(() => _finalDiff = path != null);
                            _focus.requestFocus();
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.playing,
    required this.speed,
    required this.step,
    required this.total,
    required this.filterInfo,
    required this.file,
    required this.onClearFile,
    required this.onFirst,
    required this.onPrev,
    required this.onPlay,
    required this.onNext,
    required this.onLast,
    required this.onSpeed,
    required this.onPrevError,
    required this.onNextError,
  });

  final bool playing;
  final int speed;
  final ReplayStep step;
  final int total;
  final String? filterInfo;
  final String? file;
  final VoidCallback onClearFile;
  final VoidCallback onFirst;
  final VoidCallback onPrev;
  final VoidCallback onPlay;
  final VoidCallback onNext;
  final VoidCallback onLast;
  final ValueChanged<int> onSpeed;
  final VoidCallback onPrevError;
  final VoidCallback onNextError;

  Widget _icon(
    String key,
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool amber = false,
  }) {
    return Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        label: tip,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: amber ? AppColors.amber : AppColors.panel,
              border: Border.all(
                color: amber ? AppColors.amber : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 17,
              color: amber ? AppColors.onAmber : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = step.parent ?? step;
    final no = step.parent == null
        ? '${step.index + 1}'
        : '${top.index + 1}.${step.index + 1}';
    final info = [
      'T${step.turn}',
      if (step.at != null) clock(step.at),
      if (step.duration != null) formatDurationShort(step.duration),
      ?filterInfo,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          _icon('replay-first', Icons.skip_previous, 'Início (Home)', onFirst),
          const SizedBox(width: 4),
          _icon(
            'replay-prev',
            Icons.chevron_left,
            'Passo anterior (←)',
            onPrev,
          ),
          const SizedBox(width: 4),
          _icon(
            'replay-play',
            playing ? Icons.pause : Icons.play_arrow,
            playing ? 'Pausar (Espaço)' : 'Tocar (Espaço)',
            onPlay,
            amber: true,
          ),
          const SizedBox(width: 4),
          _icon(
            'replay-next',
            Icons.chevron_right,
            'Próximo passo (→)',
            onNext,
          ),
          const SizedBox(width: 4),
          _icon('replay-last', Icons.skip_next, 'Fim (End)', onLast),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in replaySpeeds)
                  Semantics(
                    button: true,
                    selected: s == speed,
                    label: 'Velocidade $s×',
                    child: InkWell(
                      key: ValueKey('replay-speed-$s'),
                      onTap: () => onSpeed(s),
                      child: Container(
                        height: 28,
                        width: 32,
                        alignment: Alignment.center,
                        color: s == speed ? SessionColors.selectedBg : null,
                        child: Text(
                          '$s×',
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: s == speed
                                ? AppColors.text
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Passo $no de $total',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  $info',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
              key: const ValueKey('replay-position'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
            ),
          ),
          if (file != null) ...[
            InkWell(
              key: const ValueKey('replay-clear-file'),
              onTap: onClearFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.amber),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'filtro: ${baseName(file!)} ×',
                  style: const TextStyle(fontSize: 11, color: AppColors.amber),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SmallButton(
            key: const ValueKey('replay-prev-error'),
            label: '← erro anterior',
            color: AppColors.red,
            border: SessionColors.stopBorder,
            height: 28,
            onTap: onPrevError,
          ),
          const SizedBox(width: 6),
          SmallButton(
            key: const ValueKey('replay-next-error'),
            label: 'próximo erro →',
            color: AppColors.red,
            border: SessionColors.stopBorder,
            height: 28,
            onTap: onNextError,
          ),
        ],
      ),
    );
  }
}

/// Whether the replay of a session can open (R1): not while the agent is
/// working on it (an idle process waiting for the next message counts as
/// finished).
bool replayAvailable(SessionStatus status, {required bool alive}) =>
    !(alive &&
        (status == SessionStatus.running ||
            status == SessionStatus.waitingApproval));
