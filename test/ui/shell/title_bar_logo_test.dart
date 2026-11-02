import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/ui/shell/brand_activity.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/shell/title_bar.dart';
import 'package:promptorium/ui/widgets/app_icon.dart';
import 'package:promptorium/ui/widgets/brand_mark.dart';

import '../../helpers/test_db.dart';

class _Activity extends Notifier<BrandActivity?> {
  @override
  BrandActivity? build() => null;
  void set(BrandActivity? a) => state = a;
}

final _activity = NotifierProvider<_Activity, BrandActivity?>(_Activity.new);

/// SPEC-031: the header mark, still or playing the splash's loop.
void main() {
  Future<ProviderContainer> pumpLogo(WidgetTester tester) async {
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        brandActivityProvider.overrideWith((ref) => ref.watch(_activity)),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: TitleBarLogo())),
        ),
      ),
    );
    return c;
  }

  AnimationController? waveOf(WidgetTester tester) {
    final marks = tester.widgetList<BrandMark>(find.byType(BrandMark));
    return marks
        .map((m) => m.wave)
        .whereType<AnimationController>()
        .firstOrNull;
  }

  const running = (running: 1, wave: 1, waves: 2);

  testWidgets('the header shows the 26 px mark, not the amber square (R1)', (
    tester,
  ) async {
    await pumpLogo(tester);
    expect(tester.getSize(find.byType(BrandMark)), const Size(26, 26));
    expect(find.text('Promptorium'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.flask),
      findsNothing,
    );
    final source = await tester.runAsync(
      () => File('lib/ui/shell/title_bar.dart').readAsString(),
    );
    expect(source, isNot(contains('AppIcons.flask')));
  });

  testWidgets('still with nothing running: no clock, label "Promptorium" '
      '(R3, R7)', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLogo(tester);
    expect(waveOf(tester), isNull);
    expect(find.bySemanticsLabel('Promptorium'), findsOneWidget);
    expect(find.byKey(const ValueKey('brand-open-board')), findsNothing);
    semantics.dispose();
  });

  testWidgets('a running spec plays a 2.4 s loop and says the wave; when it '
      'stops the loop ends and fades still (R3, R5, R7, R8)', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await pumpLogo(tester);
    c.read(_activity.notifier).set(running);
    await tester.pump();
    final wave = waveOf(tester);
    expect(wave, isNotNull);
    expect(wave!.duration, brandMotionCycle);
    expect(wave.isAnimating, isTrue);
    expect(
      find.bySemanticsLabel('Executando a onda 1 de 2 · 1 spec em execução'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 600));
    c.read(_activity.notifier).set(null);
    await tester.pump();
    // Still animating towards the end of the cycle.
    expect(waveOf(tester), same(wave));
    expect(wave.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 400));
    expect(waveOf(tester), isNull);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.bySemanticsLabel('Promptorium'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('with animations off nothing moves, but the label still says '
      'the specs run (R6)', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final semantics = tester.ensureSemantics();
    final c = await pumpLogo(tester);
    c.read(_activity.notifier).set((running: 2, wave: 1, waves: 1));
    await tester.pump();
    expect(waveOf(tester), isNull);
    expect(find.bySemanticsLabel('2 specs em execução'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('while specs run, clicking the mark opens the Quadro; still, '
      'it does nothing (R9)', (tester) async {
    final c = await pumpLogo(tester);
    c.read(navigationProvider.notifier).go(AppSection.home);
    await tester.tap(find.byType(BrandMark));
    await tester.pump();
    expect(c.read(navigationProvider), AppSection.home);
    c.read(_activity.notifier).set(running);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('brand-open-board')));
    await tester.pump();
    expect(c.read(navigationProvider), AppSection.tasks);
    c.read(_activity.notifier).set(null);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('brandActivityOf counts running specs with a live session, '
      'not waiting ones nor conversations (R3)', (tester) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final (specs, sessions) = (await tester.runAsync(() async {
      final ws = await db
          .into(db.workspaces)
          .insertReturning(WorkspacesCompanion.insert(path: '/r', name: 'r'));
      Future<Spec> spec(
        String code,
        SpecStage stage, [
        List<String> deps = const [],
      ]) => db
          .into(db.specs)
          .insertReturning(
            SpecsCompanion.insert(
              workspaceId: ws.id,
              code: code,
              title: code,
              path: 'specs/$code.md',
              stage: Value(stage),
              dependsOn: Value(deps),
            ),
          );
      final a = await spec('SPEC-001', SpecStage.running);
      final b = await spec('SPEC-002', SpecStage.running);
      await spec('SPEC-003', SpecStage.backlog, ['SPEC-001']);
      Future<void> session(String id, int? specId, SessionStatus status) => db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: id,
              workspaceId: ws.id,
              worktreePath: '/r',
              branch: 'b',
              model: 'sonnet',
              specId: Value(specId),
              status: Value(status),
            ),
          );
      await session('s-a', a.id, SessionStatus.running);
      await session('s-b', b.id, SessionStatus.waitingApproval);
      await session('chat', null, SessionStatus.running);
      return (
        await db.select(db.specs).get(),
        await db.select(db.sessions).get(),
      );
    }))!;
    final all = {'s-a', 's-b', 'chat'};
    expect(brandActivityOf(specs, sessions, all.contains), (
      running: 1,
      wave: 1,
      waves: 2,
    ));
    expect(brandActivityOf(specs, sessions, (_) => false), isNull);
    expect(
      brandLabel((running: 1, wave: 1, waves: 2)),
      'Executando a onda 1 de 2 · 1 spec em execução',
    );
    expect(brandLabel(null), 'Promptorium');
  });
}
