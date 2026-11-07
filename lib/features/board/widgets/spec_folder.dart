import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart' show Spec;
import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../board_rules.dart';
import '../board_screen.dart';
import 'spec_canvas.dart' show AttentionBubble;
import 'spec_folder_search.dart';
import 'spec_node.dart';

/// Size of the folder and its lines (docs/mockups/spec-036/Main.dc.html).
const folderWidth = 330.0, folderCollapsedWidth = 88.0;
const folderRowHeight = 40.0, folderRowGap = 3.0;
const folderRowStride = folderRowHeight + folderRowGap;
const folderMaxRows = 15;

/// Lines moved by a click on the arrows of the folder (R3).
const folderArrowRows = 4;

const _margin = 12.0, _tabHeight = 33.0, _arrowHeight = 26.0;
const _searchHeight = 44.0;

/// Room after the last line, so that it grows without being cut (R3).
const _endRoom = 150.0;

/// Width of the card over the stage, when the folder is collapsed (R5).
const _overlayCardWidth = 300.0;

/// The specs of the workspace, newest first, in a column that can be collapsed
/// to the numbers (SPEC-036 R1–R5).
/// A section of the folder in "Todas" (SPEC-042 R8).
@immutable
class FolderSection {
  const FolderSection({
    required this.key,
    required this.name,
    required this.matches,
    this.state = '',
    this.progress = '',
    this.open = false,
  });

  final String key;
  final String name;
  final bool Function(Spec) matches;

  /// `Ativa`, `Planejada`, `Concluída`.
  final String state;

  /// `5 de 8`.
  final String progress;

  /// Open until the person says otherwise.
  final bool open;
}

class SpecFolder extends ConsumerStatefulWidget {
  const SpecFolder({
    super.key,
    required this.cards,
    required this.attention,
    required this.onOpen,
    this.onSearchDone,
    this.title = 'specs/',
    this.sections,
    this.outside = const [],
    this.onSearchAll,
  });

  /// `specs/`, or the name of the sprint on the Quadro.
  final String title;

  /// Groups the list; null = a plain list.
  final List<FolderSection>? sections;

  /// Cards of the other sprints: a search with no result counts them (R8).
  final List<SpecCardData> outside;

  /// "Buscar em todas".
  final VoidCallback? onSearchAll;

  /// Cards of the folder, in any order.
  final List<SpecCardData> cards;
  final bool Function(SpecCardData) attention;
  final ValueChanged<int> onOpen;

  /// The search closed by `Esc` or `Enter`: the focus should go elsewhere.
  final VoidCallback? onSearchDone;

  @override
  ConsumerState<SpecFolder> createState() => SpecFolderState();
}

