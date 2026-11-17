import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show fail;
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';
import 'package:promptorium/features/sessions/restore/restore_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/claude/claude_process_test.dart' show FakeProcess;
import '../../helpers/test_db.dart';

export '../../core/claude/claude_process_test.dart' show FakeProcess;

/// Records notifications instead of showing them.
class FakeNotifier implements AppNotifier {
  final shown = <(String, String)>[];
  final clicks = <VoidCallback?>[];

  @override
  Future<int?> show(
    String title,
    String body, {
    VoidCallback? onClick,
    NotificationImage? image,
    int? replaces,
    List<(String, String)> actions = const [clickAction],
    String? noActionsHint,
    String? category,
  }) async {
    shown.add((title, body));
    clicks.add(onClick);
    return shown.length;
  }

  @override
  Future<void> close(int id) async {}
}

/// Every fake `claude` started by the manager, with its argv and cwd.
class FakeCli {
  final processes = <FakeProcess>[];
  final args = <List<String>>[];
  final cwds = <String?>[];
  final envs = <Map<String, String>?>[];

  FakeProcess get last => processes.last;

  /// Starting a process fails (CLI gone, spawn error).
  bool failStart = false;

  /// Starting waits for this (a slow start, to see what happens meanwhile).
  Completer<void>? gate;

  Future<Process> start(
    String exe,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (failStart) throw ProcessException(exe, arguments, 'falha ao iniciar');
    if (gate case final g?) await g.future;
    final p = FakeProcess();
    processes.add(p);
    args.add(arguments);
    cwds.add(workingDirectory);
    envs.add(environment);
    return p;
  }
}

/// Fixture lines (`test/fixtures/stream-json-exemplo.jsonl`).
List<String> fixtureLines() =>
    File('test/fixtures/stream-json-exemplo.jsonl')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();

/// Deterministic UUIDs.
String Function() idSequence() {
  var n = 0;
  return () {
    n++;
    return '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
  };
}

List<Override> sessionOverrides({
  required AppDatabase db,
  required FakeCli cli,
  required FakeNotifier notifier,
  String? worktreesBase,
  bool restorePoints = false,
}) => [
  databaseOverride(db),
  claudeProcessStarterProvider.overrideWithValue(cli.start),
  appNotifierProvider.overrideWithValue(notifier),
  sessionIdGeneratorProvider.overrideWithValue(idSequence()),
  // SPEC-084: restore points only in the tests about them (real git per
  // turn would slow every other test down).
  if (!restorePoints)
    restoreSettingsProvider.overrideWithValue(
      const RestoreSettings(enabled: false),
    ),
  if (worktreesBase != null)
    gitServiceFactoryProvider.overrideWithValue(
      (root) => GitService(root, worktreesBase: worktreesBase),
    ),
];

/// Lets the manager's queue (drift writes) drain.
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// Waits (up to 15 s) for [cond], then [settle]s: what follows a turn (the
/// next session, a stage) runs off the manager's queue, and a fixed wait
/// is too short on a busy machine.
Future<void> until(Future<bool> Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!await cond()) {
    if (DateTime.now().isAfter(end)) fail('condição não atingida');
    // Short polls: the deadline, not the interval, bounds the wait.
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await settle();
}

ProviderContainer sessionContainer(List<Override> overrides) {
  final c = ProviderContainer(overrides: overrides);
  // Keep the manager alive for the whole test.
  c.listen(sessionManagerProvider, (_, _) {});
  return c;
}
