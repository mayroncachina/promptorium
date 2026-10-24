import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// One spec of a canvas test: step states in order (`R1`, `R2`…) and the
/// agent and skills its sessions used.
class CanvasSpec {
  const CanvasSpec(
    this.code, {
    this.title,
    this.stage = SpecStage.backlog,
    this.steps = const [StepStatus.pending],
    this.deps = const [],
    this.agent,
    this.skills = const [],
    this.sessionStatus = SessionStatus.completed,
  });
  final String code;
  final String? title;
  final SpecStage stage;
  final List<StepStatus> steps;
  final List<String> deps;
  final String? agent;
  final List<String> skills;
  final SessionStatus sessionStatus;

  /// A session exists when the spec ran, waits for the user or used refs.
  bool get hasSession =>
      agent != null ||
      skills.isNotEmpty ||
      steps.any((s) => s != StepStatus.pending);
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

String stepText(String code, String step) => 'Texto do $step de $code';

/// Quadro with [specs], switched to the Canvas view.
Future<(ProviderContainer, AppDatabase)> pumpCanvas(
  WidgetTester tester,
  List<CanvasSpec> specs, {
  String path = '/work/repo',
  Size size = const Size(1440, 900),
  List<Override> Function(AppDatabase db)? overrides,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final ws = await db
      .into(db.workspaces)
      .insertReturning(WorkspacesCompanion.insert(path: path, name: 'repo'));
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${ws.id}',
        ),
      );
  var seq = 0;
  for (final f in specs) {
    final spec = await db
        .into(db.specs)
        .insertReturning(
          SpecsCompanion.insert(
            workspaceId: ws.id,
            code: f.code,
            title: f.title ?? f.code,
            path: 'specs/${f.code}.md',
            status: const Value(SpecStatus.approved),
            stage: Value(f.stage),
            requirements: Value([
              for (var i = 1; i <= f.steps.length; i++)
                (id: 'R$i', text: stepText(f.code, 'R$i')),
            ]),
            dependsOn: Value(f.deps),
          ),
        );
    final session = 'sess-${f.code}';
    if (f.hasSession) {
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: session,
              workspaceId: ws.id,
              worktreePath: path,
              branch: 'pr/${f.code}',
              model: 'sonnet',
              specId: Value(spec.id),
              agentName: Value(f.agent),
              status: Value(f.sessionStatus),
            ),
          );
      for (final skill in f.skills) {
        await db
            .into(db.sessionEvents)
            .insert(
              SessionEventsCompanion.insert(
                sessionId: session,
                seq: seq++,
                type: 'assistant',
                json: jsonEncode({
                  'type': 'assistant',
                  'message': {
                    'content': [
                      {
                        'type': 'tool_use',
                        'name': 'Skill',
                        'input': {'skill': skill},
                      },
                    ],
                  },
                }),
              ),
            );
      }
    }
    for (final (i, status) in f.steps.indexed) {
      if (status == StepStatus.pending) continue;
      await db
          .into(db.specSteps)
          .insert(
            SpecStepsCompanion.insert(
              specId: spec.id,
              step: 'R${i + 1}',
              status: Value(status),
              sessionId: Value(session),
            ),
          );
    }
  }
  final c = ProviderContainer(
    overrides: [databaseOverride(db), ...?overrides?.call(db)],
  );
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  c.read(boardGraphViewProvider.notifier).set(true);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: BoardScreen()),
      ),
    ),
  );
  await pumpFor(tester, 20);
  return (c, db);
}

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Selects [code] by tapping its node.
Future<void> selectSpec(WidgetTester tester, String code) async {
  await tester.tap(byKey('board-open-$code'));
  await pumpFor(tester, 20);
}

/// Hovers [finder] with a mouse long enough for the details card.
Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 350));
  await pumpFor(tester, 5);
  return mouse;
}
