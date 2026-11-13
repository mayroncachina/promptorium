import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/tokens.dart';

/// One occurrence of a search in [NumberedTextView.lines]: [line] is the
/// index in the list, [start]..[end] the characters.
typedef TextMatch = ({int line, int start, int end});

/// Occurrences of [query] in [lines], ignoring case (SPEC-058 R5).
List<TextMatch> findMatches(List<String> lines, String query) {
  if (query.isEmpty) return const [];
  final q = query.toLowerCase();
  final out = <TextMatch>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].toLowerCase();
    var from = 0;
    while (true) {
      final at = l.indexOf(q, from);
      if (at < 0) break;
      out.add((line: i, start: at, end: at + q.length));
      from = at + q.length;
    }
  }
  return out;
}

/// A search mark inside one line: [start]..[end], [current] = the one the
/// search is on.
typedef LineMark = ({int start, int end, bool current});

/// [text] with [marks] in amber (SPEC-058 R5): the current one solid, the
/// others translucent.
TextSpan markedSpan(String text, List<LineMark> marks) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in marks) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(
      TextSpan(
        text: text.substring(m.start, m.end),
        style: TextStyle(
          color: m.current ? AppColors.onAmber : AppColors.text,
          backgroundColor: m.current
              ? AppColors.amber
              : AppColors.amber.withValues(alpha: .32),
        ),
      ),
    );
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: spans);
}

/// [matches] by line, as [LineMark]s ([current] = index of the current one).
Map<int, List<LineMark>> marksByLine(List<TextMatch> matches, int? current) {
  final by = <int, List<LineMark>>{};
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    (by[m.line] ??= []).add((
      start: m.start,
      end: m.end,
      current: i == current,
    ));
  }
  return by;
}

/// [text] split in lines for [NumberedTextView], tabs as four spaces (the
/// search counts the characters it shows).
List<String> displayLines(String text) {
  final t = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return t.replaceAll('\t', '    ').split('\n');
}

/// Text with line numbers, search marks and optional wrapping (SPEC-058 R4,
/// R5, R7). Long texts (more than [virtualizeAbove] lines) are built lazily.
class NumberedTextView extends StatefulWidget {
  const NumberedTextView({
    super.key,
    required this.lines,
    this.numbers,
    this.highlighted = const {},
    this.wrap = false,
    this.matches = const [],
    this.current,
    this.virtualizeAbove = 5000,
    this.color = AppColors.text,
  });

  final List<String> lines;

  /// Number shown on each line (default: 1, 2, 3…).
  final List<int>? numbers;

  /// Indexes of lines shown highlighted (the lines a Read asked for).
  final Set<int> highlighted;

  /// Wrap long lines; otherwise they scroll sideways.
  final bool wrap;
  final List<TextMatch> matches;

  /// Index in [matches] of the current one: marked stronger and scrolled
  /// into view.
  final int? current;
  final int virtualizeAbove;
  final Color color;

  static const fontSize = 12.5;
  static const lineHeight = 20.0;

  @override
  State<NumberedTextView> createState() => _NumberedTextViewState();
}

class _NumberedTextViewState extends State<NumberedTextView> {
  final _v = ScrollController();
  final _h = ScrollController();
  final _currentKey = GlobalKey(debugLabel: 'current match');

  /// Matches by line, rebuilt when [NumberedTextView.matches] changes.
  Map<int, List<(TextMatch, int)>> _byLine = const {};

