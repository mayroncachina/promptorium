import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/text/line_diff.dart';
import '../theme/tokens.dart';
import 'numbered_text_view.dart';

/// Line diff with the sign in its own column (separated from the text by a
/// rule, so `-` is not taken for a markdown list), the file position and an
/// accessible label per line (SPEC-026 R9).
///
/// [muted]: neutral colors, no background or green / red sign (denied edit,
/// R4). [maxLines]: lines shown before "Mostrar as outras N linhas" (R10).
/// [collapseSame]: runs of unchanged lines longer than this fold into
/// "N linhas sem mudança" (R7). [scrollable]: lazily built list (dialog);
/// otherwise a column sized by its content (cards).
class DiffView extends StatefulWidget {
  const DiffView({
    super.key,
    required this.rows,
    this.muted = false,
    this.maxLines = 400,
    this.collapseSame,
    this.scrollable = false,
    this.marks = const {},
    this.currentRow,
  });

  final List<DiffRow> rows;
  final bool muted;
  final int maxLines;
  final int? collapseSame;
  final bool scrollable;

  /// Search marks by row index (SPEC-058 R5).
  final Map<int, List<LineMark>> marks;

  /// Row of the current search match, scrolled into view.
  final int? currentRow;

  @override
  State<DiffView> createState() => _DiffViewState();
}

/// A row, or a fold of [count] unchanged rows starting at [start].
typedef _Entry = ({DiffRow? row, int start, int count});

class _DiffViewState extends State<DiffView> {
  final Set<int> _unfolded = {};
  bool _all = false;
  final _scroll = ScrollController();
  final _currentKey = GlobalKey(debugLabel: 'current diff match');

  @override
  void initState() {
    super.initState();
    if (widget.currentRow != null) _reveal();
  }

