import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../../ui/widgets/diff_view.dart';
import '../../../ui/widgets/numbered_text_view.dart';
import '../../code/code_model.dart';
import '../edit_diff.dart';
import '../timeline.dart';
import '../timeline_provider.dart';
import '../tool_expanded.dart';
import 'session_style.dart';
import 'timeline_view.dart';

/// Layer of the Sessions screen that holds the expanded tool (SPEC-058).
/// Put over the whole area (list, sessions, panel) in a [Stack]: it grows
/// from the clicked card and shrinks back to it (R9), while the timeline
/// stays mounted below (R8).
class ToolExpandedOverlay extends ConsumerStatefulWidget {
  const ToolExpandedOverlay({super.key, required this.rootOf});

  /// Worktree of a session (tool targets are shown relative to it).
  final String? Function(String sessionId) rootOf;

  @override
  ConsumerState<ToolExpandedOverlay> createState() =>
      _ToolExpandedOverlayState();
}

class _ToolExpandedOverlayState extends ConsumerState<ToolExpandedOverlay>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this);
  late final _curve = CurvedAnimation(
    parent: _anim,
    curve: AppMotion.enter,
    reverseCurve: AppMotion.exit.flipped,
  );

  /// What is on screen: the open tool, or the last one while it shrinks.
  ToolExpanded? _shown;

  /// Rectangle the view grows from or shrinks to, in this layer (null =
  /// none: it fades).
  Rect? _edge;

  /// [global] in this layer's coordinates.
  Rect? _local(Rect? global) {
    final box = context.findRenderObject();
    if (global == null || box is! RenderBox || !box.hasSize) return null;
    return Rect.fromPoints(
      box.globalToLocal(global.topLeft),
      box.globalToLocal(global.bottomRight),
    );
  }

  @override
  void initState() {
    super.initState();
    final s = ref.read(toolExpandedProvider);
    if (s != null && s.open) {
      _shown = s;
      _anim.value = 1;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onChange(ToolExpanded? prev, ToolExpanded? next) {
    final animate = AppMotion.animate(context);
    if (next != null && next.open) {
      final opening = _shown == null || !(prev?.open ?? false);
      setState(() => _shown = next);
      if (!opening) return;
      _edge = _local(next.origin);
      if (!animate) {
        _anim.value = 1;
        return;
      }
      _anim.duration = AppMotion.emphasis;
      _anim.forward(from: _anim.isAnimating ? _anim.value : 0);
      return;
    }
    final shown = _shown;
    if (shown == null) return;
    // Shrinks to the card it came back to, when it is in sight.
    final box = context.findRenderObject();
    final bounds = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final card = ref
        .read(toolExpandedProvider.notifier)
        .cards(shown.sessionId)
        .rectOf(next?.toolId ?? shown.toolId);
    _edge = _local(
      card != null && bounds != null && bounds.overlaps(card)
          ? card
          : shown.origin,
    );
    if (!animate) {
      setState(() => _shown = null);
      return;
    }
    _anim.reverseDuration = AppMotion.base;
    _anim.reverse().whenCompleteOrCancel(() {
      if (mounted && !_anim.isAnimating && _anim.value == 0) {
        setState(() => _shown = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ToolExpanded?>(toolExpandedProvider, _onChange);
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final open = ref.watch(
      toolExpandedProvider.select((s) => s?.open ?? false),
    );
    final view = ToolExpandedView(
      key: const ValueKey('tool-expanded'),
      sessionId: shown.sessionId,
      toolId: shown.toolId,
      root: widget.rootOf(shown.sessionId),
    );
    return IgnorePointer(
      ignoring: !open,
      child: LayoutBuilder(
        builder: (context, c) {
          final full = Offset.zero & c.biggest;
          final small = _edge;
          return AnimatedBuilder(
            animation: _curve,
            child: view,
            builder: (context, child) {
              final k = _curve.value;
              if (k >= 1 || small == null) {
                return Opacity(opacity: k >= 1 ? 1 : k, child: child);
              }
              final rect = Rect.lerp(small, full, k)!;
              // The text arrives after the box has mostly grown.
              final fade = ((k - .4) / .6).clamp(0.0, 1.0);
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: Container(
                      key: const ValueKey('tool-expanded-motion'),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.panelSolid,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.amber),
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: full.width,
                        maxWidth: full.width,
                        minHeight: full.height,
                        maxHeight: full.height,
                        child: Opacity(opacity: fade, child: child),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// `7,2 s` under a minute, `2m 05s` above.
String expandedDuration(Duration d) {
  if (d.inSeconds >= 60) return formatDuration(d);
  final tenths = (d.inMilliseconds / 100).round();
  final s = '${tenths ~/ 10},${tenths % 10}';
  return '$s s';
}

/// [rows] as a unified diff (`+`, `-`, space), for Copiar.
String diffText(List<DiffRow> rows) => [
  for (final r in rows)
    '${switch (r.op) {
      DiffOp.add => '+',
      DiffOp.del => '-',
      DiffOp.same => ' ',
    }}${r.text}',
].join('\n');

/// Text the expanded view shows for [t] and Copiar copies: the new content
/// of a Write, the result of anything else.
String expandedText(ToolItem t) {
  if (t.name == 'Write') {
    final c = t.input['content'];
    if (c is String) return c;
  }
  return t.result ?? '';
}

/// The expanded tool: header (name, target, result, Anterior / Próxima,
/// Copiar, Fechar) over its whole output (SPEC-058 R1–R3, R11).
class ToolExpandedView extends ConsumerStatefulWidget {
  const ToolExpandedView({
    super.key,
    required this.sessionId,
    required this.toolId,
    this.root,
  });

  final String sessionId;
  final String toolId;
  final String? root;

  @override
  ConsumerState<ToolExpandedView> createState() => _ToolExpandedViewState();
}

/// Text of the file at an absolute path, for a Read with `offset` /
/// `limit` (SPEC-058 R7: the lines read are highlighted in the whole file);
/// null when it cannot be read.
final toolFileTextProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, path) async {
    try {
      final f = File(path);
      if (await f.length() > 4 * 1024 * 1024) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  },
);

/// Line (1-based) of the first line of [needle] in [text]; null = absent.
int? lineOf(String text, String needle) {
  final first = needle
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  if (first.isEmpty) return null;
  final at = text.indexOf(first);
  return at < 0 ? null : '\n'.allMatches(text.substring(0, at)).length + 1;
}

/// Opens [path] (absolute, under [worktree]) on the Code screen at [line]
/// (1-based); returns why it could not, or null.
typedef OpenInCode = Future<String?> Function(
  String worktree,
  String path,
  int line,
);

/// "Abrir no Código" (SPEC-058 R6, R7): the Code screen on the session's
/// worktree, with the file open at the line.
final openInCodeProvider = Provider<OpenInCode>(
  (ref) => (worktree, path, line) async {
    final ws = ref.read(activeWorkspaceProvider);
    if (ws == null) return 'Nenhum workspace aberto.';
    final String rel;
    if (path.startsWith('$worktree/')) {
      rel = path.substring(worktree.length + 1);
    } else if (!path.startsWith('/')) {
      rel = path;
    } else {
      return 'O arquivo está fora do worktree da sessão.';
    }
    await ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.codeWorktree(ws.id), worktree);
    final r = await ref
        .read(codeWorktreeModelProvider(worktree))
        .openAt(rel, line);
    if (r case NotOpened(:final reason)) return reason;
    await ref.read(navigationProvider.notifier).request(AppSection.code);
    return null;
  },
);

/// What one tab of the expanded view shows.
sealed class _Content {
  const _Content();
}

/// Text with line numbers ([numbers] null = 1, 2, 3…).
class _TextContent extends _Content {
  _TextContent(String text, {required this.wrap, this.placeholder})
    : lines = displayLines(text),
      copy = text,
      numbers = null,
      highlighted = const {};

  _TextContent.lines(
    this.lines, {
    required this.copy,
    this.numbers,
    this.highlighted = const {},
    required this.wrap,
  }) : placeholder = null;

  final List<String> lines;
  final String copy;
  final List<int>? numbers;
  final Set<int> highlighted;

  /// "Quebrar linhas" when the person has not chosen (R4).
  final bool wrap;

  /// Shown instead of an empty text ("executando…").
  final String? placeholder;

  int get count => placeholder != null ? 0 : lines.length;
}

class _DiffContent extends _Content {
  const _DiffContent(this.diff, {this.muted = false, this.split = false});

  final EditDiff diff;
  final bool muted;

  /// Side by side (R6); otherwise unified.
  final bool split;
}

typedef _Tab = ({String id, String label, _Content content});

final _numbered = RegExp(r'^\s*(\d+)[→\t](.*)$');

/// Lines of a Read result (`cat -n`: `   12→text`) with their numbers;
/// what is not a numbered line (a reminder appended to the result) is left
/// out. Null when the result is not numbered.
({List<String> lines, List<int> numbers})? readLines(String result) {
  final lines = <String>[], numbers = <int>[];
  for (final l in result.split('\n')) {
    final m = _numbered.firstMatch(l);
    if (m == null) continue;
    numbers.add(int.parse(m.group(1)!));
    lines.add(m.group(2)!.replaceAll('\t', '    '));
  }
  return lines.isEmpty ? null : (lines: lines, numbers: numbers);
}

String _prettyInput(Map<String, dynamic> input) {
  try {
    return const JsonEncoder.withIndent('  ').convert(input);
  } catch (_) {
    return '$input';
  }
}

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

class _ToolExpandedViewState extends ConsumerState<ToolExpandedView> {
  final _body = FocusNode(debugLabel: 'tool expanded body');
  final _searchFocus = FocusNode(debugLabel: 'tool expanded search');
  final _query = TextEditingController();

  /// Tab chosen per tool (null = the first).
  final _tabs = <String, String>{};

  /// "Quebrar linhas" chosen per tool and tab (null = the default).
  final _wrap = <String, bool>{};
  bool _searching = false;
  var _current = 0;

  @override
  void initState() {
    super.initState();
    // R11: the text gets the focus on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _body.requestFocus();
    });
    _query.addListener(() => setState(() => _current = 0));
  }

  @override
  void didUpdateWidget(ToolExpandedView old) {
    super.didUpdateWidget(old);
    if (old.toolId != widget.toolId) _current = 0;
  }

  @override
  void dispose() {
    _body.dispose();
    _searchFocus.dispose();
    _query.dispose();
    super.dispose();
  }

  ToolExpandedController get _ctrl => ref.read(toolExpandedProvider.notifier);

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(const SnackBar(content: Text('Copiado')));
  }

  /// Ctrl+F: opens the search, or selects what it holds (R5).
  void _openSearch() {
    setState(() => _searching = true);
    _query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _query.text.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _body.requestFocus();
  }

  /// Esc closes the search before the view (R5).
  void _escape() => _searching ? _closeSearch() : _ctrl.close();

  void _step(int by, int count) {
    if (count == 0) return;
    setState(() => _current = (_current + by) % count);
  }

  /// Tabs of [t] (R4, R7): Saída / Comando of a Bash, Conteúdo / Diff of a
  /// Write, Conteúdo of a Read, the diff of an edit, Saída / Entrada of
  /// anything else.
  List<_Tab> _tabsOf(ToolItem t, EditDiff? diff, bool showsDiff) {
    final result = t.result ?? '';
    final waiting = t.done
        ? (t.denied ? 'Negada, não executada.' : '(sem saída)')
        : 'executando…';
    _TextContent output({required bool wrap}) => _TextContent(
      result,
      wrap: wrap,
      placeholder: result.isEmpty ? waiting : null,
    );
    final input = (
      id: 'input',
      label: 'Entrada',
      content: _TextContent(_prettyInput(t.input), wrap: true) as _Content,
    );
    switch (t.name) {
      case 'Bash':
        final cmd = t.input['command'];
        return [
          (id: 'output', label: 'Saída', content: output(wrap: false)),
          (
            id: 'command',
            label: 'Comando',
            content: _TextContent(cmd is String ? cmd : '', wrap: true),
          ),
        ];
      case 'Write' when showsDiff:
        final content = t.input['content'];
        return [
          (
            id: 'content',
            label: 'Conteúdo',
            content: _TextContent(
              content is String ? content : '',
              wrap: false,
            ),
          ),
          if (!diff!.unknownBefore)
            (
              id: 'diff',
              label: 'Diff',
              content: _DiffContent(diff, muted: t.denied),
            ),
        ];
      case 'Read' when t.done && !t.isError:
        return [(id: 'content', label: 'Conteúdo', content: _readContent(t))];
      case _ when showsDiff:
        final split = (
          id: 'split',
          label: 'Lado a lado',
          content:
              _DiffContent(diff!, muted: t.denied, split: true) as _Content,
        );
        final unified = (
          id: 'unified',
          label: 'Unificado',
          content: _DiffContent(diff, muted: t.denied) as _Content,
        );
        return [split, unified];
    }
    return [(id: 'output', label: 'Saída', content: output(wrap: true)), input];
  }

  /// A Read: the lines it returned with their numbers; with `offset` /
  /// `limit`, the whole file with those lines highlighted (R7).
  _Content _readContent(ToolItem t) {
    final result = t.result ?? '';
    final read = readLines(result);
    final offset = _int(t.input['offset']);
    final limit = _int(t.input['limit']);
    final path = editFilePath(t.input);
    if ((offset != null || limit != null) && path != null) {
      final file = ref.watch(toolFileTextProvider(path)).value;
      if (file != null) {
        final lines = displayLines(file);
        final from = ((offset ?? 1) - 1).clamp(0, lines.length);
        final to = limit == null
            ? lines.length
            : (from + limit).clamp(0, lines.length);
        return _TextContent.lines(
          lines,
          copy: file,
          highlighted: {for (var i = from; i < to; i++) i},
          wrap: false,
        );
      }
    }
    if (read == null) return _TextContent(result, wrap: false);
    return _TextContent.lines(
      read.lines,
      copy: read.lines.join('\n'),
      numbers: read.numbers,
      wrap: false,
    );
  }

  /// "Abrir no Código" of [t] (R6, R7): the file of an edit, a Write or a
  /// Read, at the first changed line (or the first line read).
  VoidCallback? _openInCode(ToolItem t, EditDiff? diff, bool showsDiff) {
    final path = editFilePath(t.input);
    final root = widget.root;
    if (path == null || root == null) return null;
    int? line;
    String? find;
    switch (t.name) {
      case 'Read':
        line = _int(t.input['offset']) ?? 1;
      case 'Write':
        line = diff == null || diff.unknownBefore
            ? 1
            : (firstChangedLine(diff.rows) ?? 1);
      case 'Edit' || 'MultiEdit':
        line = showsDiff ? firstChangedLine(diff!.rows) : null;
        // Positions unknown (the text before the edit was not seen): the
        // new text is looked for in the file as it is now.
        final edits = t.input['edits'];
        final first = t.name == 'Edit'
            ? t.input['new_string']
            : (edits is List && edits.isNotEmpty && edits.first is Map
                  ? (edits.first as Map)['new_string']
                  : null);
        if (first is String) find = first;
      default:
        return null;
    }
    return () async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final open = ref.read(openInCodeProvider);
      final container = ProviderScope.containerOf(context, listen: false);
      _ctrl.close();
      final needle = find;
      if (line == null && needle != null) {
        final sub = container.listen(
          toolFileTextProvider(path).future,
          (_, _) {},
        );
        try {
          final text = await sub.read();
          line = text == null ? null : lineOf(text, needle);
        } finally {
          sub.close();
        }
      }
      final error = await open(root, path, line ?? 1);
      if (error != null) {
        messenger
          ?..hideCurrentSnackBar()
          ..showAppToast(SnackBar(content: Text(error)));
      }
    };
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => _build(context, c.maxWidth));

  Widget _build(BuildContext context, double width) {
    // R10: below 1200 px the buttons are icons and an edit opens unified.
    final wide = width >= 1200;
    final snap = ref.watch(sessionTimelineProvider(widget.sessionId));
    final tools = ref.watch(sessionToolsProvider(widget.sessionId));
    final i = tools.indexWhere((t) => t.id == widget.toolId);
    final t = i < 0 ? findTool(snap.items, widget.toolId) : tools[i];
    final hasPrevious = i > 0;
    final hasNext = i >= 0 && i < tools.length - 1;
    final diff = t == null || !isEditTool(t.name)
        ? null
        : (sessionEditDiffs(snap, widget.root)[t.id] ??
              editDiffOf(t.name, t.input));
    final showsDiff = diff != null && t != null && (t.denied || !t.isError);

    final tabs = t == null ? const <_Tab>[] : _tabsOf(t, diff, showsDiff);
    final chosen = t == null ? null : _tabs[t.id];
    final preferred = wide ? 'split' : 'unified';
    final tab =
        tabs.where((x) => x.id == chosen).firstOrNull ??
        tabs.where((x) => x.id == preferred).firstOrNull ??
        tabs.firstOrNull;
    final content = tab?.content;
    final wrapKey = '${t?.id}/${tab?.id}';
    final wrap = switch (content) {
      _TextContent() => _wrap[wrapKey] ?? content.wrap,
      _DiffContent() => _wrap[wrapKey] ?? false,
      null => false,
    };
    final matches = !_searching
        ? const <TextMatch>[]
        : switch (content) {
            _TextContent(:final lines) => findMatches(lines, _query.text),
            _DiffContent(:final diff) => findMatches([
              for (final r in diff.rows) r.text,
            ], _query.text),
            null => const <TextMatch>[],
          };
    final current = matches.isEmpty ? null : _current % matches.length;
    final marks = content is _DiffContent
        ? marksByLine(matches, current)
        : const <int, List<LineMark>>{};
    final currentRow = current == null ? null : matches[current].line;

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): _escape,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          _openSearch,
      const SingleActivator(LogicalKeyboardKey.arrowUp): _ctrl.previous,
      const SingleActivator(LogicalKeyboardKey.keyK): _ctrl.previous,
      const SingleActivator(LogicalKeyboardKey.arrowDown): _ctrl.next,
      const SingleActivator(LogicalKeyboardKey.keyJ): _ctrl.next,
    };

    final name = t?.name ?? 'Ferramenta';
    final copy = switch (content) {
      _TextContent(:final copy) => copy,
      _DiffContent(:final diff) =>
        t?.name == 'Write' && tab?.id != 'diff'
            ? expandedText(t!)
            : diffText(diff.rows),
      null => null,
    };

    Widget body;
    if (t == null) {
      body = const Center(
        child: Text(
          'Este item não está mais na sessão.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    } else {
      body = switch (content) {
        _TextContent(placeholder: final String p) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 20, 20),
          child: Text(
            p,
            key: const ValueKey('tool-expanded-placeholder'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: NumberedTextView.fontSize,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        _TextContent c => NumberedTextView(
          key: ValueKey('tool-expanded-text-${t.id}-${tab!.id}'),
          lines: c.lines,
          numbers: c.numbers,
          highlighted: c.highlighted,
          wrap: wrap,
          matches: matches,
          current: current,
        ),
        _DiffContent(:final diff, :final muted, split: true) =>
          SideBySideDiffView(
            key: ValueKey('tool-expanded-split-${t.id}'),
            rows: diff.rows,
            muted: muted,
            wrap: wrap,
            marks: marks,
            currentRow: currentRow,
          ),
        _DiffContent(:final diff, :final muted) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (diff.unknownBefore)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  'Conteúdo anterior desconhecido',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            Expanded(
              child: DiffView(
                key: ValueKey('tool-expanded-diff-${t.id}'),
                rows: diff.rows,
                muted: muted,
                scrollable: true,
                maxLines: 1 << 30,
                marks: marks,
                currentRow: currentRow,
              ),
            ),
          ],
        ),
        null => const SizedBox.shrink(),
      };
    }

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: '$name ampliado',
      child: BlockSemantics(
        child: CallbackShortcuts(
          bindings: bindings,
          child: FocusScope(
            // R11: Tab goes around inside the view.
            child: FocusTraversalGroup(
              child: Material(
                color: AppColors.panelSolid,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      tool: t,
                      diff: diff,
                      root: widget.root,
                      lines: content is _TextContent ? content.count : 0,
                      onPrevious: hasPrevious ? _ctrl.previous : null,
                      onNext: hasNext ? _ctrl.next : null,
                      onCopy: copy == null ? null : () => _copy(copy),
                      onClose: _ctrl.close,
                      onOpenInCode: t == null
                          ? null
                          : _openInCode(t, diff, showsDiff),
                      compact: !wide,
                    ),
                    _TabBar(
                      tabs: [for (final x in tabs) (id: x.id, label: x.label)],
                      selected: tab?.id,
                      onSelect: (id) => setState(() => _tabs[t!.id] = id),
                      // The unified diff keeps its own layout (no wrap).
                      wrap: content is _DiffContent && !content.split
                          ? null
                          : (content == null ? null : wrap),
                      onWrap: () => setState(() => _wrap[wrapKey] = !wrap),
                      onSearch: content == null ? null : _openSearch,
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Focus(focusNode: _body, child: body),
                          ),
                          if (_searching && content != null)
                            Positioned(
                              top: 10,
                              right: 20,
                              child: _SearchBar(
                                controller: _query,
                                focusNode: _searchFocus,
                                current: current,
                                count: matches.length,
                                onNext: () => _step(1, matches.length),
                                onPrevious: () => _step(-1, matches.length),
                                onClose: _closeSearch,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tool,
    required this.diff,
    required this.root,
    required this.lines,
    required this.onPrevious,
    required this.onNext,
    required this.onCopy,
    required this.onClose,
    this.onOpenInCode,
    this.compact = false,
  });

  final ToolItem? tool;
  final EditDiff? diff;
  final String? root;

  /// Lines of the text shown (0 = none, or a diff).
  final int lines;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCopy;
  final VoidCallback onClose;

  /// "Abrir no Código" (R6, R7); null = not a file.
  final VoidCallback? onOpenInCode;

  /// Narrow area (R10): buttons as icons, no duration nor counts.
  final bool compact;

  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  /// "erro", "+9 −3", "+61 arquivo novo", "ok"… (R2).
  List<Widget> _result(ToolItem t) {
    const meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    if (t.denied) return const [Text('negada', style: meta)];
    if (!t.done) {
      return const [
        Dot(AppColors.teal, size: 6),
        SizedBox(width: 6),
        Text(
          'executando',
          style: TextStyle(fontSize: 12, color: AppColors.teal),
        ),
      ];
    }
    if (t.isError) {
      return const [
        Dot(AppColors.red, size: 6),
        SizedBox(width: 6),
        Text(
          'erro',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.red,
          ),
        ),
      ];
    }
    final d = diff;
    if (d != null) {
      return [
        Text(
          '+${d.added}',
          style: const TextStyle(fontSize: 12, color: AppColors.teal),
        ),
        if (d.removed > 0) ...[
          const SizedBox(width: 6),
          Text(
            '−${d.removed}',
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
        if (t.name == 'Write' && d.unknownBefore) ...[
          const SizedBox(width: 6),
          const Text('arquivo novo', style: meta),
        ] else if (!compact && t.name != 'Write') ...[
          const SizedBox(width: 10),
          Text(switch (diffHunks(d.rows)) {
            1 => '1 trecho',
            final n => '$n trechos',
          }, style: meta),
        ],
      ];
    }
    // A Read says "N linhas": the line count next to it already does.
    if (t.name == 'Read') return const [];
    return [Text(resultSummary(t), style: meta)];
  }

  @override
  Widget build(BuildContext context) {
    final t = tool;
    final start = t?.at, end = t?.doneAt;
    final took = start == null || end == null ? null : end.difference(start);
    const meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (t != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: toolColor(t.name).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                t.name,
                key: const ValueKey('tool-expanded-name'),
                style: _mono.copyWith(color: toolColor(t.name)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              t == null ? '' : toolTarget(t.name, t.input, root: root),
              key: const ValueKey('tool-expanded-target'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono,
            ),
          ),
          if (t != null) ...[
            const SizedBox(width: 12),
            ..._result(t),
            if (!compact && took != null && took.inMilliseconds >= 100) ...[
              const SizedBox(width: 12),
              const Icon(Icons.schedule, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(expandedDuration(took), style: meta),
            ],
            if (!compact && lines > 0) ...[
              const SizedBox(width: 12),
              Text(lines == 1 ? '1 linha' : '$lines linhas', style: meta),
            ],
          ],
          const SizedBox(width: 12),
          _NavPair(onPrevious: onPrevious, onNext: onNext, compact: compact),
          if (onOpenInCode != null) ...[
            const SizedBox(width: 8),
            _HeadButton(
              key: const ValueKey('tool-expanded-open-code'),
              label: 'Abrir no Código',
              icon: Icons.code,
              compact: compact,
              onTap: onOpenInCode,
            ),
          ],
          const SizedBox(width: 8),
          _HeadButton(
            key: const ValueKey('tool-expanded-copy'),
            label: 'Copiar',
            icon: Icons.copy_outlined,
            compact: compact,
            onTap: onCopy,
          ),
          const SizedBox(width: 8),
          SmallButton(
            key: const ValueKey('tool-expanded-close'),
            label: 'Fechar',
            icon: Icons.close,
            color: AppColors.amber,
            border: SessionColors.approvalBorder,
            semanticLabel: 'Fechar (Esc)',
            trailing: const Text(
              'Esc',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// Anterior | Próxima, joined (R2, R3).
class _NavPair extends StatelessWidget {
  const _NavPair({
    required this.onPrevious,
    required this.onNext,
    this.compact = false,
  });

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Icons only, with a tooltip (R10).
  final bool compact;

  Widget _half(
    String key,
    String label,
    String hint,
    IconData icon,
    VoidCallback? onTap,
  ) {
    final on = onTap != null;
    final color = on ? AppColors.text : AppColors.textMuted;
    final button = Semantics(
      button: true,
      enabled: on,
      label: '$label ($hint)',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('tool-expanded-$key'),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: '$label ($hint)', child: button) : button;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _half(
            'previous',
            'Anterior',
            '↑ ou K',
            Icons.keyboard_arrow_up,
            onPrevious,
          ),
          const SizedBox(
            height: 30,
            child: VerticalDivider(width: 1, color: AppColors.border),
          ),
          _half('next', 'Próxima', '↓ ou J', Icons.keyboard_arrow_down, onNext),
        ],
      ),
    );
  }
}

/// A header button: icon and label, or (narrow, R10) the icon alone with a
/// tooltip and the label for screen readers.
class _HeadButton extends StatelessWidget {
  const _HeadButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!compact) return SmallButton(label: label, icon: icon, onTap: onTap);
    final on = onTap != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: on,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: AppColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 30,
              height: 30,
              child: Icon(
                icon,
                size: 14,
                color: on ? AppColors.text : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tabs of the body, "Quebrar linhas" and "Buscar" (R4, R5, R7).
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.wrap,
    required this.onWrap,
    required this.onSearch,
  });

  final List<({String id, String label})> tabs;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Null = the body is not text (no "Quebrar linhas").
  final bool? wrap;
  final VoidCallback onWrap;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    Widget tool(
      String key,
      IconData icon,
      String label,
      String? hint,
      bool on,
      VoidCallback onTap,
    ) => Semantics(
      button: true,
      toggled: key == 'wrap' ? on : null,
      label: hint == null ? label : '$label ($hint)',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('tool-expanded-$key'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: on ? AppColors.amber : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: on ? AppColors.amber : AppColors.textSecondary,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Text(
                  hint,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 16, right: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final x in tabs) ...[
            Semantics(
              button: true,
              selected: x.id == selected,
              child: InkWell(
                key: ValueKey('tool-expanded-tab-${x.id}'),
                onTap: () => onSelect(x.id),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  margin: const EdgeInsets.only(right: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: x.id == selected
                            ? AppColors.amber
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    x.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: x.id == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: x.id == selected
                          ? AppColors.amber
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (wrap != null)
            tool(
              'wrap',
              Icons.wrap_text,
              'Quebrar linhas',
              null,
              wrap!,
              onWrap,
            ),
          if (onSearch != null)
            tool('search', Icons.search, 'Buscar', 'Ctrl F', false, onSearch!),
        ],
      ),
    );
  }
}

/// Search box in the corner of the body: "x de n", previous / next (R5).
/// Enter and Shift+Enter walk the matches; Esc closes it.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.current,
    required this.count,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int? current;
  final int count;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Widget arrow(String key, IconData icon, String label, VoidCallback onTap) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Tooltip(
            message: label,
            child: InkWell(
              key: ValueKey('tool-search-$key'),
              onTap: count == 0 ? null : onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  icon,
                  size: 16,
                  color: count == 0
                      ? AppColors.textMuted
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
    final counter = controller.text.isEmpty
        ? ''
        : (count == 0 ? 'nenhuma' : '${(current ?? 0) + 1} de $count');
    return Container(
      key: const ValueKey('tool-search'),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaisedSolid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderHover),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 200,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): onNext,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    onPrevious,
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              },
              // Letters typed here are text, not J / K (R3).
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.keyJ):
                      DoNothingAndStopPropagationTextIntent(),
                  SingleActivator(LogicalKeyboardKey.keyK):
                      DoNothingAndStopPropagationTextIntent(),
                },
                child: TextField(
                  key: const ValueKey('tool-search-field'),
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12.5,
                    color: AppColors.text,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar na saída',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.amber),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              counter,
              key: const ValueKey('tool-search-count'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          arrow(
            'previous',
            Icons.keyboard_arrow_up,
            'Ocorrência anterior (Shift+Enter)',
            onPrevious,
          ),
          arrow(
            'next',
            Icons.keyboard_arrow_down,
            'Próxima ocorrência (Enter)',
            onNext,
          ),
          arrow('close', Icons.close, 'Fechar a busca (Esc)', onClose),
        ],
      ),
    );
  }
}
