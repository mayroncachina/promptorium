import 'package:flutter/material.dart';

import '../../core/text/line_diff.dart';
import '../theme/tokens.dart';

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
  });

  final List<DiffRow> rows;
  final bool muted;
  final int maxLines;
  final int? collapseSame;
  final bool scrollable;

  @override
  State<DiffView> createState() => _DiffViewState();
}

/// A row, or a fold of [count] unchanged rows starting at [start].
typedef _Entry = ({DiffRow? row, int start, int count});

class _DiffViewState extends State<DiffView> {
  final Set<int> _unfolded = {};
  bool _all = false;

  @override
  void didUpdateWidget(DiffView old) {
    super.didUpdateWidget(old);
    if (!identical(old.rows, widget.rows) &&
        old.rows.length != widget.rows.length) {
      _unfolded.clear();
    }
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

  Widget _line(DiffRow r, bool numbers) {
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
    return Semantics(
      container: true,
      label: '$what${r.line == null ? '' : ', linha ${r.line}'}: ${r.text}',
      excludeSemantics: true,
      child: Container(
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
              child: Text(
                r.text,
                style: mono.copyWith(
                  color: muted ? AppColors.textSecondary : AppColors.text,
                ),
              ),
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
      return e.row == null ? _fold(e) : _line(e.row!, numbers);
    }

    final count = shown.length + (more == null ? 0 : 1);
    if (widget.scrollable) {
      return ListView.builder(
        key: const ValueKey('diff-view-list'),
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