  @override
  void didUpdateWidget(DiffView old) {
    super.didUpdateWidget(old);
    if (!identical(old.rows, widget.rows) &&
        old.rows.length != widget.rows.length) {
      _unfolded.clear();
    }
    if (widget.currentRow != null &&
        (widget.currentRow != old.currentRow ||
            !identical(widget.marks, old.marks))) {
      _reveal();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the current match into view (the list is lazy: an estimate
  /// first when its row is not built).
  void _reveal([int tries = 0]) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _currentKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: .3);
        return;
      }
      final row = widget.currentRow;
      if (row == null || !_scroll.hasClients || tries >= 3) return;
      final p = _scroll.position;
      p.jumpTo(
        (row * 19.2 - p.viewportDimension * .3).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
      _reveal(tries + 1);
    });
  }

  List<_Entry> _entries() {
    final rows = widget.rows;
    final n = widget.collapseSame;
    final out = <_Entry>[];
    var i = 0;
    while (i < rows.length) {
      if (n == null || rows[i].op != DiffOp.same) {
        out.add((row: rows[i], start: i, count: 1));
        i++;
        continue;
      }
      var j = i;
      while (j < rows.length && rows[j].op == DiffOp.same) {
        j++;
      }
      // Keep one line of context next to each change.
      final keepTop = i == 0 ? 0 : 1;
      final keepBottom = j == rows.length ? 0 : 1;
      final hidden = (j - i) - keepTop - keepBottom;
      if (j - i > n && hidden > 0 && !_unfolded.contains(i + keepTop)) {
        for (var k = i; k < i + keepTop; k++) {
          out.add((row: rows[k], start: k, count: 1));
        }
        out.add((row: null, start: i + keepTop, count: hidden));
        for (var k = j - keepBottom; k < j; k++) {
          out.add((row: rows[k], start: k, count: 1));
        }
      } else {
        for (var k = i; k < j; k++) {
          out.add((row: rows[k], start: k, count: 1));
        }
      }
      i = j;
    }
    return out;
  }

  Widget _fold(_Entry e) {
    final label = e.count == 1
        ? '1 linha sem mudança'
        : '${e.count} linhas sem mudança';
    return Container(
      key: ValueKey('diff-fold-${e.start}'),
      color: AppColors.surfaceRaised,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '± $label',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textDisabled,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'Mostrar $label',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('diff-unfold-${e.start}'),
              onTap: () => setState(() => _unfolded.add(e.start)),
              child: const Text(
                'Mostrar',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.amber,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.amber,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(DiffRow r, bool numbers, [int? index]) {
    final marks = index == null ? null : widget.marks[index];
    final muted = widget.muted;
    final (bg, sign, signColor, what) = switch (r.op) {
      DiffOp.add => (
        muted ? Colors.transparent : SessionColors.addBg,
        '+',
        muted ? AppColors.textDisabled : AppColors.teal,
        'linha adicionada',
      ),
      DiffOp.del => (
        muted ? Colors.transparent : SessionColors.delBg,
        '-',
        muted ? AppColors.textDisabled : AppColors.red,
        'linha removida',
      ),
      DiffOp.same => (
        Colors.transparent,
        ' ',
        AppColors.textDisabled,
        'sem mudança',
      ),
    };
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      height: 1.6,
    );
    final textStyle = mono.copyWith(
      color: muted ? AppColors.textSecondary : AppColors.text,
    );
    return Semantics(
      container: true,
      label: '$what${r.line == null ? '' : ', linha ${r.line}'}: ${r.text}',
      excludeSemantics: true,
      child: Container(
        key: index != null && index == widget.currentRow ? _currentKey : null,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (numbers) ...[
              SizedBox(
                width: 30,
                child: Text(
                  r.line == null ? '' : '${r.line}',
                  textAlign: TextAlign.right,
                  style: mono.copyWith(color: AppColors.textDisabled),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              width: 16,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border)),
              ),
              child: Text(
                sign,
                style: mono.copyWith(
                  color: signColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: marks == null
                  ? Text(r.text, style: textStyle)
                  : Text.rich(markedSpan(r.text, marks), style: textStyle),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final numbers = widget.rows.any((r) => r.line != null);
    final visibleLines = entries.where((e) => e.row != null).length;
    final limit = _all ? visibleLines : widget.maxLines;
    final shown = <_Entry>[];
    var lines = 0;
    for (final e in entries) {
      if (e.row != null) {
        if (lines >= limit) break;
        lines++;
      }
      shown.add(e);
    }
    final rest = visibleLines - lines;
    final more = rest <= 0
        ? null
        : Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('diff-show-more'),
                onPressed: () => setState(() => _all = true),
                child: Text(
                  rest == 1
                      ? 'Mostrar a outra linha'
                      : 'Mostrar as outras $rest linhas',
                  style: const TextStyle(fontSize: 12, color: AppColors.amber),
                ),
              ),
            ),
          );
    Widget item(int i) {
      if (i == shown.length) return more!;
      final e = shown[i];
      return e.row == null ? _fold(e) : _line(e.row!, numbers, e.start);
    }

    final count = shown.length + (more == null ? 0 : 1);
    if (widget.scrollable) {
      return ListView.builder(
        key: const ValueKey('diff-view-list'),
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: count,
        itemBuilder: (_, i) => item(i),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < count; i++) item(i)],
    );
  }
}

/// One line of [SideBySideDiffView]: the old line on the left, the new one
/// on the right; a side is null where the other has a line it lacks.
/// [leftIndex] / [rightIndex] are the positions in the [DiffRow] list.
typedef SidePair = ({
  DiffRow? left,
  int? leftNo,
  int? leftIndex,
  DiffRow? right,
  int? rightNo,
  int? rightIndex,
});

/// [rows] side by side (SPEC-058 R6): unchanged lines on both sides, a run
/// of removed lines next to the run of added lines that follows it, the
/// shorter side padded. Old numbers of unchanged lines come from the new
/// ones minus the lines added so far.
List<SidePair> sideBySide(List<DiffRow> rows) {
  final out = <SidePair>[];
  var delta = 0; // added − removed so far
  var i = 0;
  while (i < rows.length) {
    final r = rows[i];
    if (r.op == DiffOp.same) {
      out.add((
        left: r,
        leftNo: r.line == null ? null : r.line! - delta,
        leftIndex: i,
        right: r,
        rightNo: r.line,
        rightIndex: i,
      ));
      i++;
      continue;
    }
    final dels = <int>[], adds = <int>[];
    while (i < rows.length && rows[i].op == DiffOp.del) {
      dels.add(i++);
    }
    while (i < rows.length && rows[i].op == DiffOp.add) {
      adds.add(i++);
    }
    for (var k = 0; k < math.max(dels.length, adds.length); k++) {
      final d = k < dels.length ? dels[k] : null;
      final a = k < adds.length ? adds[k] : null;
      out.add((
        left: d == null ? null : rows[d],
        leftNo: d == null ? null : rows[d].line,
        leftIndex: d,
        right: a == null ? null : rows[a],
        rightNo: a == null ? null : rows[a].line,
        rightIndex: a,
      ));
    }
    delta += adds.length - dels.length;
  }
  return out;
}

/// Changed runs ("trechos") of [rows]: groups of added / removed lines.
int diffHunks(List<DiffRow> rows) {
  var n = 0;
  var inside = false;
  for (final r in rows) {
    final changed = r.op != DiffOp.same;
    if (changed && !inside) n++;
    inside = changed;
  }
  return n;
}

/// The new-file line of the first change of [rows] (SPEC-058 R6: "Abrir no
/// Código" goes there); null when the rows carry no positions.
int? firstChangedLine(List<DiffRow> rows) {
  var delta = 0;
  for (final r in rows) {
    switch (r.op) {
      case DiffOp.same:
        continue;
      case DiffOp.add:
        return r.line;
      case DiffOp.del:
        return r.line == null ? null : r.line! + delta;
    }
  }
  return null;
}

/// Diagonal lines that fill the side of a [SideBySideDiffView] with no line.
class _Hatch extends CustomPainter {
  const _Hatch();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Hatch old) => false;
}

