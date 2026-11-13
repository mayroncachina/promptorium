import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/process/process_runner.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../spec_action.dart';
import '../widgets/spec_action_banner.dart';
import 'prototype_delete.dart';
import 'prototype_files.dart';
import 'prototype_service.dart';
import 'prototype_thumbnails.dart';

/// `app_settings` key: the "no headless browser" hint was shown (R5).
const headlessWarnedKey = 'prototype.headlessWarned';

/// UI state of the Protótipo mode of one spec (kept while the app runs).
@immutable
class PrototypeUiState {
  const PrototypeUiState({
    this.selected = const {},
    this.comparing,
    this.zoom = 80,
    this.chosen,
    this.narrow = false,
    this.versionsTab = false,
    this.focusTarget,
    this.focusTick = 0,
    this.askTick = 0,
  });

  /// Selected files on the canvas.
  final Set<String> selected;

  /// Requirement shown in "Comparar variações" (null = canvas).
  final String? comparing;

  /// Canvas zoom (percent).
  final int zoom;

  /// File picked with "Usar esta" in the comparison.
  final String? chosen;

  /// Comparison at 1100×700 instead of 1440×900.
  final bool narrow;

  final bool versionsTab;

  /// Card or empty slot (both by requirement, `R<n>`) that gets the focus after a
  /// deletion (SPEC-027 R10); [focusTick] changes on every request.
  final String? focusTarget;
  final int focusTick;

  /// Changes when "Pedir variação" asks for the request field (R1a).
  final int askTick;

  PrototypeUiState copyWith({
    Set<String>? selected,
    String? Function()? comparing,
    int? zoom,
    String? Function()? chosen,
    bool? narrow,
    bool? versionsTab,
    String? focusTarget,
    int? focusTick,
    int? askTick,
  }) => PrototypeUiState(
    selected: selected ?? this.selected,
    comparing: comparing == null ? this.comparing : comparing(),
    zoom: zoom ?? this.zoom,
    chosen: chosen == null ? this.chosen : chosen(),
    narrow: narrow ?? this.narrow,
    versionsTab: versionsTab ?? this.versionsTab,
    focusTarget: focusTarget ?? this.focusTarget,
    focusTick: focusTick ?? this.focusTick,
    askTick: askTick ?? this.askTick,
  );
}

class PrototypeUi extends Notifier<PrototypeUiState> {
  PrototypeUi(this.specId);

  final int specId;

  static const minZoom = 40, maxZoom = 200, zoomStep = 10;

  @override
  PrototypeUiState build() => const PrototypeUiState();

  void select(String file, {bool add = false}) {
    if (!add) {
      state = state.copyWith(selected: {file});
      return;
    }
    final s = {...state.selected};
    if (!s.remove(file)) s.add(file);
    state = state.copyWith(selected: s);
  }

  void zoomBy(int delta) => state = state.copyWith(
    zoom: (state.zoom + delta).clamp(minZoom, maxZoom),
  );

  void compare(String? requirement, {String? chosen}) => state = state.copyWith(
    comparing: () => requirement,
    chosen: () => chosen,
  );

  void choose(String file) => state = state.copyWith(chosen: () => file);

  void setNarrow(bool v) => state = state.copyWith(narrow: v);

  void showVersions(bool v) => state = state.copyWith(versionsTab: v);

  /// "Limpar seleção" (Esc, SPEC-027 R3).
  void clear() {
    if (state.selected.isNotEmpty) state = state.copyWith(selected: {});
  }

  /// "Pedir variação" (SPEC-027 R1a): selects [file] and focuses the
  /// request field of "Pedir ao Claude".
  void askVariation(String file) => state = state.copyWith(
    selected: {file},
    versionsTab: false,
    askTick: state.askTick + 1,
  );

  /// Focus goes to [target] (a file or `R<n>`) after a deletion (R10).
  void focusOn(String target) => state = state.copyWith(
    focusTarget: target,
    focusTick: state.focusTick + 1,
  );

  /// Deleted [files] leave the selection and "Comparar variações" (R10);
  /// [left] are the screens that remain.
  void forget(Set<String> files, List<MockupScreen> left) {
    final comparing = state.comparing;
    state = state.copyWith(
      selected: state.selected.difference(files),
      chosen: files.contains(state.chosen) ? () => null : null,
      comparing:
          comparing != null && !left.any((x) => x.requirement == comparing)
          ? () => null
          : null,
    );
  }

  /// Drops files that no longer exist from the selection.
  void prune(Iterable<String> files) {
    final keep = state.selected.where(files.contains).toSet();
    if (keep.length != state.selected.length) {
      state = state.copyWith(selected: keep);
    }
  }
}

final prototypeUiProvider =
    NotifierProvider.family<PrototypeUi, PrototypeUiState, int>(
      PrototypeUi.new,
    );

/// Requirement "Comparar variações" opens (R8): the selected screen's, else
/// the first with two or more variations; null when that one has fewer
/// than two (the action is disabled).
String? compareTarget(PrototypeState s, PrototypeUiState ui) {
  final sel = s.screens.where((x) => ui.selected.contains(x.file)).firstOrNull;
  if (sel != null) {
    return s.variationsOf(sel.requirement).length >= 2 ? sel.requirement : null;
  }
  for (final x in s.screens) {
    if (s.variationsOf(x.requirement).length >= 2) return x.requirement;
  }
  return null;
}

/// Approved file of [requirement] (from `## Protótipo`), by file name.
String? approvedFile(Map<String, String> approved, String requirement) =>
    approved[requirement]?.split('/').last;

