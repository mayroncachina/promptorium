import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/usage_poller.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/core/providers/agent_event.dart' show QuotaWindow;
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/features/prompt/compare/compare_controller.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/features/prompt/compare/widgets/compare_bar.dart';

import '../../../core/codex/fake_codex.dart';
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
    final warn = tester.widget<Text>(key('compare-usage-warning'));
    expect(
      warn.data,
      startsWith('A janela de 5 h do Claude está em 86% e renova às '),
    );
    expect(warn.data, endsWith('Comparar pode esgotá-la.'));
    expect(warn.style!.color, const Color(0xFFF2A541));
    // Still sendable.
    expect(sendLabel(tester), 'Enviar os dois');
  });

  test('compareUsageLine without a reading', () {
    expect(
      compareUsageLine({'claude': null}, DateTime.now()).text,
      'Roda dois agentes ao mesmo tempo',
    );
    expect(
      compareUsageLine({'claude': null, 'codex': null}, DateTime.now()).text,
      'Roda dois agentes ao mesmo tempo · Claude · sem leitura · Codex · sem '
      'leitura',
    );
  });

  QuotaSnapshot codexQuota(double five, double week) => QuotaSnapshot(
    provider: 'codex',
    main: QuotaBucket(
      id: 'codex',
      windows: [
        QuotaWindow(id: 'primary', label: '', usedPercent: five, minutes: 300),
        QuotaWindow(
          id: 'secondary',
          label: '',
          usedPercent: week,
          minutes: 10080,
        ),
      ],
    ),
  );

  test('SPEC-108 R5: the windows of each provider involved; amber with any '
      'of them at 80%, saying whose it is', () {
    final now = DateTime.now();
    final claude = claudeSnapshot(parseUsageText(usageText(38, 61), now)!);
    final line = compareUsageLine({
      'claude': claude,
      'codex': codexQuota(12, 30),
    }, now);
    expect(
      line.text,
      'Roda dois agentes ao mesmo tempo · Claude · janela de 5 h em 38% · '
      'semana em 61% · Codex · janela de 5 h em 12% · semana em 30%',
    );
    expect(line.warning, isNull);
    final warn = compareUsageLine({
      'claude': claude,
      'codex': codexQuota(12, 91),
    }, now);
    expect(
      warn.warning,
      'A semana do Codex está em 91%. Comparar pode esgotá-la.',
    );
    expect(warn.text, line.text.replaceAll('30%', '91%'));
  });

  testWidgets('SPEC-108 R1: each side has its provider, model and effort; the '
      'Codex ones come from model/list', (tester) async {
    final p = CompareFakeProvider();
    await pumpCompare(tester, provider: p, codex: []);
    await tester.tap(key('prompt-compare'));
    await pumpFor(tester);
    expect(key('compare-provider-A'), findsOneWidget);
    await tester.tap(key('compare-provider-B'));
    await pumpFor(tester);
    await tester.tap(key('compare-provider-B-codex').last);
    await pumpFor(tester);
    // The badge has the name, not only the color.
    expect(
      find.descendant(
        of: key('compare-provider-B'),
        matching: find.text('Codex'),
      ),
      findsOneWidget,
    );
    expect(modelOf(tester, 'B'), 'Padrão');
    await tester.tap(key('compare-model-B'));
    await pumpFor(tester);
    expect(key('compare-model-B-gpt-6.2-mini'), findsOneWidget);
    expect(key('compare-model-B-opus'), findsNothing);
    await tester.tap(key('compare-model-B-gpt-6.2-sol').last);
    await pumpFor(tester);
    expect(modelOf(tester, 'B'), 'gpt-6.2-sol');
    await tester.tap(key('compare-effort-B'));
    await pumpFor(tester, 25);
    // The efforts of the chosen model, nothing from the Claude.
    expect(key('compare-effort-B-high'), findsOneWidget);
    expect(key('compare-effort-B-max'), findsNothing);
    await tester.tap(key('compare-effort-B-high').last);
    await pumpFor(tester, 25);
    expect(
      find.descendant(
        of: key('compare-effort-B'),
        matching: find.text('high'),
      ),
      findsOneWidget,
    );
    // Another model without that effort goes to its default.
    await tester.tap(key('compare-model-B'));
    await pumpFor(tester, 25);
    await tester.tap(key('compare-model-B-gpt-6.2-mini').last);
    await pumpFor(tester, 25);
    expect(modelOf(tester, 'B'), 'gpt-6.2-mini');
    expect(find.text('high'), findsNothing);
  });

  testWidgets('SPEC-108 R1, R2, R4: "Claude × Codex" fills the sides, warns '
      'about the package and lets the person review and edit it', (
    tester,
  ) async {
    final servers = <FakeCodex>[];
    final p = CompareFakeProvider();
    await pumpCompare(
      tester,
      provider: p,
      codex: servers,
      usages: [usageText(38, 61)],
      codexUsages: [codexLimits(12, 30)],
    );
    await tester.enterText(field, 'por que o cupom passa?');
    await tester.tap(key('prompt-compare'));
    await pumpFor(tester);
    expect(key('compare-handoff-notice'), findsNothing);
    await tester.tap(key('compare-claude-codex'));
    await pumpFor(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await pumpFor(tester);
    expect(modelOf(tester, 'A'), 'Sonnet');
    expect(modelOf(tester, 'B'), 'Padrão');
    final notice = find.descendant(
      of: key('compare-handoff-notice'),
      matching: find.textContaining('B começa sem a sessão do Claude:'),
    );
    expect(notice, findsOneWidget);
    expect(
      tester.widget<Text>(notice).textSpan!.toPlainText(),
      allOf(
        contains('um resumo de ≈ '),
        contains('Os dois lados não partem exatamente do mesmo ponto.'),
      ),
    );
    await tester.tap(key('compare-handoff-show'));
    await pumpFor(tester);
    expect(key('compare-handoff-panel'), findsOneWidget);
    expect(find.text('lib/core/claude_process.dart'), findsWidgets);
    await tester.tap(key('compare-handoff-edit'));
    await pumpFor(tester);
    await tester.enterText(key('compare-handoff-field'), 'Resumo revisado');
    await tester.tap(key('compare-handoff-save'));
    await pumpFor(tester);
    expect(
      tester.widget<SelectableText>(key('compare-handoff-text')).data,
      'Resumo revisado',
    );
    // P1: both sides on the same package.
    await tester.tap(key('compare-same-handoff'));
    await pumpFor(tester);
    expect(
      find.textContaining('Os dois lados começam sem a sessão do Claude:'),
      findsOneWidget,
    );
    await tester.tap(key('compare-same-handoff'));
    await pumpFor(tester);
    await tester.tap(key('prompt-send'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await pumpFor(tester, 5);
    }
    expect(p.runs.single.options.resumeId, 'conv-sid');
    expect(
      ((codexParams(servers.single, 'turn/start')!['input'] as List).single
          as Map)['text'],
      'Resumo revisado\n\nPergunta atual:\npor que o cupom passa?',
    );
    await tester.tap(key('compare-stop-both'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await pumpFor(tester, 5);
    }
    for (final f in servers) {
      await tester.runAsync(f.finish);
    }
  });

  testWidgets('SPEC-108 R2: equal sides count the provider; the same model '
      'name on two efforts can be sent', (tester) async {
    const a = CompareChoice(model: 'inherit', mode: PromptMode.ask);
    const b = CompareChoice(
      provider: 'codex',
      model: 'inherit',
      mode: PromptMode.ask,
    );
    expect(compareSidesProblem(a, b), isNull);
    expect(compareSidesProblem(b, b), compareSameSidesMessage);
    expect(compareSidesProblem(a, a.copyWith(effort: 'high')), isNull);
    expect(decodeCompareSides(encodeCompareSides(a, b)), (a, b));
    // A pair saved before this version.
    expect(
      decodeCompareSides(
        '{"a":{"model":"sonnet","mode":"ask"},'
        '"b":{"model":"opus","mode":"ask"}}',
      )!.$1.provider,
      'claude',
    );
  });

  for (final (name, status, flows, text) in [
    (
      'not installed',
      const ProviderAvailability(ProviderStatus.missing, 'x'),
      null,
      'Codex não está instalado.',
    ),
    (
      'below 0.170',
      const ProviderAvailability(
        ProviderStatus.incompatible,
        'Versão instalada 0.169.0, mínimo 0.170.',
      ),
      null,
      'Codex: Versão instalada 0.169.0, mínimo 0.170.',
    ),
    (
      'without login',
      const ProviderAvailability(ProviderStatus.loginRequired, 'x'),
      null,
      'Codex sem login: rode codex login.',
    ),
    (
      'off in the Prompt',
      const ProviderAvailability(ProviderStatus.ready, 'ok'),
      ProviderFlows.defaults.copyWith('codex', const {AppFlow.compare}),
      flowLockedMessage('Codex', AppFlow.prompt),
    ),
  ]) {
    testWidgets('SPEC-108 R2: Codex $name: chip and option off, with the '
        'reason and "Abrir Provedores"', (tester) async {
      final p = CompareFakeProvider();
      final (_, c) = await pumpCompare(
        tester,
        provider: p,
        codex: [],
        codexStatus: status,
        flows: flows,
      );
      await tester.tap(key('prompt-compare'));
      await pumpFor(tester);
      expect(tester.widget<Text>(key('compare-codex-reason')).data, text);
      await tester.tap(key('compare-claude-codex'));
      await pumpFor(tester);
      expect(modelOf(tester, 'B'), 'Opus');
      await tester.tap(key('compare-provider-B'));
      await pumpFor(tester);
      expect(
        tester
            .widget<PopupMenuItem<String>>(key('compare-provider-B-codex').last)
            .enabled,
        isFalse,
      );
      await tester.tapAt(const Offset(5, 5));
      await pumpFor(tester);
      await tester.tap(key('compare-open-providers'));
      await pumpFor(tester);
      expect(c.read(navigationProvider), AppSection.settings);
      expect(
        c.read(selectedSettingsSectionProvider),
        SettingsSection.providers,
      );
    });
  }

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