/// Diff with the old text on the left and the new on the right, lines
/// aligned and the gaps hatched (SPEC-058 R6). Lazily built; without [wrap]
/// both sides scroll sideways together.
class SideBySideDiffView extends StatefulWidget {
  const SideBySideDiffView({
    super.key,
    required this.rows,
    this.muted = false,
    this.wrap = false,
    this.marks = const {},
    this.currentRow,
  });

  final List<DiffRow> rows;
  final bool muted;
  final bool wrap;

  /// Search marks by row index (R5).
  final Map<int, List<LineMark>> marks;
  final int? currentRow;

  static const lineHeight = 20.0;

  @override
  State<SideBySideDiffView> createState() => _SideBySideDiffViewState();
}

class _SideBySideDiffViewState extends State<SideBySideDiffView> {
  final _v = ScrollController();
  final _h = ScrollController();
  final _currentKey = GlobalKey(debugLabel: 'current side match');
  late List<SidePair> _pairs = sideBySide(widget.rows);

  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12.5,
    height: SideBySideDiffView.lineHeight / 12.5,
  );

  @override
  void initState() {
    super.initState();
    if (widget.currentRow != null) _reveal();
  }

  @override
  void didUpdateWidget(SideBySideDiffView old) {
    super.didUpdateWidget(old);
    if (!identical(old.rows, widget.rows)) _pairs = sideBySide(widget.rows);
    if (widget.currentRow != null &&
        (widget.currentRow != old.currentRow ||
            !identical(widget.marks, old.marks))) {
      _reveal();
    }
  }

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  void _reveal([int tries = 0]) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _currentKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: .3);
        return;
      }
      final row = widget.currentRow;
      if (row == null || !_v.hasClients || tries >= 3) return;
      final at = _pairs.indexWhere(
        (p) => p.leftIndex == row || p.rightIndex == row,
      );
      if (at < 0) return;
      final p = _v.position;
      p.jumpTo(
        (at * SideBySideDiffView.lineHeight - p.viewportDimension * .3).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
      _reveal(tries + 1);
    });
  }

  Widget _side(
    DiffRow? r,
    int? no,
    int? index, {
    required bool left,
    required bool numbers,
  }) {
    if (r == null) {
      return const CustomPaint(
        painter: _Hatch(),
        child: SizedBox(height: SideBySideDiffView.lineHeight),
      );
    }
    final muted = widget.muted;
    final bg = switch (r.op) {
      DiffOp.same => Colors.transparent,
      _ when muted => Colors.transparent,
      DiffOp.add => SessionColors.addBg,
      DiffOp.del => SessionColors.delBg,
    };
    final what = switch (r.op) {
      DiffOp.add => 'linha adicionada',
      DiffOp.del => 'linha removida',
      DiffOp.same => 'sem mudança',
    };
    final marks = index == null ? null : widget.marks[index];
    final style = _mono.copyWith(
      color: muted ? AppColors.textSecondary : AppColors.text,
    );
    return Semantics(
      container: true,
      label:
          '${left ? 'antes' : 'depois'}, $what'
          '${no == null ? '' : ', linha $no'}: ${r.text}',
      excludeSemantics: true,
      child: Container(
        color: bg,
        constraints: const BoxConstraints(
          minHeight: SideBySideDiffView.lineHeight,
        ),
        padding: const EdgeInsets.only(left: 8, right: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (numbers) ...[
              SizedBox(
                width: 40,
                child: Text(
                  no == null ? '' : '$no',
                  textAlign: TextAlign.right,
                  style: _mono.copyWith(color: ReviewColors.lineNumber),
                ),
              ),
              const SizedBox(width: 14),
            ] else
              const SizedBox(width: 4),
            Expanded(
              child: marks == null
                  ? Text(r.text, style: style, softWrap: widget.wrap)
                  : Text.rich(
                      markedSpan(r.text, marks),
                      style: style,
                      softWrap: widget.wrap,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pair(int i, bool numbers) {
    final p = _pairs[i];
    final current = widget.currentRow;
    final isCurrent =
        current != null && (p.leftIndex == current || p.rightIndex == current);
    return IntrinsicHeight(
      key: isCurrent ? _currentKey : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _side(
              p.left,
              p.leftNo,
              p.leftIndex,
              left: true,
              numbers: numbers,
            ),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: _side(
              p.right,
              p.rightNo,
              p.rightIndex,
              left: false,
              numbers: numbers,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heads() {
    Widget head(String label) => Expanded(
      child: Container(
        height: 30,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 12),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .8,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          head('ANTES'),
          const SizedBox(
            height: 30,
            child: VerticalDivider(width: 1, color: AppColors.border),
          ),
          head('DEPOIS'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final numbers = widget.rows.any((r) => r.line != null);
    Widget table(double? width) {
      final list = ListView.builder(
        key: const ValueKey('side-by-side-diff'),
        controller: _v,
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: _pairs.length,
        itemBuilder: (_, i) => _pair(i, numbers),
      );
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heads(),
          Expanded(child: list),
        ],
      );
      return width == null ? body : SizedBox(width: width, child: body);
    }

    if (widget.wrap) return Scrollbar(controller: _v, child: table(null));
    return LayoutBuilder(
      builder: (context, c) {
        final longest = widget.rows.fold<int>(
          0,
          (m, r) => math.max(m, r.text.length),
        );
        final tp = TextPainter(
          text: TextSpan(text: '0' * 10, style: _mono),
          textDirection: TextDirection.ltr,
        )..layout();
        final char = tp.width / 10;
        tp.dispose();
        final half = math.max(
          c.maxWidth / 2,
          8 + 40 + 14 + longest * char + 24,
        );
        return Scrollbar(
          controller: _v,
          notificationPredicate: (n) => n.depth == 1,
          child: Scrollbar(
            controller: _h,
            child: SingleChildScrollView(
              controller: _h,
              scrollDirection: Axis.horizontal,
              child: table(half * 2 + 1),
            ),
          ),
        );
      },
    );
  }
}
