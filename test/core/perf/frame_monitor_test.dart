import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/perf/frame_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('percentiles and slow frames', () {
    final build = List.generate(100, (i) => (i + 1) * 100); // 0,1..10 ms
    final raster = List.generate(100, (i) => i >= 98 ? 20000 : 5000);
    final s = FrameStats.of(build, raster);
    expect(s.frames, 100);
    expect(s.buildP50, 5100);
    expect(s.buildP90, 9000);
    expect(s.rasterP90, 5000);
    expect(s.rasterP99, 20000);
    expect(s.slow, 2);
  });

  test('empty batch is all zero', () {
    final s = FrameStats.of(const [], const []);
    expect(s.frames, 0);
    expect(s.rasterP90, 0);
  });

  test('only the variable turns it on', () {
    expect(FrameMonitor.fromEnvironment(const {}), isNull);
    expect(
      FrameMonitor.fromEnvironment(const {'PROMPTORIUM_QUADROS': ' '}),
      isNull,
    );
  });

  test('flush appends one JSON line per window and resets', () {
    final dir = Directory.systemTemp.createTempSync('quadros');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/q.jsonl');
    final m = FrameMonitor(f)
      ..add(1000, 2000)
      ..add(3000, 18000)
      ..flush()
      ..flush(); // nothing new: no line
    m.add(500, 500);
    m.flush();
    final lines = f.readAsLinesSync();
    expect(lines, hasLength(2));
    final first = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(first['quadros'], 2);
    expect(first['lentos'], 1);
    expect(first['raster_p99_us'], 18000);
  });
}
