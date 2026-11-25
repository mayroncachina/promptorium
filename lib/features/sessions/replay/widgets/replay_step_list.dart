import 'package:flutter/material.dart';

import '../../../../ui/theme/tokens.dart';
import '../replay_state.dart';
import '../replay_step.dart';
import 'replay_style.dart';

/// Filters, search and the lazy list of steps, grouped by turn (SPEC-082
/// R9, R11).
class ReplayStepList extends StatefulWidget {
  const ReplayStepList({
    super.key,
    required this.steps,
    required this.visible,
    required this.current,
    required this.filter,
    required this.query,
    required this.onFilter,
    required this.onQuery,
    required this.onSelect,
    required this.searchFocus,
    this.file,
    this.root,
  });

  /// Every top-level step.
  final List<ReplayStep> steps;

  /// Indexes of the steps inside the filter, in order.
  final List<int> visible;
  final int current;
  final ReplayFilter filter;
  final String query;
  final ValueChanged<ReplayFilter> onFilter;
  final ValueChanged<String> onQuery;
  final ValueChanged<int> onSelect;
  final FocusNode searchFocus;

  /// File chosen in "Resultado" (the list says so).
  final String? file;
  final String? root;

  static const rowHeight = 27.0;

  @override
  State<ReplayStepList> createState() => _ReplayStepListState();
}

/// A turn header or a step.
typedef _Entry = ({int? turn, int? step});

class _ReplayStepListState extends State<ReplayStepList> {
  final _scroll = ScrollController();
  late final _search = TextEditingController(text: widget.query);
  List<_Entry> _entries = const [];
  Map<int, int> _rowOf = const {};

  @override
  void initState() {
    super.initState();
    _build();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didUpdateWidget(ReplayStepList old) {
    super.didUpdateWidget(old);
    if (!identical(old.visible, widget.visible) ||
        !identical(old.steps, widget.steps) ||
        old.file != widget.file) {
      _build();
    }
    if (old.current != widget.current ||
        !identical(old.visible, widget.visible)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
    if (widget.query != _search.text) _search.text = widget.query;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _build() {
    final out = <_Entry>[];
    final rowOf = <int, int>{};
    final byFile = widget.file != null;
    int? turn;
    for (final i in widget.visible) {
      final s = widget.steps[i];
      if (!byFile && s.turn != turn) {
        turn = s.turn;
        out.add((turn: turn, step: null));
      }
      rowOf[i] = out.length;
      out.add((turn: null, step: i));
    }
    _entries = out;
    _rowOf = rowOf;
  }

  /// Keeps the current step in view.
  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final row = _rowOf[widget.current];
    if (row == null) return;
    final p = _scroll.position;
    final top = row * ReplayStepList.rowHeight;
    final bottom = top + ReplayStepList.rowHeight;
    if (top < p.pixels) {
      _scroll.jumpTo(top.clamp(p.minScrollExtent, p.maxScrollExtent));
    } else if (bottom > p.pixels + p.viewportDimension) {
      _scroll.jumpTo(
        (bottom - p.viewportDimension).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
    }
  }

  String _turnText(int turn) {
    for (final s in widget.steps) {
      if (s.turn == turn && s.kind == ReplayKind.user) {
        return 'T$turn · "${s.target}"';
      }
    }
    return 'T$turn';
  }

  @override
  Widget build(BuildContext context) {
    int count(ReplayFilter f) => widget.steps.where(f.matches).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final f in ReplayFilter.values)
                _FilterChip(
                  key: ValueKey('replay-filter-${f.name}'),
                  label: f == ReplayFilter.all || f != widget.filter
                      ? (f == ReplayFilter.errors && count(f) > 0
                            ? '${f.label} ${count(f)}'
                            : f.label)
                      : '${f.label} ${count(f)}',
                  on: f == widget.filter,
                  onTap: () => widget.onFilter(f),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
          child: SizedBox(
            height: 28,
            child: TextField(
              key: const ValueKey('replay-search'),
              controller: _search,
              focusNode: widget.searchFocus,
              onChanged: widget.onQuery,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Buscar arquivo ou comando',
                hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                prefixIcon: Icon(Icons.search, size: 14),
                prefixIconConstraints: BoxConstraints(minWidth: 26),
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
        if (widget.file != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: Text(
              'Passos que tocaram em ${baseName(widget.file!)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        Expanded(
          child: _entries.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum passo neste filtro.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('replay-step-list'),
                  controller: _scroll,
                  itemExtent: ReplayStepList.rowHeight,
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    if (e.turn != null) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Text(
                          _turnText(e.turn!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    final s = widget.steps[e.step!];
                    return _StepRow(
                      key: ValueKey('replay-step-${s.index}'),
                      step: s,
                      selected: s.index == widget.current,
                      showTurn: widget.file != null,
                      onTap: () => widget.onSelect(s.index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: on ? SessionColors.selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? AppColors.text : AppColors.textSecondary,
          ),
        ),
      ),
    ),
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.step,
    required this.selected,
    required this.showTurn,
    required this.onTap,
  });

  final ReplayStep step;
  final bool selected;
  final bool showTurn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = step;
    final problem = s.isProblem;
    final label = replayStepLabel(s);
    final name = s.tool == null ? null : s.verb;
    final via = s.via ?? '';
    return Semantics(
      button: true,
      selected: selected,
      label: replaySemanticValue(s, 0).replaceFirst(' de 0', ''),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 8, right: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.amberTint : null,
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.amber : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${s.index + 1}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ReplayKindBadge(s, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (name != null) ...[
                        TextSpan(
                          text: '$name ',
                          style: TextStyle(
                            color: problem ? AppColors.red : AppColors.text,
                          ),
                        ),
                        TextSpan(
                          text: label.substring(name.length + 1),
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11.5,
                            color: problem
                                ? AppColors.red
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (via.isNotEmpty)
                          TextSpan(
                            text: ' · $via',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ] else
                        TextSpan(
                          text: label,
                          style: TextStyle(
                            color: problem
                                ? AppColors.red
                                : AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                showTurn ? 'T${s.turn}' : formatDurationShort(s.duration),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