/// Files shown on the canvas, one per requirement (SPEC-067 R1).
List<String> shownFiles(PrototypeState s, Map<String, String> approved) => [
  for (final r in s.requirements)
    ?shownScreen(s, r, approved: approvedFile(approved, r))?.file,
];

/// Opens [path] in the system's default browser (R6).
Future<void> openInBrowser(WidgetRef ref, String path) async {
  try {
    await ref.read(processRunnerProvider)('xdg-open', [path]);
  } catch (e) {
    debugPrint('xdg-open $path: $e');
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Time of a screen: `index.json`, else the file's mtime.
DateTime? screenTime(PrototypeState s, String dir, String file) =>
    s.index.screens[file]?.createdAt ??
    (File('$dir/$file').existsSync()
        ? File('$dir/$file').lastModifiedSync()
        : null);

/// Small focusable control with an accessible label (R12).
class ProtoButton extends StatelessWidget {
  const ProtoButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.semanticLabel,
    this.selected,
    this.color,
    this.focusNode,
  });

  final FocusNode? focusNode;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final String? semanticLabel;
  final bool? selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    final enabled = onTap != null;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: semanticLabel ?? label,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
            color: primary
                ? AppColors.amber
                : selected == true
                ? AppColors.amberTint
                : AppColors.panel,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: primary ? AppColors.amber : AppColors.border,
              ),
            ),
            child: InkWell(
              focusNode: focusNode,
              onTap: onTap,
              borderRadius: radius,
              focusColor: primary
                  ? AppColors.onAmber.withValues(alpha: .25)
                  : AppColors.amber.withValues(alpha: .25),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: primary ? FontWeight.w600 : null,
                      color: primary
                          ? AppColors.onAmber
                          : color ??
                                (selected == true
                                    ? AppColors.amber
                                    : AppColors.text),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Border drawn with dashes (screen being generated, R3).
class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}

class _Dots extends CustomPainter {
  const _Dots();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = CanvasColors.grid;
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Dots old) => false;
}

