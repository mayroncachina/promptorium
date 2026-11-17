import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/usage_poller.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/features/prompt/compare/compare_controller.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';
import 'package:promptorium/features/prompt/compare/widgets/compare_bar.dart';

import '../prompt_screen_test.dart' show field, fieldText, pumpFor;
import 'compare_test_utils.dart';

String modelOf(WidgetTester tester, String letter) {
  final t = find.descendant(
    of: key('compare-model-$letter'),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(t.first).data!;
}

bool modeOn(WidgetTester tester, String letter, PromptMode m) {
  final text = tester.widget<Text>(
    find.descendant(
      of: key('compare-mode-$letter-${m.name}'),
      matching: find.byType(Text),
    ),
  );
  return text.style?.color == const Color(0xFFF2A541);
}

String sendLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: key('prompt-send'), matching: find.byType(Text)),
    )
    .data!;

void main() {
  testWidgets('Comparar turns the sides on: A = the conversation, B = the '
      'other model; off keeps the text (R1)', (tester) async {
    final p = CompareFakeProvider();
    await pumpCompare(tester, provider: p);
    await tester.enterText(field, 'por que o cupom passa?');
    expect(key('compare-bar'), findsNothing);
    await tester.tap(key('prompt-compare'));
    await pumpFor(tester);
    expect(key('compare-bar'), findsOneWidget);
    expect(modelOf(tester, 'A'), 'Sonnet');
    expect(modelOf(tester, 'B'), 'Opus');
    expect(modeOn(tester, 'A', PromptMode.ask), isTrue);
    expect(modeOn(tester, 'B', PromptMode.ask), isTrue);
    expect(sendLabel(tester), 'Enviar os dois');
    expect(find.text('o modelo e o modo vão nos lados'), findsOneWidget);
    expect(key('prompt-model'), findsNothing);

    // ⇄ swaps the sides.
    await tester.tap(key('compare-swap'));
    await pumpFor(tester);
    expect(modelOf(tester, 'A'), 'Opus');
    expect(modelOf(tester, 'B'), 'Sonnet');

    await tester.tap(key('prompt-compare'));
    await pumpFor(tester);
    expect(key('compare-bar'), findsNothing);
    expect(key('prompt-model'), findsOneWidget);
    expect(fieldText(tester), 'por que o cupom passa?');
  });

  testWidgets('the shortcuts fill the sides; equal sides cannot be sent; '
      'Editar is off (R2, R3)', (tester) async {
    final p = CompareFakeProvider();
    await pumpCompare(tester, provider: p);
    await tester.enterText(field, 'por quê?');
    await tester.tap(key('prompt-compare'));
    await pumpFor(tester);

    await tester.tap(key('compare-plan-ask'));
    await pumpFor(tester);
    expect(modelOf(tester, 'A'), 'Sonnet');
    expect(modelOf(tester, 'B'), 'Sonnet');
    expect(modeOn(tester, 'A', PromptMode.plan), isTrue);
    expect(modeOn(tester, 'B', PromptMode.ask), isTrue);

    await tester.tap(key('compare-sonnet-opus'));
    await pumpFor(tester);
    expect(modelOf(tester, 'A'), 'Sonnet');
    expect(modelOf(tester, 'B'), 'Opus');
    expect(modeOn(tester, 'B', PromptMode.plan), isTrue);

    // Same model and mode: blocked, with the reason.
    await tester.tap(key('compare-model-B'));
    await pumpFor(tester);
    await tester.tap(key('compare-model-B-sonnet').last);
    await pumpFor(tester);
    expect(find.text(compareSameSidesMessage), findsWidgets);
    await tester.tap(key('prompt-send'));
    await pumpFor(tester);
    expect(p.runs, isEmpty);

    // Editar does nothing, with the hint.
    await tester.tap(key('compare-mode-B-edit'));
    await pumpFor(tester);
    expect(modeOn(tester, 'B', PromptMode.edit), isFalse);
    expect(
      tester.widget<Tooltip>(key('compare-edit-hint-B')).message,
      compareEditHint,
    );
  });

  testWidgets('the weight line shows the window and the week, amber at 80% '
      'or more (R4)', (tester) async {
    final p = CompareFakeProvider();
    final (_, c) = await pumpCompare(tester, provider: p);
    final now = DateTime.now();
    await tester.runAsync(
      () => c
          .read(rateLimitProvider.notifier)
          .record(parseUsageText(usageText(38, 61), now)!),
    );
    await tester.tap(key('prompt-compare'));
    await pumpFor(tester);
    expect(
      tester.widget<Text>(key('compare-usage')).data,
      'Roda dois agentes ao mesmo tempo · janela de 5 h em 38% · semana em '
      '61%',
    );
    await tester.runAsync(
      () => c
          .read(rateLimitProvider.notifier)
          .record(parseUsageText(usageText(86, 61), now)!),
    );
    await pumpFor(tester);
    final warn = tester.widget<Text>(key('compare-usage'));
    expect(warn.data, startsWith('A janela de 5 h está em 86% e renova às '));
    expect(warn.data, endsWith('Comparar pode esgotá-la.'));
    expect(warn.style!.color, const Color(0xFFF2A541));
    // Still sendable.
    expect(sendLabel(tester), 'Enviar os dois');
  });

  test('compareUsageLine without a reading', () {
    expect(
      compareUsageLine(null, DateTime.now()).text,
      'Roda dois agentes ao mesmo tempo',
    );
  });

  testWidgets('Ctrl+Shift+Enter turns Comparar on and sends with the default '
      'sides (R4)', (tester) async {
    final p = CompareFakeProvider();
    final (_, c) = await pumpCompare(
      tester,
      provider: p,
      usages: [usageText(38, 61)],
    );
    await tester.enterText(field, 'por que o cupom passa?');
    await tester.tap(field);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester, 20);
    expect(p.runs, hasLength(2));
    expect(p.runs[0].options.model, 'sonnet');
    expect(p.runs[1].options.model, 'opus');
    expect(p.runs[0].options.forkSession, isTrue);
    expect(p.runs[0].options.resumeId, 'conv-sid');
    expect(c.read(compareControllerProvider), hasLength(1));
    // R14: the composer waits for a choice.
    expect(find.text(compareBlockedMessage), findsWidgets);
    expect(sendLabel(tester), 'Escolha uma resposta');
    expect(key('prompt-compare'), findsNothing);
    await tester.tap(key('compare-stop-both'));
    await pumpFor(tester, 40);
  });
}
