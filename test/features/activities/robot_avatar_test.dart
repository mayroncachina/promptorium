import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/activities/widgets/robot_avatar.dart';

Widget host(Widget child, {bool reduce = false, bool ticking = true}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(
          enabled: ticking,
          child: Center(child: child),
        ),
      ),
    );

void main() {
  group('identity (R5, R9)', () {
    test('the same seed is always the same robot', () {
      final a = RobotIdentity.of('spec:1:SPEC-075');
      final b = RobotIdentity.of('spec:1:SPEC-075');
      expect(
        (a.shape, a.color, a.name, a.speed, a.delay),
        (b.shape, b.color, b.name, b.speed, b.delay),
      );
      // A known value: the hash does not depend on the platform or run.
      expect(stableHash('a'), 0xe40c292c);
    });

    test('seeds spread over the shapes, colours and names', () {
      final ids = [
        for (var i = 0; i < 60; i++) RobotIdentity.of('spec:1:SPEC-${100 + i}'),
      ];
      expect(
        ids.map((i) => i.shape).toSet(),
        hasLength(RobotShape.values.length),
      );
      expect(ids.map((i) => i.color).toSet().length, greaterThanOrEqualTo(6));
      expect(ids.map((i) => i.name).toSet().length, greaterThanOrEqualTo(10));
      for (final i in ids) {
        expect(i.speed, inInclusiveRange(.85, 1.2));
        expect(i.delay, inInclusiveRange(0, 1.5));
      }
    });
  });

  test('each state shows its pieces (R10)', () {
    expect(robotProps(ActivityPose.sleep), {RobotProp.z});
    expect(robotProps(ActivityPose.read), {RobotProp.lupa});
    expect(robotProps(ActivityPose.edit), {RobotProp.spark});
    expect(robotProps(ActivityPose.run), {RobotProp.gear});
    expect(robotProps(ActivityPose.think), {RobotProp.think});
    expect(robotProps(ActivityPose.wait), {RobotProp.clip});
    expect(robotProps(ActivityPose.gate), {RobotProp.lupa});
    expect(robotProps(ActivityPose.fix), {RobotProp.wrench});
    expect(robotProps(ActivityPose.error), {RobotProp.smoke});
    expect(robotProps(ActivityPose.wave), isEmpty);
    expect(robotProps(ActivityPose.watch), isEmpty);
    expect(robotEyesClosed(ActivityPose.sleep), isTrue);
    expect(robotEyesClosed(ActivityPose.error), isTrue);
    expect(robotEyesClosed(ActivityPose.read), isFalse);
  });

  group('motion (R11)', () {
    testWidgets('it moves: frames keep coming and the painter has the pose', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const RobotAvatar(seed: 's', pose: ActivityPose.edit)),
      );
      expect(find.byKey(const ValueKey('robot-edit')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      final painter =
          tester
                  .widget<CustomPaint>(find.byKey(const ValueKey('robot-edit')))
                  .painter!
              as RobotPainter;
      expect(painter.pose, ActivityPose.edit);
      expect(painter.identity.name, RobotIdentity.of('s').name);
    });

    testWidgets('"reduzir movimento": still, in the pose, no frames', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const RobotAvatar(seed: 's', pose: ActivityPose.wave),
          reduce: true,
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('robot-wave')), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('out of the screen (TickerMode off): no frames', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const RobotAvatar(seed: 's', pose: ActivityPose.run),
          ticking: false,
        ),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the window out of focus stops it; back, it moves again', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const RobotAvatar(seed: 's', pose: ActivityPose.read)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('no ticker leaks when the robots leave the tree', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in ActivityPose.values)
                RobotAvatar(seed: p.name, pose: p, size: 24),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