  static const _style = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: NumberedTextView.fontSize,
    height: NumberedTextView.lineHeight / NumberedTextView.fontSize,
  );
  static const _strut = StrutStyle(
    fontFamily: AppFonts.mono,
    fontSize: NumberedTextView.fontSize,
    height: NumberedTextView.lineHeight / NumberedTextView.fontSize,
    forceStrutHeight: true,
  );

  double? _charWidth;

  double get _char => _charWidth ??= () {
    final tp = TextPainter(
      text: const TextSpan(text: '0000000000', style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width / 10;
    tp.dispose();
    return w;
  }();

  bool get _virtual => widget.lines.length > widget.virtualizeAbove;

  @override
  void initState() {
    super.initState();
    _index();
    if (widget.current != null) _scrollToCurrent();
  }

  @override
  void didUpdateWidget(NumberedTextView old) {
    super.didUpdateWidget(old);
    if (!identical(old.matches, widget.matches)) _index();
    if (widget.current != null &&
        (widget.current != old.current ||
            !identical(old.matches, widget.matches) ||
            old.wrap != widget.wrap)) {
      _scrollToCurrent();
    }
  }

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  void _index() {
    final by = <int, List<(TextMatch, int)>>{};
    for (var i = 0; i < widget.matches.length; i++) {
      final m = widget.matches[i];
      (by[m.line] ??= []).add((m, i));
    }
    _byLine = by;
  }

  /// Brings the current match into view: the line by its key, or (not built
  /// yet) by its estimated offset first; sideways by its column.
  void _scrollToCurrent([int tries = 0]) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = widget.current;
      if (i == null || i >= widget.matches.length) return;
      final m = widget.matches[i];
      final ctx = _currentKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: .3);
      } else if (_v.hasClients && tries < 3) {
        final p = _v.position;
        p.jumpTo(
          (m.line * NumberedTextView.lineHeight - p.viewportDimension * .3)
              .clamp(p.minScrollExtent, p.maxScrollExtent),
        );
        _scrollToCurrent(tries + 1);
        return;
      }
      if (!widget.wrap && _h.hasClients) {
        final p = _h.position;
        final x = m.start * _char;
        final end = m.end * _char + _gutter + 40;
        if (x < p.pixels || end > p.pixels + p.viewportDimension) {
          p.jumpTo((x - 80).clamp(p.minScrollExtent, p.maxScrollExtent));
        }
      }
    });
  }

  int get _digits {
    final ns = widget.numbers;
    final max = ns == null || ns.isEmpty
        ? widget.lines.length
        : ns.reduce(math.max);
    return math.max(2, '$max'.length);
  }

  /// Width of the numbers column and the space after it.
  double get _gutter => _digits * _char + 20 + 16;

  Widget _line(int i) {
    final text = widget.lines[i];
    final marks = _byLine[i];
    final current = widget.current;
    final isCurrent =
        marks != null && current != null && marks.any((m) => m.$2 == current);
    final style = _style.copyWith(color: widget.color);
    final Widget body;
    if (marks == null) {
      body = Text(
        text,
        style: style,
        strutStyle: widget.wrap ? null : _strut,
        softWrap: widget.wrap,
      );
    } else {
      final span = markedSpan(text, [
        for (final (m, idx) in marks)
          (start: m.start, end: m.end, current: idx == current),
      ]);
      body = Text.rich(
        span,
        style: style,
        strutStyle: widget.wrap ? null : _strut,
        softWrap: widget.wrap,
      );
    }
    final number = widget.numbers?[i] ?? i + 1;
    final lit = widget.highlighted.contains(i);
    return Container(
      key: isCurrent ? _currentKey : null,
      decoration: lit
          ? const BoxDecoration(
              color: AppColors.amberTint,
              border: Border(
                left: BorderSide(color: AppColors.amber, width: 2),
              ),
            )
          : null,
      padding: EdgeInsets.only(left: lit ? 0 : 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: SizedBox(
              width: _digits * _char + 20,
              child: Text(
                '$number',
                textAlign: TextAlign.right,
                strutStyle: _strut,
                style: _style.copyWith(
                  color: lit ? AppColors.amber : ReviewColors.lineNumber,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (widget.wrap) Expanded(child: body) else body,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    const pad = EdgeInsets.fromLTRB(4, 14, 20, 20);
    Widget list(double? width) {
      final Widget column = _virtual
          ? ListView.builder(
              key: const ValueKey('numbered-text-virtual'),
              controller: _v,
              padding: pad,
              itemExtent: widget.wrap ? null : NumberedTextView.lineHeight,
              itemCount: lines.length,
              itemBuilder: (_, i) => _line(i),
            )
          : SingleChildScrollView(
              controller: _v,
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = 0; i < lines.length; i++) _line(i)],
              ),
            );
      return width == null ? column : SizedBox(width: width, child: column);
    }

    final body = widget.wrap
        ? Scrollbar(controller: _v, child: list(null))
        : LayoutBuilder(
            builder: (context, c) {
              final longest = lines.fold<int>(
                0,
                (m, l) => math.max(m, l.length),
              );
              final width = math.max(
                c.maxWidth,
                _gutter + longest * _char + pad.horizontal + 24,
              );
              return Scrollbar(
                controller: _v,
                notificationPredicate: (n) => n.depth == 1,
                child: Scrollbar(
                  controller: _h,
                  child: SingleChildScrollView(
                    controller: _h,
                    scrollDirection: Axis.horizontal,
                    child: list(width),
                  ),
                ),
              );
            },
          );
    return SelectionArea(child: body);
  }
}
