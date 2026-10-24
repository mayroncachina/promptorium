import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/process/process_runner.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
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

  PrototypeUiState copyWith({
    Set<String>? selected,
    String? Function()? comparing,
    int? zoom,
    String? Function()? chosen,
    bool? narrow,
    bool? versionsTab,
  }) => PrototypeUiState(
    selected: selected ?? this.selected,
    comparing: comparing == null ? this.comparing : comparing(),
    zoom: zoom ?? this.zoom,
    chosen: chosen == null ? this.chosen : chosen(),
    narrow: narrow ?? this.narrow,
    versionsTab: versionsTab ?? this.versionsTab,
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
  });

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

/// Canvas of the Protótipo mode (R3–R6).
class PrototypeCanvas extends ConsumerWidget {
  const PrototypeCanvas({super.key, required this.ws, required this.spec});

  final Workspace ws;
  final Spec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (root: ws.path, code: spec.code);
    final s = ref.watch(prototypeScreensProvider(key));
    final ui = ref.watch(prototypeUiProvider(spec.id));
    final uiCtrl = ref.read(prototypeUiProvider(spec.id).notifier);
    final job = ref.watch(prototypeJobsProvider)[spec.id];
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          key: ValueKey('proto-headless-hint'),
          content: Text(headlessInstallHint),
        ),
      );
    });
    ref.listen(
      prototypeScreensProvider(key).select((x) => x.screens),
      (_, screens) => uiCtrl.prune([for (final x in screens) x.file]),
    );
    final w = 360.0 * ui.zoom / 100;
    final h = w * thumbnailSize.height / thumbnailSize.width;
    final count = s.screens.length;
    Widget card(MockupScreen x) {
      final sel = ui.selected.contains(x.file);
      return SizedBox(
        width: w,
        child: Semantics(
          key: ValueKey('proto-card-${x.file}'),
          container: true,
          button: true,
          selected: sel,
          label: 'Tela ${x.label}',
          child: InkWell(
            onTap: () => uiCtrl.select(
              x.file,
              add: HardwareKeyboard.instance.isControlPressed,
            ),
            onDoubleTap: () => openInBrowser(ref, '$dir/${x.file}'),
            focusColor: AppColors.amber.withValues(alpha: .2),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      x.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: sel ? AppColors.amber : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: h,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sel ? AppColors.amber : AppColors.border,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: _Thumb(
                      file: x.file,
                      png: s.thumbs[x.file],
                      browserMissing: s.browserMissing,
                      onOpen: () => openInBrowser(ref, '$dir/${x.file}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget pending(String text, String id) => SizedBox(
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
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.teal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
      if (job != null && !job.isVariation)
        pending('Gerando telas da spec…', 'spec'),
    ];

    final status = [
      '$rel/',
      '$count ${count == 1 ? 'tela' : 'telas'}',
      job != null ? 'gerando…' : 'salvo',
    ].join(' · ');
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
          Expanded(
            child: CustomPaint(
              painter: const _Dots(),
              child: count == 0 && generating.isEmpty
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
                          for (final x in s.screens) card(x),
                          ...generating,
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
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
  });

  final Workspace ws;
  final Spec spec;
  final Map<String, String> approved;

  /// Sends [request] for the selected screens; null while not possible.
  final Future<bool> Function(String request)? onSend;

  @override
  ConsumerState<PrototypePanel> createState() => _PrototypePanelState();
}

class _PrototypePanelState extends ConsumerState<PrototypePanel> {
  final _request = TextEditingController();

  @override
  void initState() {
    super.initState();
    _request.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  Future<void> _remove(MockupScreen x) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('proto-remove-dialog'),
        backgroundColor: AppColors.panel,
        title: Text('Remover ${x.file}?', style: const TextStyle(fontSize: 16)),
        content: const Text(
          'O arquivo da variação é apagado da pasta de mockups.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('proto-remove-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(prototypeServiceProvider)
          .remove(widget.ws, widget.spec, x);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Falha ao remover: $e')));
      }
    }
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
    final versions = byReq.isEmpty
        ? const Center(
            child: Text(
              'Nenhuma variação ainda.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        : ListView(
            key: const ValueKey('proto-versions'),
            children: [
              for (final MapEntry(key: req, value: list) in byReq.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    '$req · ${list.first.title}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final x in list)
                  Padding(
                    key: ValueKey('proto-version-${x.file}'),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Variação ${x.letter.toUpperCase()} · ${x.file}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (approvedFile(widget.approved, req) == x.file)
                          _Badge(
                            'aprovada',
                            AppColors.teal,
                            'proto-approved-${x.file}',
                          )
                        else
                          ProtoButton(
                            key: ValueKey('proto-remove-${x.file}'),
                            label: 'Remover',
                            semanticLabel: 'Remover ${x.file}',
                            color: AppColors.red,
                            onTap: busy ? null : () => _remove(x),
                          ),
                      ],
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
