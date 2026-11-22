import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/codex/codex_hooks.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/automations_view.dart';
import 'package:promptorium/features/settings/secrets_view.dart'
    show secretsAgentWhere;
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-103 R8, R10: Automações with a column per provider.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester, {bool? python}) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        pythonAvailableProvider.overrideWith((ref) async => python),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AutomationsCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  String cell(WidgetTester tester, ManagedHook h, String provider) {
    final row = find.byKey(ValueKey('automation-${h.name}-$provider'));
    return tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data)
        .join();
  }

  testWidgets('no Codex session yet (the 0.170): Claude before the tool, '
      'Codex after the turn and the block at the approval; the text of both '
      'mechanisms', (tester) async {
    await pump(tester, python: true);
    expect(cell(tester, ManagedHook.block, 'claude'), 'Antes da ferramenta');
    expect(cell(tester, ManagedHook.format, 'claude'), 'Depois da edição');
    expect(cell(tester, ManagedHook.end, 'claude'), 'SessionEnd');
    expect(cell(tester, ManagedHook.block, 'codex'), 'Na aprovação');
    expect(cell(tester, ManagedHook.secrets, 'codex'), 'Ao fim do turno');
    expect(cell(tester, ManagedHook.format, 'codex'), 'Ao fim do turno');
    expect(cell(tester, ManagedHook.end, 'codex'), 'Ao fim do turno');
    expect(find.textContaining('Codex: hooks de sessão (-c'), findsOneWidget);
    expect(find.textContaining('nem no ~/.codex'), findsOneWidget);
    expect(find.textContaining('nunca usa --trust'), findsOneWidget);
    final tip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('automation-format-codex')),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tip.message, contains('formatar: nos arquivos alterados no turno'));
  });

  testWidgets('a Codex session with native hooks: before the tool; the last '
      'activity says which provider', (tester) async {
    final c = await pump(tester, python: true);
    c
        .read(codexHookStatusProvider.notifier)
        .set(
          's1',
          CodexHookStatus(
            mode: CodexHookMode.native,
            planned: ManagedHook.values.toSet(),
            active: ManagedHook.values.toSet(),
            at: DateTime.now(),
          ),
        );
    c
        .read(hookActivityProvider.notifier)
        .add(
          HookActivity(
            hook: ManagedHook.block,
            text: 'Hook bloqueou `git push --force` (git push --force)',
            at: DateTime(2026, 11, 21, 14, 22),
            error: true,
            provider: 'codex',
          ),
        );
    await tester.pumpAndSettle();
    expect(cell(tester, ManagedHook.block, 'codex'), 'Antes da ferramenta');
    expect(cell(tester, ManagedHook.format, 'codex'), 'Depois do apply_patch');
    expect(cell(tester, ManagedHook.end, 'codex'), 'sessionEnd');
    expect(
      find.text(
        'Último: Codex · Hook bloqueou `git push --force` (git push --force) '
        '· 14:22',
      ),
      findsOneWidget,
    );
  });

  testWidgets('off = Desligado in both; the switch is the same for both '
      'providers', (tester) async {
    final c = await pump(tester, python: true);
    await tester.tap(find.byKey(const ValueKey('automation-format')));
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)[ManagedHook.format.settingKey], '0');
    expect(cell(tester, ManagedHook.format, 'claude'), 'Desligado');
    expect(cell(tester, ManagedHook.format, 'codex'), 'Desligado');
  });

  testWidgets('R10: without python3, unavailable in both except the Vigia, '
      'which checks after the turn', (tester) async {
    await pump(tester, python: false);
    expect(find.byKey(const ValueKey('automations-no-python')), findsOneWidget);
    for (final p in ['claude', 'codex']) {
      expect(cell(tester, ManagedHook.block, p), 'Indisponível');
      expect(cell(tester, ManagedHook.secrets, p), 'Ao fim do turno');
    }
  });

  test('Vigia de segredos: the real state per provider and the last check', () {
    expect(
      secretsAgentWhere(python: true),
      'Claude Code: hook antes do comando. Codex: ao fim do turno e antes do '
      'push.',
    );
    expect(
      secretsAgentWhere(
        python: true,
        latest: const CodexHookStatus(
          mode: CodexHookMode.native,
          active: {ManagedHook.secrets},
        ),
        last: HookActivity(
          hook: ManagedHook.secrets,
          text: 'Vigia de segredos bloqueou o commit · 1 achado',
          at: DateTime(2026, 11, 21, 14, 20),
          provider: 'codex',
        ),
      ),
      'Claude Code: hook antes do comando. Codex: hook antes do comando. '
      'Última verificação: Codex · Vigia de segredos bloqueou o commit · 1 '
      'achado · 14:20',
    );
  });
}
