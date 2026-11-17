import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/activities/widgets/robot_avatar.dart';
import 'package:promptorium/features/activities/widgets/robot_snapshot.dart';

/// SPEC-086 R3, R10: the robot of the notification is the one of the
/// Atividades and the Quadro, still, waving.

/// The pixel at robot units [x], [y] of a [size] snapshot.
({int r, int g, int b, int a}) _at(RobotPixels p, double x, double y) {
  final t = robotSnapshotTransform(p.width);
  final px = (t.offset.dx + x * t.scale).round();
  final py = (t.offset.dy + y * t.scale).round();
  final i = (py * p.width + px) * 4;
  return (r: p.rgba[i], g: p.rgba[i + 1], b: p.rgba[i + 2], a: p.rgba[i + 3]);
}

int _opaque(RobotPixels p) {
  var n = 0;
  for (var i = 3; i < p.rgba.length; i += 4) {
    if (p.rgba[i] > 0) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(clearRobotSnapshots);

  const seeds = [
    'spec:1:SPEC-031',
    'spec:1:SPEC-033',
    'spec:1:SPEC-034',
    'conv:7',
    'session:abc',
  ];

  test('128 × 128 RGBA, fundo transparente', () async {
    final p = await robotSnapshot('spec:1:SPEC-031');
    expect((p.width, p.height), (128, 128));
    expect(p.rgba.length, 128 * 128 * 4);
    // The corners are empty.
    expect(p.rgba[3], 0);
    expect(p.rgba[p.rgba.length - 1], 0);
    expect(_opaque(p), greaterThan(128 * 128 ~/ 10));
  });

  test('a mesma semente dá os mesmos pixels, outra semente não', () async {
    final a = await robotSnapshot('spec:1:SPEC-031');
    clearRobotSnapshots();
    final b = await robotSnapshot('spec:1:SPEC-031');
    expect(identical(a, b), isFalse);
    expect(b.rgba, a.rgba);
    final c = await robotSnapshot('spec:1:SPEC-033');
    expect(c.rgba, isNot(a.rgba));
    // Cached: the second call is the same object.
    expect(identical(await robotSnapshot('spec:1:SPEC-033'), c), isTrue);
  });

  test('é o robô da Atividades: a cor do corpo vem do RobotIdentity', () async {
    for (final seed in seeds) {
      final p = await robotSnapshot(seed, ring: false);
      final body = _at(p, 20, 34);
      final c = RobotIdentity.of(seed).color;
      // The body is the colour at 90% over nothing: straight alpha keeps
      // the colour itself.
      expect(body.a, greaterThan(200), reason: seed);
      expect((body.r - (c.r * 255).round()).abs(), lessThan(4), reason: seed);
      expect((body.g - (c.g * 255).round()).abs(), lessThan(4), reason: seed);
      expect((body.b - (c.b * 255).round()).abs(), lessThan(4), reason: seed);
    }
  });

  test('a pose wave tem o braço direito levantado', () async {
    for (final seed in seeds) {
      final wave = await robotSnapshot(seed, ring: false);
      final still = await robotSnapshot(
        seed,
        pose: ActivityPose.watch,
        ring: false,
      );
      // Above the right shoulder: the raised arm; at rest it hangs down.
      expect(_at(wave, 33.6, 19).a, greaterThan(100), reason: seed);
      expect(_at(still, 33.6, 19).a, 0, reason: seed);
      expect(_at(still, 32, 34).a, greaterThan(100), reason: seed);
    }
  });

  test('o anel âmbar de "precisa de você"', () async {
    final p = await robotSnapshot('spec:1:SPEC-031');
    var amber = 0;
    for (var deg = 0; deg < 360; deg += 3) {
      final r = deg * 3.141592653589793 / 180;
      final x = 20 + 21 * _cos(r);
      final y = 24 + 21 * _sin(r);
      final px = _at(p, x, y);
      if (px.a > 100 && px.r > 200 && px.g > 130 && px.b < 110) amber++;
    }
    expect(amber, greaterThan(30));
  });

  test('os olhos estão abertos no quadro parado', () {
    for (final seed in seeds) {
      final id = RobotIdentity.of(seed);
      final t = robotStillTime(id, ActivityPose.wave);
      final blink = (((t - id.delay) / (4.2 * id.speed)) % 1 + 1) % 1;
      expect(blink, lessThan(.93), reason: seed);
      expect((t / .55 - (t / .55).round()).abs(), lessThan(1e-9));
    }
  });

  group('resumo (R10)', () {
    test('até três robôs lado a lado', () async {
      final three = await robotGroupSnapshot(seeds.take(3).toList());
      expect((three.width, three.height), (128, 128));
      // Three columns with something in each.
      for (final col in [21, 64, 107]) {
        var any = false;
        for (var y = 0; y < 128 && !any; y++) {
          if (three.rgba[(y * 128 + col) * 4 + 3] > 0) any = true;
        }
        expect(any, isTrue, reason: 'coluna $col');
      }
    });

    test('mais de três: os três primeiros e "+N"', () async {
      final three = await robotGroupSnapshot(seeds.take(3).toList());
      final five = await robotGroupSnapshot(seeds);
      expect(five.rgba, isNot(three.rgba));
      // The "+2" pill in the bottom-right corner.
      final i = (120 * 128 + 118) * 4;
      expect(five.rgba[i + 3], greaterThan(0));
      expect(three.rgba[i + 3], 0);
    });
  });
}

double _cos(double r) => Offset.fromDirection(r).dx;
double _sin(double r) => Offset.fromDirection(r).dy;
