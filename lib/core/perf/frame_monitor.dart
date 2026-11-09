import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';

/// Frame budget at 60 Hz, in microseconds.
const frameBudgetUs = 16667;

/// Summary of a batch of frames (SPEC-049 R7).
class FrameStats {
  const FrameStats({
    required this.frames,
    required this.buildP50,
    required this.buildP90,
    required this.buildP99,
    required this.rasterP50,
    required this.rasterP90,
    required this.rasterP99,
    required this.slow,
  });

  /// Durations in microseconds, one pair per frame.
  factory FrameStats.of(List<int> build, List<int> raster) {
    int pct(List<int> xs, double p) {
      if (xs.isEmpty) return 0;
      final s = [...xs]..sort();
      final i = ((s.length - 1) * p).round();
      return s[i];
    }

    var slow = 0;
    for (var i = 0; i < build.length; i++) {
      if (build[i] > frameBudgetUs || raster[i] > frameBudgetUs) slow++;
    }
    return FrameStats(
      frames: build.length,
      buildP50: pct(build, .5),
      buildP90: pct(build, .9),
      buildP99: pct(build, .99),
      rasterP50: pct(raster, .5),
      rasterP90: pct(raster, .9),
      rasterP99: pct(raster, .99),
      slow: slow,
    );
  }

  final int frames;
  final int buildP50, buildP90, buildP99;
  final int rasterP50, rasterP90, rasterP99;

  /// Frames whose build or raster passed [frameBudgetUs].
  final int slow;

  Map<String, Object> toJson() => {
    'quadros': frames,
    'build_p50_us': buildP50,
    'build_p90_us': buildP90,
    'build_p99_us': buildP99,
    'raster_p50_us': rasterP50,
    'raster_p90_us': rasterP90,
    'raster_p99_us': rasterP99,
    'lentos': slow,
  };
}

/// Records frame timings to a file while `PROMPTORIUM_QUADROS` is set: one
/// JSON line every [period] with the frames of that window (SPEC-049 R7).
/// Off by default; it costs nothing when the variable is absent.
class FrameMonitor {
  FrameMonitor(this.file, {this.period = const Duration(seconds: 5)});

  final File file;
  final Duration period;
  final _build = <int>[];
  final _raster = <int>[];
  Timer? _timer;

  /// Starts the monitor if `PROMPTORIUM_QUADROS` names a file.
  static FrameMonitor? fromEnvironment([Map<String, String>? env]) {
    final path = (env ?? Platform.environment)['PROMPTORIUM_QUADROS'];
    if (path == null || path.trim().isEmpty) return null;
    return FrameMonitor(File(path.trim()))..start();
  }

  void start() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(period, (_) => flush());
  }

  void stop() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    flush();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      add(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds);
    }
  }

  /// One frame, in microseconds (public for tests).
  void add(int buildUs, int rasterUs) {
    _build.add(buildUs);
    _raster.add(rasterUs);
  }

  /// Writes the frames since the last flush, if any.
  void flush() {
    if (_build.isEmpty) return;
    final stats = FrameStats.of(_build, _raster);
    _build.clear();
    _raster.clear();
    final line = jsonEncode({
      'em': DateTime.now().toIso8601String(),
      ...stats.toJson(),
    });
    try {
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } on FileSystemException {
      // A measurement aid: never break the app over it.
    }
  }
}
