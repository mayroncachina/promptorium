import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'tokens.dart';

/// The Vidro theme (SPEC-049): the backdrop behind the shell, the two glass
/// levels and the blur of what floats over content.

/// Glass effects on (R6): the backdrop's lights and the blurs. Off, the app
/// keeps its layout and the translucent tokens compose over a flat
/// [AppColors.backgroundSolid] into the opaque colours of before.
/// `PROMPTORIUM_SEM_VIDRO=1` turns them off for the run.
final glassEffectsProvider = Provider<bool>((ref) {
  if (glassDisabledByEnvironment()) return false;
  return ref.watch(appSettingsProvider)[AppSettingKeys.glassEffects] != 'false';
});

/// [glassEffectsProvider] read once, for widgets that may live without a
/// [ProviderScope] (dialogs opened in tests): then only the environment
/// decides.
bool glassEffectsOf(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(glassEffectsProvider);
  } on StateError {
    return !glassDisabledByEnvironment();
  }
}

/// `PROMPTORIUM_SEM_VIDRO=1` (or `true`) in the environment.
bool glassDisabledByEnvironment([Map<String, String>? env]) {
  final v = (env ?? Platform.environment)['PROMPTORIUM_SEM_VIDRO']
      ?.trim()
      .toLowerCase();
  return v == '1' || v == 'true' || v == 'sim';
}

/// Colours of the backdrop (R1).
abstract final class GlassColors {
  /// Base of the backdrop with the effects on: a little deeper than
  /// [AppColors.backgroundSolid], so the lights read.
  static const base = Color(0xFF0A0C10);

  /// The amber light, top left, and the teal one, bottom right.
  static const amberLight = Color(0x24F2A541);
  static const tealLight = Color(0x214FD1B5);

  /// Dots of the grid.
  static const dot = Color(0x0FFFFFFF);

  /// Border and top highlight of the glass (R3).
  static const hairline = Color(0x12FFFFFF);
  static const highlight = Color(0x10FFFFFF);
}

/// The window's backdrop (R1): a dark base, an amber light top left, a teal
/// one bottom right and a faint dot grid. The lights and the dots are drawn
/// once into an image for the window size; each frame only copies that
/// image. Repainting the gradients and ~1600 dots every frame cost ~8 ms of
/// raster on an Iris Xe.
class GlassBackdrop extends ConsumerStatefulWidget {
  const GlassBackdrop({super.key});

  @override
  ConsumerState<GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends ConsumerState<GlassBackdrop> {
  ui.Image? _image;
  Size? _size;
  double _ratio = 1;
  int _job = 0;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render(Size size, double ratio) async {
    final job = ++_job;
    final w = (size.width * ratio).ceil(), h = (size.height * ratio).ceil();
    if (w <= 0 || h <= 0) return;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(ratio);
    const GlassBackdropPainter(effects: true).paint(canvas, size);
    final pic = rec.endRecording();
    final img = await pic.toImage(w, h);
    pic.dispose();
    if (!mounted || job != _job) {
      img.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = img;
    });
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(glassEffectsProvider);
    if (!on) {
      return const ColoredBox(
        key: ValueKey('glass-backdrop-flat'),
        color: AppColors.backgroundSolid,
      );
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (size != _size || ratio != _ratio) {
          _size = size;
          _ratio = ratio;
          // After the frame: never block a resize on the picture.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _render(size, ratio),
          );
        }
        return RepaintBoundary(
          child: ColoredBox(
            key: const ValueKey('glass-backdrop'),
            color: GlassColors.base,
            child: _image == null
                ? const SizedBox.expand()
                : RawImage(
                    image: _image,
                    width: size.width,
                    height: size.height,
                    fit: BoxFit.fill,
                  ),
          ),
        );
      },
    );
  }
}

class GlassBackdropPainter extends CustomPainter {
  const GlassBackdropPainter({required this.effects});

  final bool effects;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    if (!effects) {
      canvas.drawRect(all, Paint()..color = AppColors.backgroundSolid);
      return;
    }
    canvas.drawRect(all, Paint()..color = GlassColors.base);
    void light(Offset c, double r, Color color) {
      canvas.drawRect(
        all,
        Paint()..shader = ui.Gradient.radial(c, r, [color, color.withAlpha(0)]),
      );
    }

    final long = size.longestSide;
    light(
      Offset(size.width * .1, -size.height * .1),
      long * .55,
      GlassColors.amberLight,
    );
    light(
      Offset(size.width * 1.02, size.height * 1.08),
      long * .6,
      GlassColors.tealLight,
    );
    final dot = Paint()..color = GlassColors.dot;
    const step = 28.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1.2, 1.2), dot);
      }
    }
  }

  @override
  bool shouldRepaint(GlassBackdropPainter old) => old.effects != effects;
}

/// The two levels of glass (R3).
enum GlassLevel {
  /// Panels, columns, side bars of the screens.
  shell,

  /// Cards, fields, controls.
  card,
}

/// A glass surface (R3): translucent fill, 1 px hairline and a 1 px highlight
/// on top. [opaque] for surfaces content scrolls under. [glow] lights the
/// border for live state only (R4).
class AppGlass extends StatelessWidget {
  const AppGlass({
    super.key,
    this.level = GlassLevel.shell,
    this.radius = 16,
    this.opaque = false,
    this.glow,
    this.padding,
    this.child,
  });

  final GlassLevel level;
  final double radius;
  final bool opaque;
  final Color? glow;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  static Color fill(GlassLevel level, {bool opaque = false}) =>
      switch ((level, opaque)) {
        (GlassLevel.shell, false) => AppColors.panel,
        (GlassLevel.shell, true) => AppColors.panelSolid,
        (GlassLevel.card, false) => AppColors.surfaceRaised,
        (GlassLevel.card, true) => AppColors.surfaceRaisedSolid,
      };

  static BoxDecoration decoration({
    GlassLevel level = GlassLevel.shell,
    double radius = 16,
    bool opaque = false,
    Color? glow,
  }) => BoxDecoration(
    color: fill(level, opaque: opaque),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: glow?.withValues(alpha: .45) ?? GlassColors.hairline,
    ),
    boxShadow: [
      if (glow != null)
        BoxShadow(color: glow.withValues(alpha: .22), blurRadius: 22),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: decoration(
        level: level,
        radius: radius,
        opaque: opaque,
        glow: glow,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (padding == null)
              ?child
            else
              Padding(padding: padding!, child: child),
            // The 1 px light on the top edge.
            Positioned(
              left: radius / 2,
              right: radius / 2,
              top: 0,
              height: 1,
              child: const IgnorePointer(
                child: ColoredBox(color: GlassColors.highlight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blurs what is behind [child] (R5), clipped to [radius]. One level per
/// region: never nest it, never use it per item of a list. Without the glass
/// effects it is a plain clip.
class GlassBlur extends StatelessWidget {
  const GlassBlur({
    super.key,
    this.radius = 16,
    this.sigma = 22,
    required this.child,
  });

  final double radius;
  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    if (!glassEffectsOf(context)) {
      return ClipRRect(borderRadius: r, child: child);
    }
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