/// Thumbnail (or the "no browser" card) of one screen.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.file,
    required this.png,
    required this.browserMissing,
    required this.onOpen,
  });

  final String file;
  final String? png;
  final bool browserMissing;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (png != null) {
      return Image.file(
        File(png!),
        key: ValueKey('proto-thumb-$file'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return Container(
      key: ValueKey('proto-nothumb-$file'),
      color: AppColors.surfaceRaised,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            file,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (browserMissing)
            ProtoButton(
              key: ValueKey('proto-open-$file'),
              label: 'Abrir no navegador',
              semanticLabel: 'Abrir $file no navegador',
              onTap: onOpen,
            )
          else
            const Text(
              'Gerando miniatura…',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// Deletes screens of the canvas (SPEC-027): asks, deletes and offers
/// "Desfazer". Null while deleting is blocked (R8).
typedef DeleteScreens = Future<void> Function(List<MockupScreen> screens);

/// Canvas of the Protótipo mode (R3–R6; SPEC-027 R1–R3, R7, R10).
class PrototypeCanvas extends ConsumerStatefulWidget {
  const PrototypeCanvas({
    super.key,
    required this.ws,
    required this.spec,
    this.approved = const {},
    this.onDelete,
    this.deleteReason,
    this.onGenerate,
  });

  final Workspace ws;
  final Spec spec;

  /// Approved screens of `## Protótipo` (requirement → path).
  final Map<String, String> approved;

  /// Null while deleting is blocked; [deleteReason] says why (R8).
  final DeleteScreens? onDelete;
  final String? deleteReason;

  /// "Gerar tela do `R<n>`" of an empty requirement (R7); null while not
  /// possible.
  final ValueChanged<String>? onGenerate;

  @override
  ConsumerState<PrototypeCanvas> createState() => _PrototypeCanvasState();
}

class _PrototypeCanvasState extends ConsumerState<PrototypeCanvas> {
  /// One node per card (file) and per empty slot (`R<n>`), for the focus
  /// after a deletion (R10).
  final _nodes = <String, FocusNode>{};
  String? _pendingFocus;

  FocusNode _node(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'proto-$id'));

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Focuses [_pendingFocus] once its card or slot is on screen.
  void _applyFocus() {
    final id = _pendingFocus;
    if (id == null) return;
    final n = _nodes[id];
    if (n == null || n.context == null) return;
    _pendingFocus = null;
    n.requestFocus();
  }

  /// Delete (R2): the selection when the focused card is in it (or no
  /// card has the focus), else the focused card.
  void _deleteKey(PrototypeState s, PrototypeUiState ui) {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    // The focused card, by its requirement's node (the slot and the card
    // share it, so a stale "last focused" file could name a deleted one).
    final req = _nodes.entries
        .where((e) => e.value.hasPrimaryFocus)
        .firstOrNull
        ?.key;
    final focused = req == null
        ? null
        : shownScreen(
            s,
            req,
            approved: approvedFile(widget.approved, req),
          )?.file;
    final files = focused != null && !ui.selected.contains(focused)
        ? {focused}
        : ui.selected;
    final targets = [
      for (final x in s.screens)
        if (files.contains(x.file)) x,
    ];
    if (targets.isNotEmpty) unawaited(onDelete(targets));
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.ws, spec = widget.spec;
    final key = (root: ws.path, code: spec.code);
    final s = ref.watch(prototypeScreensProvider(key));
    final ui = ref.watch(prototypeUiProvider(spec.id));
    final uiCtrl = ref.read(prototypeUiProvider(spec.id).notifier);
    final job = ref.watch(prototypeJobsProvider)[spec.id];
    // SPEC-025 R9: "Gerar telas da spec" holds the spec; its card has the
    // elapsed time and "Cancelar geração".
    final action = ref.watch(specActionProvider);
    final screensAction =
        action != null &&
            action.specId == spec.id &&
            action.kind == SpecActionKind.screens
        ? action
        : null;
    final rel = mockupDir(spec.code);
    final dir = '${ws.path}/$rel';
    ref.listen(prototypeScreensProvider(key).select((x) => x.browserMissing), (
      _,
      missing,
    ) {
      if (!missing) return;
      final settings = ref.read(appSettingsProvider.notifier);
      if (settings.get(headlessWarnedKey) == '1') return;
      unawaited(settings.set(headlessWarnedKey, '1'));
      ScaffoldMessenger.maybeOf(context)?.showAppToast(
        const SnackBar(
          key: ValueKey('proto-headless-hint'),
          content: Text(headlessInstallHint),
        ),
      );
    });
    // Only shown versions stay selected (SPEC-067 R7).
    ref.listen(
      prototypeScreensProvider(key),
      (_, next) => uiCtrl.prune(shownFiles(next, widget.approved)),
    );
    ref.listen(
      prototypeUiProvider(spec.id).select((u) => u.focusTick),
      (_, _) =>
          _pendingFocus = ref.read(prototypeUiProvider(spec.id)).focusTarget,
    );
    if (_pendingFocus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyFocus();
      });
    }
    final w = 360.0 * ui.zoom / 100;
    final h = w * thumbnailSize.height / thumbnailSize.width;
    // SPEC-067 R1: one card per requirement, with its shown version.
    final shown = [
      for (final r in s.requirements)
        ?shownScreen(s, r, approved: approvedFile(widget.approved, r)),
    ];
    final count = shown.length;
    final multi = ui.selected.length >= 2;
    final empty = s.emptyRequirements;

    Widget card(MockupScreen x) => _ScreenCard(
      key: ValueKey('proto-cardbox-${x.requirement}'),
      screen: x,
      versions: s.variationsOf(x.requirement).length,
      onVersions: () => uiCtrl.showVersions(true),
      width: w,
      height: h,
      selected: ui.selected.contains(x.file),
      multi: multi,
      approved: approvedFile(widget.approved, x.requirement) == x.file,
      png: s.thumbs[x.file],
      browserMissing: s.browserMissing,
      focusNode: _node(x.requirement),
      onTap: () => uiCtrl.select(
        x.file,
        add: HardwareKeyboard.instance.isControlPressed,
      ),
      onOpen: () => openInBrowser(ref, '$dir/${x.file}'),
      onAsk: () => uiCtrl.askVariation(x.file),
      onDelete: widget.onDelete == null ? null : () => widget.onDelete!([x]),
      deleteReason: widget.deleteReason,
    );

    Widget emptySlot(String req) => _EmptySlot(
      key: ValueKey('proto-empty-$req'),
      requirement: req,
      title: s.index.emptied[req]?.title ?? '',
      width: w,
      height: h,
      focusNode: _node(req),
      onGenerate: widget.onGenerate == null
          ? null
          : () => widget.onGenerate!(req),
    );

    Widget pending(String text, String id, {SpecActionState? run}) => SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(' ', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            CustomPaint(
              key: ValueKey('proto-generating-$id'),
              painter: const _DashedBorder(AppColors.teal),
              child: SizedBox(
                height: h,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (run != null) ...[
                          const ActionSpinner(size: 16, color: AppColors.teal),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.teal,
                          ),
                        ),
                        if (run != null) ...[
                          const SizedBox(height: 8),
                          ElapsedText(startedAt: run.startedAt),
                          const SizedBox(height: 10),
                          // Narrow cards (zoom out) shrink it instead of
                          // cutting the label.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: CancelGenerationButton(
                              onTap: ref
                                  .read(specActionProvider.notifier)
                                  .cancel,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (run != null) ...[
              const SizedBox(height: 8),
              const Text(
                'A spec fica bloqueada até as telas ficarem prontas.',
                key: ValueKey('proto-generating-note'),
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );

    final generating = <Widget>[
      if (job != null && job.isVariation)
        for (final t in job.targets)
          if (parseMockupName(t) case final m?)
            pending(
              'Gerando variação ${m.letter.toUpperCase()} de ${m.requirement}…',
              t,
            ),
      if ((job != null && !job.isVariation) || screensAction != null)
        pending('Gerando telas da spec…', 'spec', run: screensAction),
    ];

    // Cards and empty slots in requirement order (R7).
    int n(String r) => int.tryParse(r.substring(1)) ?? 0;
    final items =
        <(int, String, Widget)>[
          for (final x in shown) (x.number, x.letter, card(x)),
          for (final r in empty) (n(r), '', emptySlot(r)),
        ]..sort((a, b) {
          final c = a.$1.compareTo(b.$1);
          return c != 0 ? c : a.$2.compareTo(b.$2);
        });

    final status = [
      '$rel/',
      '$count ${count == 1 ? 'tela' : 'telas'}',
      job != null || screensAction != null ? 'gerando…' : 'salvo',
    ].join(' · ');
    final selectedScreens = [
      for (final x in shown)
        if (ui.selected.contains(x.file)) x,
    ];
    return ColoredBox(
      color: AppColors.background,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.delete): () =>
              _deleteKey(s, ui),
          const SingleActivator(LogicalKeyboardKey.escape): uiCtrl.clear,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      key: const ValueKey('proto-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  ProtoButton(
                    key: const ValueKey('proto-zoom-out'),
                    label: '−',
                    semanticLabel: 'Diminuir zoom do protótipo',
                    onTap: ui.zoom > PrototypeUi.minZoom
                        ? () => uiCtrl.zoomBy(-PrototypeUi.zoomStep)
                        : null,
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${ui.zoom}%',
                      key: const ValueKey('proto-zoom'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  ProtoButton(
                    key: const ValueKey('proto-zoom-in'),
                    label: '+',
                    semanticLabel: 'Aumentar zoom do protótipo',
                    onTap: ui.zoom < PrototypeUi.maxZoom
                        ? () => uiCtrl.zoomBy(PrototypeUi.zoomStep)
                        : null,
                  ),
                ],
              ),
            ),
            if (selectedScreens.length >= 2)
              PrototypeSelectionBar(
                count: selectedScreens.length,
                onClear: uiCtrl.clear,
                onDelete: widget.onDelete == null
                    ? null
                    : () => widget.onDelete!(selectedScreens),
              ),
            Expanded(
              child: CustomPaint(
                painter: const _Dots(),
                child: items.isEmpty && generating.isEmpty
                    ? Center(
                        child: Text(
                          s.loaded
                              ? 'Nenhuma tela ainda. Use "Gerar telas da spec".'
                              : 'Lendo $rel/…',
                          key: const ValueKey('proto-empty'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        key: const ValueKey('proto-canvas'),
                        padding: const EdgeInsets.all(24),
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 24,
                          children: [
                            for (final i in items) i.$3,
                            ...generating,
                          ],
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

/// Letter of the variation (SPEC-027 R1), also on A.
class _LetterBadge extends StatelessWidget {
  const _LetterBadge(this.letter, {super.key, required this.selected});

  final String letter;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: selected ? AppColors.amber : AppColors.border),
    ),
    child: Text(
      letter,
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 11,
        color: selected ? AppColors.amber : AppColors.textSecondary,
      ),
    ),
  );
}

/// `D · 4` after the title (SPEC-067 R2, R8): the shown letter and how
/// many versions; it opens "Versões" for that requirement.
class _VersionChip extends StatelessWidget {
  const _VersionChip({
    super.key,
    required this.screen,
    required this.versions,
    required this.selected,
    required this.onTap,
  });

  final MockupScreen screen;
  final int versions;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.amber : AppColors.textSecondary;
    final radius = BorderRadius.circular(4);
    return Semantics(
      container: true,
      button: true,
      label:
          'Variação ${screen.letterLabel}, $versions versões: ver versões de '
          '${screen.requirement}',
      child: Material(
        color: selected ? AppColors.amberTint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? AppColors.amber : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          focusColor: AppColors.amber.withValues(alpha: .25),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${screen.letterLabel} · $versions',
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.layers_outlined, size: 11, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edges of the cards stacked behind a thumbnail with two or more versions
/// (SPEC-067 R2); takes the place of the gap above the thumbnail.
class _Stacked extends StatelessWidget {
  const _Stacked({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 6,
    width: double.infinity,
    child: CustomPaint(painter: _StackedEdges(selected)),
  );
}

class _StackedEdges extends CustomPainter {
  const _StackedEdges(this.selected);

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (inset, top, alpha) in [(14.0, 0.5, .5), (7.0, 3.0, .8)]) {
      paint.color = (selected ? AppColors.amber : AppColors.border).withValues(
        alpha: alpha,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(inset, top, size.width - inset, top + 16),
          const Radius.circular(8),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StackedEdges old) => old.selected != selected;
}

/// "Aprovada" in the card label, outside the thumbnail (SPEC-027 R1).
class _ApprovedPill extends StatelessWidget {
  const _ApprovedPill({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    decoration: BoxDecoration(
      color: SessionColors.runningToolBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: SessionColors.runningToolBorder),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 12, color: AppColors.teal),
        SizedBox(width: 4),
        Text('Aprovada', style: TextStyle(fontSize: 11, color: AppColors.teal)),
      ],
    ),
  );
}

/// One screen of the canvas: label, thumbnail, "Mais ações da tela" and,
/// with two or more selected, a checkbox (SPEC-027 R1–R3).
class _ScreenCard extends StatefulWidget {
  const _ScreenCard({
    super.key,
    required this.screen,
    required this.versions,
    required this.onVersions,
    required this.width,
    required this.height,
    required this.selected,
    required this.multi,
    required this.approved,
    required this.png,
    required this.browserMissing,
    required this.focusNode,
    required this.onTap,
    required this.onOpen,
    required this.onAsk,
    required this.onDelete,
    required this.deleteReason,
  });

  final MockupScreen screen;

  /// Versions of the requirement (SPEC-067 R2: two or more show the chip).
  final int versions;
  final VoidCallback onVersions;
  final double width;
  final double height;
  final bool selected;
  final bool multi;
  final bool approved;
  final String? png;
  final bool browserMissing;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onAsk;
  final VoidCallback? onDelete;
  final String? deleteReason;

  @override
  State<_ScreenCard> createState() => _ScreenCardState();
}

class _ScreenCardState extends State<_ScreenCard> {
  bool _hover = false;
  bool _focus = false;
  bool _menuFocus = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final x = widget.screen;
    final sel = widget.selected;
    final showMore = _hover || _focus || _menuFocus || _menuOpen || sel;
    final labelColor = sel ? AppColors.amber : AppColors.textSecondary;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: FocusTraversalGroup(
          child: Stack(
            children: [
              Semantics(
                key: ValueKey('proto-card-${x.file}'),
                container: true,
                button: true,
                selected: sel,
                label:
                    'Tela ${x.spokenName}${widget.approved ? ', aprovada' : ''}',
                child: InkWell(
                  focusNode: widget.focusNode,
                  onFocusChange: (on) => setState(() => _focus = on),
                  onTap: () {
                    widget.onTap();
                    widget.focusNode.requestFocus();
                  },
                  onDoubleTap: widget.onOpen,
                  focusColor: AppColors.amber.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 20,
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: Text(
                                  x.requirement,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? AppColors.amber
                                        : AppColors.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: ExcludeSemantics(
                                  child: Text(
                                    x.title,
                                    key: ValueKey('proto-title-${x.file}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: labelColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (widget.versions >= 2)
                                _VersionChip(
                                  key: ValueKey('proto-letter-${x.file}'),
                                  screen: x,
                                  versions: widget.versions,
                                  selected: sel,
                                  onTap: widget.onVersions,
                                )
                              else
                                ExcludeSemantics(
                                  child: _LetterBadge(
                                    x.letterLabel,
                                    key: ValueKey('proto-letter-${x.file}'),
                                    selected: sel,
                                  ),
                                ),
                              const Spacer(),
                              if (widget.approved)
                                ExcludeSemantics(
                                  child: _ApprovedPill(
                                    key: ValueKey(
                                      'proto-card-approved-${x.file}',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (widget.versions >= 2)
                          _Stacked(
                            key: ValueKey('proto-stack-${x.requirement}'),
                            selected: sel,
                          )
                        else
                          const SizedBox(height: 6),
                        Container(
                          key: ValueKey('proto-frame-${x.file}'),
                          height: widget.height,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sel ? AppColors.amber : AppColors.border,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _Thumb(
                                file: x.file,
                                png: widget.png,
                                browserMissing: widget.browserMissing,
                                onOpen: widget.onOpen,
                              ),
                              if (widget.multi)
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: ExcludeSemantics(
                                    child: Icon(
                                      sel
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      key: ValueKey('proto-check-${x.file}'),
                                      size: 20,
                                      color: sel
                                          ? AppColors.amber
                                          : AppColors.textSecondary,
                                    ),
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
              if (showMore)
                Positioned(
                  right: 12,
                  top: 38,
                  child: _CardMenu(
                    screen: x,
                    onOpen: widget.onOpen,
                    onAsk: widget.onAsk,
                    onDelete: widget.onDelete,
                    deleteReason: widget.deleteReason,
                    onFocus: (on) => setState(() => _menuFocus = on),
                    onMenu: (open) => setState(() => _menuOpen = open),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Mais ações da tela" (⋯) and its menu (SPEC-027 R1a).
class _CardMenu extends StatefulWidget {
  const _CardMenu({
    required this.screen,
    required this.onOpen,
    required this.onAsk,
    required this.onDelete,
    required this.deleteReason,
    required this.onFocus,
    required this.onMenu,
  });

  final MockupScreen screen;
  final VoidCallback onOpen;
  final VoidCallback onAsk;
  final VoidCallback? onDelete;
  final String? deleteReason;
  final ValueChanged<bool> onFocus;
  final ValueChanged<bool> onMenu;

  @override
  State<_CardMenu> createState() => _CardMenuState();
}

class _CardMenuState extends State<_CardMenu> {
  final _focus = FocusNode(debugLabel: 'proto-more');
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  ButtonStyle _style(Color color) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(220, 36)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    foregroundColor: WidgetStatePropertyAll(color),
    overlayColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.focused)
          ? AppColors.amber.withValues(alpha: .25)
          : s.contains(WidgetState.hovered)
          ? SessionColors.selectedBg
          : null,
    ),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
  );

  @override
  Widget build(BuildContext context) {
    final x = widget.screen;
    final canDelete = widget.onDelete != null;
    final deleteColor = canDelete ? AppColors.red : AppColors.textDisabled;
    final deleteItem = MenuItemButton(
      key: const ValueKey('proto-menu-delete'),
      onPressed: widget.onDelete,
      leadingIcon: Icon(Icons.delete_outline, size: 16, color: deleteColor),
      trailingIcon: KeyHint('Del', color: deleteColor),
      style: _style(deleteColor),
      child: const Text('Apagar tela…'),
    );
    // Del on the button or in the menu deletes this screen (R2).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            widget.onDelete?.call(),
      },
      child: MenuAnchor(
        childFocusNode: _focus,
        alignmentOffset: const Offset(0, 6),
        onOpen: () => widget.onMenu(true),
        onClose: () => widget.onMenu(false),
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.panelSolid),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        menuChildren: [
          MenuItemButton(
            key: const ValueKey('proto-menu-open'),
            onPressed: widget.onOpen,
            leadingIcon: const Icon(Icons.open_in_new, size: 16),
            style: _style(AppColors.text),
            child: const Text('Abrir no navegador'),
          ),
          MenuItemButton(
            key: const ValueKey('proto-menu-ask'),
            onPressed: widget.onAsk,
            leadingIcon: const Icon(Icons.auto_awesome_outlined, size: 16),
            style: _style(AppColors.text),
            child: const Text('Pedir variação'),
          ),
          const Divider(
            key: ValueKey('proto-menu-divider'),
            height: 9,
            color: AppColors.border,
          ),
          if (canDelete)
            deleteItem
          else
            Tooltip(
              message: widget.deleteReason ?? deleteBusyHint,
              child: deleteItem,
            ),
        ],
        builder: (context, controller, _) => Semantics(
          button: true,
          expanded: controller.isOpen,
          label: 'Mais ações da tela ${x.spokenName}',
          child: Material(
            color: AppColors.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: _focused
                  ? const BorderSide(color: AppColors.amber, width: 2)
                  : const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              key: ValueKey('proto-more-${x.file}'),
              focusNode: _focus,
              onFocusChange: (on) {
                setState(() => _focused = on);
                widget.onFocus(on);
              },
              borderRadius: BorderRadius.circular(6),
              focusColor: AppColors.amber.withValues(alpha: .25),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: const SizedBox(
                width: 30,
                height: 26,
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Requirement left without screens (SPEC-027 R7).
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    super.key,
    required this.requirement,
    required this.title,
    required this.width,
    required this.height,
    required this.focusNode,
    required this.onGenerate,
  });

  final String requirement;
  final String title;
  final double width;
  final double height;
  final FocusNode focusNode;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 20,
            child: Row(
              children: [
                Text(
                  requirement,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
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
          ),
          const SizedBox(height: 6),
          CustomPaint(
            painter: const _DashedBorder(AppColors.textMuted),
            child: SizedBox(
              height: height,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'O $requirement ficou sem tela.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ProtoButton(
                          key: ValueKey('proto-empty-generate-$requirement'),
                          label: 'Gerar tela do $requirement',
                          focusNode: focusNode,
                          onTap: onGenerate,
                        ),
                      ),
                    ],
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

/// "Comparar variações" (R8).
class PrototypeCompare extends ConsumerWidget {
  const PrototypeCompare({
    super.key,
    required this.ws,
    required this.spec,
    required this.approved,
    required this.onApprove,
    required this.onViewSpec,
  });

  final Workspace ws;
  final Spec spec;
  final Map<String, String> approved;

  /// Null when the spec cannot change (started).
  final ValueChanged<MockupScreen>? onApprove;
  final VoidCallback onViewSpec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(
      prototypeScreensProvider((root: ws.path, code: spec.code)),
    );
    final ui = ref.watch(prototypeUiProvider(spec.id));
    final uiCtrl = ref.read(prototypeUiProvider(spec.id).notifier);
    final req = ui.comparing!;
    final rel = mockupDir(spec.code);
    final dir = '${ws.path}/$rel';
    final vars = s.variationsOf(req);
    final approvedName = approvedFile(approved, req);
    final chosen =
        vars.where((v) => v.file == ui.chosen).firstOrNull ??
        vars.where((v) => v.file == approvedName).firstOrNull ??
        vars.firstOrNull;
    final title = vars.firstOrNull?.title ?? req;
    final size = ui.narrow ? narrowThumbnailSize : thumbnailSize;
    final chosenPath = chosen == null ? null : '$rel/${chosen.file}';

    Widget variation(MockupScreen v, double w) {
      final isChosen = v == chosen;
      final meta = s.index.screens[v.file];
      final t = screenTime(s, dir, v.file);
      final h = w * size.height / size.width;
      return SizedBox(
        width: w,
        child: Container(
          key: ValueKey('proto-variation-${v.file}'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isChosen ? AppColors.amber : AppColors.border,
              width: isChosen ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Variação ${v.letter.toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isChosen) ...[
                    const SizedBox(width: 8),
                    const _Badge('escolhida', AppColors.amber, 'proto-chosen'),
                  ],
                  if (v.file == approvedName) ...[
                    const SizedBox(width: 8),
                    const _Badge(
                      'aprovada',
                      AppColors.teal,
                      'proto-is-approved',
                    ),
                  ],
                  const Spacer(),
                  if (!isChosen)
                    ProtoButton(
                      key: ValueKey('proto-use-${v.file}'),
                      label: 'Usar esta',
                      semanticLabel:
                          'Usar a variação ${v.letter.toUpperCase()}',
                      onTap: () => uiCtrl.choose(v.file),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  meta?.description ?? v.file,
                  if (t != null) _hhmm(t),
                ].join(' · '),
                key: ValueKey('proto-desc-${v.file}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onDoubleTap: () => openInBrowser(ref, '$dir/${v.file}'),
                child: Container(
                  height: h,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _SizedThumb(
                    html: '$dir/${v.file}',
                    file: v.file,
                    size: size,
                    fallback: s.thumbs[v.file],
                    browserMissing: s.browserMissing,
                    onOpen: () => openInBrowser(ref, '$dir/${v.file}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                ProtoButton(
                  key: const ValueKey('proto-compare-back'),
                  label: '← Protótipo',
                  semanticLabel: 'Voltar ao protótipo',
                  onTap: () => uiCtrl.compare(null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${spec.code} · $req · $title',
                    key: const ValueKey('proto-compare-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ProtoButton(
                  key: const ValueKey('proto-size-1440'),
                  label: '1440',
                  semanticLabel: 'Comparar em 1440 por 900',
                  selected: !ui.narrow,
                  onTap: () => uiCtrl.setNarrow(false),
                ),
                const SizedBox(width: 4),
                ProtoButton(
                  key: const ValueKey('proto-size-1100'),
                  label: '1100×700',
                  semanticLabel: 'Comparar em 1100 por 700',
                  selected: ui.narrow,
                  onTap: () => uiCtrl.setNarrow(true),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final cols = vars.length >= 3 && c.maxWidth > 900 ? 3 : 2;
                final w = ((c.maxWidth - 48 - 16 * (cols - 1)) / cols).clamp(
                  160.0,
                  900.0,
                );
                return SingleChildScrollView(
                  key: const ValueKey('proto-compare-grid'),
                  padding: const EdgeInsets.all(24),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [for (final v in vars) variation(v, w)],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: SessionColors.runningToolBg,
              border: Border(
                top: BorderSide(color: SessionColors.runningToolBorder),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ao aprovar, a tela entra na seção ## Protótipo da spec — '
                    'a etapa $req recebe ${chosenPath ?? '$rel/…'} como '
                    'referência ao executar; o gate não muda.',
                    key: const ValueKey('proto-approve-note'),
                    style: const TextStyle(fontSize: 12, color: AppColors.teal),
                  ),
                ),
                const SizedBox(width: 12),
                ProtoButton(
                  key: const ValueKey('proto-view-spec'),
                  label: 'Ver na spec',
                  semanticLabel: 'Ver a seção Protótipo na spec',
                  color: AppColors.teal,
                  onTap: onViewSpec,
                ),
                const SizedBox(width: 8),
                ProtoButton(
                  key: const ValueKey('proto-approve'),
                  label: 'Aprovar e anexar à spec',
                  primary: true,
                  semanticLabel: chosen == null
                      ? 'Aprovar e anexar à spec'
                      : 'Aprovar a variação ${chosen.letter.toUpperCase()} '
                            'e anexar à spec',
                  onTap:
                      chosen == null ||
                          onApprove == null ||
                          chosen.file == approvedName
                      ? null
                      : () => onApprove!(chosen),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thumbnail at [size] (1100×700 is generated on demand).
class _SizedThumb extends ConsumerStatefulWidget {
  const _SizedThumb({
    required this.html,
    required this.file,
    required this.size,
    required this.fallback,
    required this.browserMissing,
    required this.onOpen,
  });

  final String html;
  final String file;
  final ThumbSize size;
  final String? fallback;
  final bool browserMissing;
  final VoidCallback onOpen;

  @override
  ConsumerState<_SizedThumb> createState() => _SizedThumbState();
}

class _SizedThumbState extends ConsumerState<_SizedThumb> {
  String? _png;
  ThumbSize? _for;

  void _load() {
    if (_for == widget.size) return;
    _for = widget.size;
    _png = null;
    if (widget.size == thumbnailSize) return;
    final size = widget.size;
    unawaited(
      ref
          .read(prototypeThumbnailsProvider)
          .thumbnail(widget.html, size: size)
          .then((p) {
            if (mounted && _for == size) setState(() => _png = p);
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    _load();
    return _Thumb(
      file: widget.file,
      png: widget.size == thumbnailSize ? widget.fallback : _png,
      browserMissing: widget.browserMissing,
      onOpen: widget.onOpen,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color, this.id);

  final String text;
  final Color color;
  final String id;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(id),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );
}

/// Right panel of the Protótipo mode: "Pedir ao Claude" / "Versões"
/// (R7, R11).
class PrototypePanel extends ConsumerStatefulWidget {
  const PrototypePanel({
    super.key,
    required this.ws,
    required this.spec,
    required this.approved,
    required this.onSend,
    this.onDelete,
    this.deleteReason,
  });

  final Workspace ws;
  final Spec spec;
  final Map<String, String> approved;

  /// Sends [request] for the selected screens; null while not possible.
  final Future<bool> Function(String request)? onSend;

  /// "Apagar" of "Versões" (SPEC-027 R9); null while blocked, with
  /// [deleteReason].
  final DeleteScreens? onDelete;
  final String? deleteReason;

  @override
  ConsumerState<PrototypePanel> createState() => _PrototypePanelState();
}

class _PrototypePanelState extends ConsumerState<PrototypePanel> {
  final _request = TextEditingController();
  final _requestFocus = FocusNode(debugLabel: 'proto-request');

  @override
  void initState() {
    super.initState();
    _request.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _request.dispose();
    _requestFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final s = ref.watch(
      prototypeScreensProvider((root: widget.ws.path, code: spec.code)),
    );
    final ui = ref.watch(prototypeUiProvider(spec.id));
    final uiCtrl = ref.read(prototypeUiProvider(spec.id).notifier);
    final busy = ref.watch(prototypeJobsProvider).containsKey(spec.id);
    // "Pedir variação" of a card (SPEC-027 R1a).
    ref.listen(
      prototypeUiProvider(spec.id).select((u) => u.askTick),
      (_, _) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestFocus.requestFocus();
      }),
    );
    final selected = [
      for (final x in s.screens)
        if (ui.selected.contains(x.file)) x,
    ];
    final reqs = {for (final x in selected) x.requirement}.toList();
    final canSend =
        widget.onSend != null &&
        !busy &&
        selected.isNotEmpty &&
        _request.text.trim().isNotEmpty;

    Widget tab(String label, bool on, VoidCallback onTap, String id) =>
        Expanded(
          child: ProtoButton(
            key: ValueKey(id),
            label: label,
            selected: on,
            onTap: onTap,
          ),
        );

    final ask = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: s.index.history.isEmpty
              ? const Center(
                  child: Text(
                    'Selecione telas no canvas e peça uma variação.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView(
                  key: const ValueKey('proto-history'),
                  reverse: true,
                  children: [
                    for (final h in s.index.history.reversed)
                      _HistoryEntry(entry: h, onChip: (f) => uiCtrl.select(f)),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Pedido para as telas selecionadas',
          textField: true,
          child: TextField(
            key: const ValueKey('proto-request'),
            controller: _request,
            focusNode: _requestFocus,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Pedido para as telas selecionadas',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                reqs.isEmpty
                    ? 'Nenhuma tela selecionada'
                    : 'Selecionada${reqs.length > 1 ? 's' : ''}: ${reqs.join(', ')}',
                key: const ValueKey('proto-selected'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ProtoButton(
              key: const ValueKey('proto-send'),
              label: busy ? 'Gerando…' : 'Enviar',
              semanticLabel: 'Enviar pedido ao Claude',
              primary: true,
              onTap: canSend
                  ? () async {
                      final ok = await widget.onSend!(_request.text);
                      if (ok && mounted) _request.clear();
                    }
                  : null,
            ),
          ],
        ),
      ],
    );

    final byReq = <String, List<MockupScreen>>{};
    for (final x in s.screens) {
      (byReq[x.requirement] ??= []).add(x);
    }
    final empty = s.emptyRequirements;
    int n(String r) => int.tryParse(r.substring(1)) ?? 0;
    final reqOrder = {...byReq.keys, ...empty}.toList()
      ..sort((a, b) => n(a).compareTo(n(b)));
    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
    final versions = reqOrder.isEmpty
        ? const Center(
            child: Text(
              'Nenhuma variação ainda.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        : ListView(
            key: const ValueKey('proto-versions'),
            children: [
              for (final req in reqOrder)
                if (byReq[req] case final list?) ...[
                  header('$req, ${list.first.title}'),
                  for (final x in list)
                    _VersionRow(
                      key: ValueKey('proto-version-${x.file}'),
                      screen: x,
                      approved: approvedFile(widget.approved, req) == x.file,
                      onDelete: widget.onDelete == null
                          ? null
                          : () => widget.onDelete!([x]),
                      deleteReason: widget.deleteReason,
                    ),
                ] else ...[
                  header('$req, ${s.index.emptied[req]?.title ?? ''}'),
                  Text(
                    s.index.emptied[req]?.hadApproval == true
                        ? 'Nenhuma tela. A aprovação saiu da spec.'
                        : 'Nenhuma tela.',
                    key: ValueKey('proto-version-empty-$req'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
            ],
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              tab(
                'Pedir ao Claude',
                !ui.versionsTab,
                () => uiCtrl.showVersions(false),
                'proto-tab-ask',
              ),
              const SizedBox(width: 6),
              tab(
                'Versões',
                ui.versionsTab,
                () => uiCtrl.showVersions(true),
                'proto-tab-versions',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: ui.versionsTab ? versions : ask),
        ],
      ),
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.entry, required this.onChip});

  final PrototypeRequest entry;
  final ValueChanged<String> onChip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.amberTint,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${entry.requirements.isEmpty ? '' : '${entry.requirements.join(', ')} · '}'
            '${entry.request}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_hhmm(entry.at)}${entry.answer == null ? '' : ' · ${entry.answer}'}',
          style: TextStyle(
            fontSize: 12,
            color: entry.failed ? AppColors.red : AppColors.textSecondary,
          ),
        ),
        if (entry.files.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final f in entry.files)
                ProtoButton(
                  key: ValueKey('proto-chip-$f'),
                  label: f,
                  semanticLabel: 'Selecionar $f',
                  color: AppColors.teal,
                  onTap: () => onChip(f),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// One variation of "Versões" with its trash button (SPEC-027 R9).
class _VersionRow extends StatefulWidget {
  const _VersionRow({
    super.key,
    required this.screen,
    required this.approved,
    required this.onDelete,
    required this.deleteReason,
  });

  final MockupScreen screen;
  final bool approved;
  final VoidCallback? onDelete;
  final String? deleteReason;

  @override
  State<_VersionRow> createState() => _VersionRowState();
}

class _VersionRowState extends State<_VersionRow> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final x = widget.screen;
    final enabled = widget.onDelete != null;
    final label = widget.approved
        ? 'Apagar ${x.file}, a variação aprovada: tira a aprovação da spec'
        : 'Apagar ${x.file}';
    final tip = !enabled
        ? widget.deleteReason ?? deleteBusyHint
        : widget.approved
        ? 'Apagar esta variação tira a aprovação da spec'
        : 'Apagar ${x.file}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Variação ${x.letterLabel}',
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  x.file,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (widget.approved)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                'Aprovada',
                key: ValueKey('proto-approved-${x.file}'),
                style: const TextStyle(fontSize: 11, color: AppColors.teal),
              ),
            ),
          Tooltip(
            message: tip,
            excludeFromSemantics: true,
            child: Semantics(
              container: true,
              button: true,
              enabled: enabled,
              label: label,
              child: InkWell(
                key: ValueKey('proto-remove-${x.file}'),
                onTap: widget.onDelete,
                onHover: (v) => setState(() => _hot = v),
                onFocusChange: (v) => setState(() => _hot = v),
                borderRadius: BorderRadius.circular(6),
                focusColor: AppColors.red.withValues(alpha: .15),
                hoverColor: AppColors.red.withValues(alpha: .1),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: !enabled
                          ? AppColors.textDisabled
                          : _hot
                          ? AppColors.red
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
