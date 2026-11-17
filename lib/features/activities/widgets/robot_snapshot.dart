import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../activity.dart';
import 'robot_avatar.dart';

/// The robot of an agent as a still picture (SPEC-086 R3, R10): the same
/// [RobotPainter] of the Atividades and the Quadro, one frame, for the
/// `image-data` of a system notification.

/// Straight (not premultiplied) RGBA, 8 bits per channel, no padding.
typedef RobotPixels = ({int width, int height, Uint8List rgba});

/// The frame of [pose] that reads best still: for [ActivityPose.wave] the
/// arm at the top of the wave, the body at rest and the eyes open (not in
/// the middle of a blink).
@visibleForTesting
double robotStillTime(RobotIdentity id, ActivityPose pose) {
  double phase(double t, double period, double delay) {
    final p = ((t - delay) / period) % 1;
    return p < 0 ? p + 1 : p;
  }

  // The wave loop is 0.55 s; its phase 0 has the arm up and no bob.
  for (var n = 0; n < 200; n++) {
    final t = n * .55;
    final blink = phase(t, 4.2 * id.speed, id.delay);
    if (blink > .05 && blink < .9) return t;
  }
  return 0;
}

/// Robot units (the `viewBox 0 0 40 46`) → pixels of a [size] square with
/// the ring (centre `20,24`, radius 21) inside it.
({double scale, Offset offset}) robotSnapshotTransform(int size) {
  final scale = size / 46;
  return (
    scale: scale,
    offset: Offset(size / 2 - 20 * scale, size / 2 - 24 * scale),
  );
}

final _cache = <String, Future<RobotPixels>>{};
const _cacheLimit = 32;

Future<RobotPixels> _cached(String key, Future<RobotPixels> Function() make) {
  final hit = _cache.remove(key);
  if (hit != null) return _cache[key] = hit;
  final made = make();
  _cache[key] = made;
  if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
  // A failure is not kept.
  made.catchError((Object _) {
    _cache.remove(key);
    return (width: 0, height: 0, rgba: Uint8List(0));
  });
  return made;
}

Future<RobotPixels> _pixels(ui.Picture picture, int w, int h) async {
  final image = await picture.toImage(w, h);
  try {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return (width: w, height: h, rgba: data!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void _paintRobot(
  Canvas canvas,
  String seed,
  ActivityPose pose, {
  required double scale,
  required Offset offset,
  bool ring = false,
}) {
  final id = RobotIdentity.of(seed);
  canvas
    ..save()
    ..translate(offset.dx, offset.dy)
    ..scale(scale);
  final time = ValueNotifier(robotStillTime(id, pose));
  RobotPainter(
    identity: id,
    pose: pose,
    time: time,
    // The dashed amber ring of "precisa de você".
    selected: ring,
  ).paint(canvas, const Size(40, 46));
  canvas.restore();
  time.dispose();
}

/// The robot of [seed] in [pose], [size] × [size] px on a transparent
/// background, with the amber ring when [ring]. Cached by seed (R3).
Future<RobotPixels> robotSnapshot(
  String seed, {
  ActivityPose pose = ActivityPose.wave,
  int size = 128,
  bool ring = true,
}) => _cached('$seed|${pose.name}|$size|$ring', () {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final t = robotSnapshotTransform(size);
  _paintRobot(canvas, seed, pose, scale: t.scale, offset: t.offset, ring: ring);
  return _pixels(recorder.endRecording(), size, size);
});

/// Robots side by side in the summary of several agents (R10): up to
/// [robotGroupMax], waving, and "+N" for the rest.
const robotGroupMax = 3;

/// The robots of [seeds] side by side, [size] × [size] px.
Future<RobotPixels> robotGroupSnapshot(List<String> seeds, {int size = 128}) {
  final shown = seeds.take(robotGroupMax).toList();
  final more = seeds.length - shown.length;
  return _cached('group|${seeds.join(',')}|$size', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Three robots of 40 units and two gaps of 2 fill the width.
    final scale = size / (robotGroupMax * 40 + 2 * 2);
    final width = shown.length * 40 + (shown.length - 1) * 2;
    var x = size / 2 - width * scale / 2;
    final y = size / 2 - 46 * scale / 2 - (more > 0 ? 6 : 0);
    for (final seed in shown) {
      _paintRobot(
        canvas,
        seed,
        ActivityPose.wave,
        scale: scale,
        offset: Offset(x, y),
      );
      x += 42 * scale;
    }
    if (more > 0) {
      final text = TextPainter(
        text: TextSpan(
          text: '+$more',
          style: TextStyle(
            color: const Color(0xFFE7E9EE),
            fontSize: size * .16,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = Offset(
        size - text.width - size * .06,
        size - text.height - size * .04,
      );
      final pill = RRect.fromRectAndRadius(
        (at & text.size).inflate(size * .03),
        Radius.circular(size * .08),
      );
      canvas.drawRRect(pill, Paint()..color = const Color(0xE60A0C10));
      text
        ..paint(canvas, at)
        ..dispose();
    }
    return _pixels(recorder.endRecording(), size, size);
  });
}

/// Empties the cache (tests).
@visibleForTesting
void clearRobotSnapshots() => _cache.clear();