class SpecFolderState extends ConsumerState<SpecFolder> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'spec-folder');
  final _search = TextEditingController();
  late final _searchFocus = FocusNode(
    debugLabel: 'spec-folder-search',
    onKeyEvent: _onSearchKey,
  );

  final _listKey = GlobalKey();

  /// Result the search keys act on (R7).
  int _active = 0;
  List<SpecCardData> _results = const [];

  /// Where the arrows are taking the list: clicks in a row add up.
  double? _target;
  bool _canGoUp = false, _canGoDown = false;

  /// Lines grown by the pointer and by the keyboard (R4).
  int? _hovered, _focused;

  /// Sections the person opened or closed, against [FolderSection.open].
  final _toggled = <String>{};

  /// Lines of the sectioned list: a [FolderSection] or a card.
  List<Object> _entries = const [];

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _searching => _search.text.trim().isNotEmpty;

  /// Where the line of [id] is, in the coordinates of [layer], inside the list
  /// even when it was scrolled away; the list when the line is not in it. By
  /// position, as a line out of view is not built.
  Rect listRect(int id, RenderBox layer) {
    final box = _listKey.currentContext!.findRenderObject()! as RenderBox;
    final list = box.localToGlobal(Offset.zero, ancestor: layer) & box.size;
    final at = _entries.isEmpty
        ? _results.indexWhere((d) => d.spec.id == id)
        : _entries.indexWhere((e) => e is SpecCardData && e.spec.id == id);
    if (at < 0 || !_scroll.hasClients) {
      return Rect.fromLTWH(list.left + 8, list.top, list.width - 16, 40);
    }
    final y = (list.top + at * folderRowStride - _scroll.offset).clamp(
      list.top - folderRowHeight,
      list.bottom,
    );
    return Rect.fromLTWH(list.left + 8, y, list.width - 16, folderRowHeight);
  }

  /// `/`, `Ctrl+F` or the magnifier: opens the folder and focuses the field.
  void focusSearch() {
    ref.read(boardFolderCollapsedProvider.notifier).set(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _active = 0);
    widget.onSearchDone?.call();
  }

  void _moveActive(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _active = (_active + delta).clamp(0, _results.length - 1);
    });
    if (!_scroll.hasClients) return;
    // Lines before the active one are never grown during a search.
    final p = _scroll.position;
    final top = _active * folderRowStride;
    final bottom = top + folderRowStride;
    if (top < p.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > p.pixels + p.viewportDimension) {
      _scroll.jumpTo(
        (bottom - p.viewportDimension).clamp(0, p.maxScrollExtent),
      );
    }
  }

  KeyEventResult _onSearchKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveActive(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveActive(-1);
    } else if (e is KeyDownEvent && key == LogicalKeyboardKey.escape) {
      // An empty field lets `Esc` go on to the stage.
      if (!_searching) return KeyEventResult.ignored;
      _clearSearch();
    } else if (e is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      if (_searching && _results.isEmpty && _outsideMatches > 0) {
        widget.onSearchAll?.call();
        return KeyEventResult.handled;
      }
      if (!_searching || _results.isEmpty) return KeyEventResult.handled;
      final id = _results[_active].spec.id;
      _clearSearch();
      widget.onOpen(id);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool _onScroll(ScrollMetrics m) {
    final up = m.pixels > m.minScrollExtent;
    final down = m.pixels < m.maxScrollExtent;
    if (up != _canGoUp || down != _canGoDown) {
      // Metrics arrive during layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _canGoUp = up;
            _canGoDown = down;
          });
        }
      });
    }
    return false;
  }

  void _scrollRows(int rows) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final from = _scroll.position.isScrollingNotifier.value
        ? _target ?? p.pixels
        : p.pixels;
    final to = (from + rows * folderRowStride).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    _target = to;
    final duration = AppMotion.duration(context, AppMotion.base);
    if (duration == Duration.zero) {
      _scroll.jumpTo(to);
    } else {
      _scroll.animateTo(to, duration: duration, curve: AppMotion.enter);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _scrollRows(1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _scrollRows(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(boardFolderCollapsedProvider);
    final all = [...widget.cards]
      ..sort((a, b) => compareNewestFirst(a.spec, b.spec));
    final cards = _results = searchFolder(all, _search.text);
    if (_active >= cards.length) _active = 0;
    _entries = _sectioned(cards, collapsed);
    final width = collapsed ? folderCollapsedWidth : folderWidth;
    return AnimatedContainer(
      key: const ValueKey('spec-folder'),
      duration: AppMotion.duration(context, AppMotion.emphasis),
      curve: AppMotion.enter,
      width: width + _margin,
      padding: const EdgeInsets.fromLTRB(_margin, _margin, 0, _margin),
      child: ClipRect(
        // The content takes its final width at once, and the transition only
        // reveals it: nothing is laid out in a width it does not fit.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          child: LayoutBuilder(
            builder: (context, box) =>
                _content(cards, all.length, collapsed, box),
          ),
        ),
      ),
    );
  }

  int get _outsideMatches => searchFolder(widget.outside, _search.text).length;

  bool _isOpen(FolderSection s) => s.open != _toggled.contains(s.key);

  /// The lines of the sections; empty for a plain list. A search shows plain
  /// results, and so does the folder collapsed to the numbers.
  List<Object> _sectioned(List<SpecCardData> cards, bool collapsed) {
    final sections = widget.sections;
    if (sections == null || _searching || collapsed) return const [];
    return [
      for (final s in sections) ...[
        s,
        if (_isOpen(s))
          for (final d in cards)
            if (s.matches(d.spec)) d,
      ],
    ];
  }

  Widget _sectionHeader(FolderSection s) {
    final open = _isOpen(s);
    return SizedBox(
      key: ValueKey('folder-section-${s.key}'),
      height: folderRowStride,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() {
          _toggled.contains(s.key)
              ? _toggled.remove(s.key)
              : _toggled.add(s.key);
        }),
        child: Row(
          children: [
            Icon(
              open ? Icons.expand_more : Icons.chevron_right,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              s.state,
              style: TextStyle(
                fontSize: 11,
                color: s.state == 'Ativa'
                    ? AppColors.teal
                    : AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              s.progress,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _content(
    List<SpecCardData> cards,
    int total,
    bool collapsed,
    BoxConstraints box,
  ) {
    final rows = folderVisibleRows(box.maxHeight);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tab(_searching ? '${cards.length} de $total' : '$total', collapsed),
        Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: ListenableBuilder(
            listenable: _focus,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                color: AppColors.panel,
                border: Border.all(
                  color: _focus.hasPrimaryFocus
                      ? AppColors.amber
                      : AppColors.border,
                ),
                borderRadius: BorderRadius.only(
                  topRight: const Radius.circular(12),
                  bottomLeft: const Radius.circular(12),
                  bottomRight: const Radius.circular(12),
                ),
              ),
              child: child,
            ),
            child: Listener(
              onPointerDown: (_) => _focus.requestFocus(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _searchBox(collapsed),
                  _arrow('up', Icons.keyboard_arrow_up, _canGoUp, -1),
                  SizedBox(
                    key: _listKey,
                    height: rows * folderRowStride,
                    child: cards.isEmpty && _searching
                        ? _noResult()
                        : _list(cards, collapsed),
                  ),
                  _arrow('down', Icons.keyboard_arrow_down, _canGoDown, 1),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _noResult() {
    final others = _outsideMatches;
    final inSprint = widget.onSearchAll != null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Text(
            'Nenhuma spec com "${_search.text.trim()}"'
            '${inSprint ? ' em ${widget.title}' : ''}',
            key: const ValueKey('folder-no-result'),
            textAlign: inSprint ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          if (others > 0 && inSprint) ...[
            Text(
              others == 1 ? '1 em outra sprint' : '$others em outras sprints',
              key: const ValueKey('folder-outside-count'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            SmallButton(
              key: const ValueKey('folder-search-all'),
              label: 'Buscar em todas',
              color: AppColors.amber,
              border: AppColors.amber,
              onTap: widget.onSearchAll,
              trailing: const Text(
                'Enter',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.amber,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchBox(bool collapsed) => SizedBox(
    height: _searchHeight,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: collapsed
          ? Tooltip(
              message: 'Buscar spec',
              child: InkWell(
                key: const ValueKey('folder-search-open'),
                borderRadius: BorderRadius.circular(8),
                onTap: focusSearch,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: SessionColors.selectedBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 6,
                    children: [
                      Icon(
                        Icons.search,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      Text(
                        '/',
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : TextField(
              key: const ValueKey('folder-search'),
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (_) => setState(() {
                _active = 0;
                if (_scroll.hasClients) _scroll.jumpTo(0);
              }),
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por número ou título',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                suffixIcon: const Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Text(
                      '/',
                      key: ValueKey('folder-search-hint'),
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: SessionColors.selectedBorder,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.amber),
                ),
              ),
            ),
    ),
  );

  Widget _tab(String count, bool collapsed) => Container(
    height: _tabHeight,
    width: collapsed ? folderCollapsedWidth : 190,
    padding: const EdgeInsets.only(left: 12, right: 4),
    decoration: const BoxDecoration(
      color: AppColors.panel,
      border: Border(
        top: BorderSide(color: AppColors.border),
        left: BorderSide(color: AppColors.border),
        right: BorderSide(color: AppColors.border),
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
    ),
    child: Row(
      children: [
        const Icon(Icons.folder_outlined, size: 16, color: AppColors.amber),
        if (!collapsed) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              key: const ValueKey('folder-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.text,
              ),
            ),
          ),
          Text(
            count,
            key: const ValueKey('folder-count'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ] else
          const Spacer(),
        IconButton(
          key: const ValueKey('folder-toggle'),
          tooltip: collapsed ? 'Abrir a pasta' : 'Recolher a pasta',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
          color: AppColors.textSecondary,
          icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left),
          onPressed: () =>
              ref.read(boardFolderCollapsedProvider.notifier).toggle(),
        ),
      ],
    ),
  );

  /// For the mouse: out of the `Tab` order, which goes through the lines and
  /// would stop here halfway, as the lines below the list come after it.
  Widget _arrow(String name, IconData icon, bool enabled, int direction) =>
      SizedBox(
        height: _arrowHeight,
        width: double.infinity,
        child: ExcludeFocus(
          child: IconButton(
            key: ValueKey('folder-scroll-$name'),
            tooltip: direction < 0 ? 'Rolar para cima' : 'Rolar para baixo',
            iconSize: 18,
            padding: EdgeInsets.zero,
            color: AppColors.textSecondary,
            disabledColor: AppColors.border,
            icon: Icon(icon),
            onPressed: enabled
                ? () => _scrollRows(direction * folderArrowRows)
                : null,
          ),
        ),
      );

  Widget _list(List<SpecCardData> cards, bool collapsed) {
    final fade = <Color>[
      _canGoUp ? Colors.transparent : Colors.black,
      Colors.black,
      Colors.black,
      _canGoDown ? Colors.transparent : Colors.black,
    ];
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onScroll(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onScroll(n.metrics),
        child: ShaderMask(
          key: const ValueKey('folder-fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: fade,
            stops: const [0, .05, .95, 1],
          ).createShader(r),
          child: RawScrollbar(
            key: const ValueKey('folder-bar'),
            controller: _scroll,
            thumbVisibility: true,
            thickness: 3,
            radius: const Radius.circular(2),
            thumbColor: AppColors.borderHover,
            child: ListView.builder(
              key: const ValueKey('folder-list'),
              controller: _scroll,
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                bottom: collapsed ? 0 : _endRoom,
              ),
              itemCount: _entries.isEmpty ? cards.length : _entries.length,
              findChildIndexCallback: (key) {
                final at = _entries.isEmpty
                    ? cards.indexWhere(
                        (d) => key == ValueKey('folder-row-${d.spec.code}'),
                      )
                    : _entries.indexWhere(
                        (e) =>
                            e is SpecCardData &&
                            key == ValueKey('folder-row-${e.spec.code}'),
                      );
                return at < 0 ? null : at;
              },
              itemBuilder: (_, i) {
                if (_entries.isEmpty) {
                  return _row(
                    cards[i],
                    i,
                    collapsed,
                    active: _searching && i == _active,
                  );
                }
                final entry = _entries[i];
                return entry is FolderSection
                    ? _sectionHeader(entry)
                    : _row(entry as SpecCardData, i, collapsed, active: false);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    SpecCardData d,
    int index,
    bool collapsed, {
    required bool active,
  }) {
    final id = d.spec.id;
    return _FolderRow(
      key: ValueKey('folder-row-${d.spec.code}'),
      data: d,
      index: index,
      slides: !_searching,
      attention: widget.attention(d),
      collapsed: collapsed,
      expanded:
          _hovered == id || (_hovered == null && (_focused == id || active)),
      onHover: (on) => setState(() {
        if (on) {
          _hovered = id;
        } else if (_hovered == id) {
          _hovered = null;
        }
      }),
      onFocus: (on) => setState(() {
        if (on) {
          _focused = id;
        } else if (_focused == id) {
          _focused = null;
        }
      }),
      onOpen: () => widget.onOpen(id),
    );
  }
}

/// One line. It grows into the full card down from where it is, so the lines
/// below move and the one under the pointer does not (R4, D3).
class _FolderRow extends ConsumerStatefulWidget {
  const _FolderRow({
    super.key,
    required this.data,
    required this.index,
    required this.slides,
    required this.attention,
    required this.collapsed,
    required this.expanded,
    required this.onHover,
    required this.onFocus,
    required this.onOpen,
  });

  final SpecCardData data;

  /// Position in the list; a change closes or opens a gap (R8).
  final int index;

  /// False while the search rewrites the list.
  final bool slides;
  final bool attention, collapsed, expanded;
  final ValueChanged<bool> onHover, onFocus;
  final VoidCallback onOpen;

  @override
  ConsumerState<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends ConsumerState<_FolderRow>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  /// The line goes straight to its new place and is painted coming from the
  /// old one: only a transformation, the list keeps its layout (R15).
  late final _slide = AnimationController(vsync: this, value: 1);
  double _slideFrom = 0;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _syncPortal() {
    final show = widget.collapsed && widget.expanded;
    if (show == _portal.isShowing) return;
    show ? _portal.show() : _portal.hide();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPortal();
    });
  }

  @override
  void didUpdateWidget(covariant _FolderRow old) {
    super.didUpdateWidget(old);
    final moved = old.index - widget.index;
    final duration = AppMotion.duration(context, AppMotion.emphasis);
    if (moved != 0 && widget.slides && duration > Duration.zero) {
      _slideFrom = moved * folderRowStride;
      _slide
        ..duration = duration
        ..forward(from: 0);
    }
    // Showing the portal marks this element dirty, so not during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPortal();
    });
  }

  Widget _card() => ExcludeFocus(
    child: SpecNode(
      key: ValueKey('folder-card-${widget.data.spec.code}'),
      data: widget.data,
      selected: false,
      reason: widget.attention ? specAttentionReason(ref, widget.data) : null,
      fitContent: true,
      onTap: widget.onOpen,
    ),
  );

  Widget _line() {
    final spec = widget.data.spec;
    final status = folderStatus(spec.stage, attention: widget.attention);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onOpen,
      child: Container(
        height: folderRowHeight,
        padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 8 : 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          spacing: widget.collapsed ? 6 : 10,
          children: [
            FolderStatusIcon(
              key: ValueKey('folder-status-${spec.code}'),
              status: status,
            ),
            Flexible(
              flex: widget.collapsed ? 1 : 0,
              child: Text(
                specShortCode(spec.code),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (!widget.collapsed)
              Expanded(
                child: Text(
                  spec.title,
                  key: ValueKey('folder-title-${spec.code}'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// `AnimatedSize` does not take a zero duration.
  Widget _grow(Widget child) {
    final duration = AppMotion.duration(context, AppMotion.base);
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: AppMotion.enter,
      alignment: Alignment.topCenter,
      child: child,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter ||
        e.logicalKey == LogicalKeyboardKey.space) {
      widget.onOpen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final grown = widget.expanded && !widget.collapsed;
    final spec = widget.data.spec;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: folderRowGap),
      child: Focus(
        onFocusChange: widget.onFocus,
        onKeyEvent: _onKey,
        child: Semantics(
          button: true,
          label: '${spec.code} · ${spec.title}',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => widget.onHover(true),
            onExit: (_) => widget.onHover(false),
            child: CompositedTransformTarget(
              link: _link,
              child: OverlayPortal(
                controller: _portal,
                overlayChildBuilder: (_) => Positioned(
                  width: _overlayCardWidth,
                  child: CompositedTransformFollower(
                    link: _link,
                    targetAnchor: Alignment.topRight,
                    offset: const Offset(10, 0),
                    // It only shows: the pointer stays on the line.
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _card(),
                      ),
                    ),
                  ),
                ),
                child: _grow(grown ? _card() : _line()),
              ),
            ),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _slide,
      child: row,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          0,
          _slideFrom * (1 - AppMotion.enter.transform(_slide.value)),
        ),
        child: child,
      ),
    );
  }
}

/// Status of a line, by shape and not only by colour (R2).
class FolderStatusIcon extends StatelessWidget {
  const FolderStatusIcon({super.key, required this.status});

  final FolderStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: folderStatusLabel(status),
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: 16,
        child: Center(
          child: switch (status) {
            FolderStatus.attention => const AttentionBubble(size: 15),
            FolderStatus.done => const Icon(
              Icons.check,
              size: 16,
              color: CanvasColors.done,
            ),
            FolderStatus.running => SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(
                key: const ValueKey('folder-spinner'),
                strokeWidth: 2.2,
                // Stopped when animations are off (R14).
                value: AppMotion.animate(context) ? null : .3,
                color: AppColors.amber,
                backgroundColor: AppColors.amber.withValues(alpha: .28),
              ),
            ),
            FolderStatus.review => Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: CanvasColors.review,
                shape: BoxShape.circle,
              ),
            ),
            FolderStatus.backlog => Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.textMuted, width: 2),
              ),
            ),
          },
        ),
      ),
    ),
  );
}

/// Lines shown in a folder of height [available] (R3, D1).
int folderVisibleRows(double available) => math.min(
  folderMaxRows,
  math.max(
    1,
    ((available - _tabHeight - _searchHeight - 2 * _arrowHeight - 2) /
            folderRowStride)
        .floor(),
  ),
);
