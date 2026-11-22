import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/core/providers/structured_run.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/provider_kind_card.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/widgets/run_provider_line.dart';

import '../../helpers/test_db.dart';

void main() {
  group('R9: ordem de resolução', () {
    test('tipo > rodapé do workspace > padrão global > claude', () {
      const k = ProviderKind.planner;
      expect(providerForKind(const {}, k), 'claude');
      expect(
        providerForKind({providerPreferenceKey(null): 'codex'}, k),
        'codex',
      );
      expect(
        providerForKind(
          {
            providerPreferenceKey(null): 'codex',
            providerPreferenceKey(3): 'claude',
          },
          k,
          workspaceId: 3,
        ),
        'claude',
      );
      expect(
        providerForKind(
          {providerPreferenceKey(3): 'claude', k.settingKey: 'codex'},
          k,
          workspaceId: 3,
        ),
        'codex',
      );
      // "Seguir o rodapé" = no choice.
      expect(
        providerForKind(
          {providerPreferenceKey(3): 'claude', k.settingKey: 'follow'},
          k,
          workspaceId: 3,
        ),
        'claude',
      );
    });

    test('uma linha não editável não guarda escolha e fica no Claude Code '
        'enquanto o fluxo não roda no Codex', () {
      final s = {
        providerPreferenceKey(null): 'codex',
        ProviderKind.reviewer.settingKey: 'codex',
      };
      // SPEC-102: the reviewer runs on the Codex, but its choice is the
      // project's (`revisor: provedor:`), never saved here.
      expect(providerKindChoice(s, ProviderKind.reviewer), isNull);
      expect(providerForKind(s, ProviderKind.sessions), 'codex');
    });

    test('execução em andamento > escolha no diálogo > tipo', () async {
      final c = ProviderContainer(
        overrides: [databaseOverride(memoryDatabase())],
      );
      addTearDown(c.dispose);
      final settings = c.read(appSettingsProvider.notifier);
      await settings.load();
      await settings.set(ProviderKind.planner.settingKey, 'codex');
      await settings.set('agent.run.r1.provider', 'claude');
      String of(StructuredIntent i) =>
          c.read(Provider((ref) => structuredProviderFor(ref, i, null)));
      expect(of(const StructuredIntent(cwd: '/', prompt: 'x')), 'codex');
      expect(
        of(const StructuredIntent(cwd: '/', prompt: 'x', providerId: 'claude')),
        'claude',
      );
      expect(
        of(
          const StructuredIntent(
            cwd: '/',
            prompt: 'x',
            providerId: 'codex',
            resumeId: 'r1',
          ),
        ),
        'claude',
      );
    });
  });

  group('cartão Provedor por tipo', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required ProviderStatus codex,
      Map<String, String> settings = const {},
    }) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          providerAvailabilityProvider.overrideWith(
            (ref, id) async => ProviderAvailability(
              id == 'codex' ? codex : ProviderStatus.ready,
              '',
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        await c.read(appSettingsProvider.notifier).load();
        for (final MapEntry(:key, :value) in settings.entries) {
          await c.read(appSettingsProvider.notifier).set(key, value);
        }
        // The app probes the Codex at startup; the card only reads it.
        await c.read(providerAvailabilityProvider('codex').future);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: SingleChildScrollView(child: ProviderKindCard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('grava a escolha de Planner e assistentes; as outras linhas '
        'mostram o estado atual e a ordem', (tester) async {
      final c = await pump(tester, codex: ProviderStatus.ready);
      expect(find.text('Planner e assistentes'), findsOneWidget);
      expect(find.text('segue o rodapé:'), findsOneWidget);
      // SPEC-101 R1: "Executar spec" is editable now; SPEC-102: the reviewer
      // row shows the project's choice; only the two Claude-only flows keep
      // the tag.
      expect(find.text('Só Claude Code'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('kind-runSpec-codex')));
      await tester.pumpAndSettle();
      expect(
        c.read(appSettingsProvider)[ProviderKind.runSpec.settingKey],
        'codex',
      );
      expect(
        providerForKind(c.read(appSettingsProvider), ProviderKind.runSpec),
        'codex',
      );
      expect(find.byKey(const ValueKey('provider-kind-order')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kind-planner-codex')));
      await tester.pumpAndSettle();
      expect(
        c.read(appSettingsProvider)[ProviderKind.planner.settingKey],
        'codex',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kind-planner-model')))
            .data,
        startsWith('Codex · '),
      );
      await tester.tap(find.byKey(const ValueKey('kind-planner-follow')));
      await tester.pumpAndSettle();
      expect(
        c.read(appSettingsProvider)[ProviderKind.planner.settingKey],
        isNull,
      );
    });

    testWidgets('Revisor automático mostra o valor do projeto e leva à '
        'Configuração do projeto, sem guardar escolha (SPEC-102 R4)', (
      tester,
    ) async {
      final c = await pump(tester, codex: ProviderStatus.ready);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kind-reviewer-value')))
            .data,
        'do projeto: Mesmo da execução',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kind-reviewer-models')))
            .data,
        'Claude Code haiku · Codex modelo do tipo',
      );
      expect(find.byKey(const ValueKey('kind-reviewer-codex')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('kind-reviewer-open-project')),
      );
      await tester.pumpAndSettle();
      expect(c.read(selectedSettingsSectionProvider), SettingsSection.project);
      expect(
        c.read(appSettingsProvider)[ProviderKind.reviewer.settingKey],
        isNull,
      );
    });

    testWidgets('o Codex indisponível não aparece como opção nova, e uma '
        'escolha salva continua Codex (R9, R11)', (tester) async {
      await pump(tester, codex: ProviderStatus.missing);
      expect(find.byKey(const ValueKey('kind-planner-codex')), findsNothing);
    });

    testWidgets('escolha salva no Codex fica mesmo com o Codex sem login', (
      tester,
    ) async {
      final c = await pump(
        tester,
        codex: ProviderStatus.loginRequired,
        settings: {ProviderKind.planner.settingKey: 'codex'},
      );
      expect(find.byKey(const ValueKey('kind-planner-codex')), findsOneWidget);
      expect(
        providerForKind(c.read(appSettingsProvider), ProviderKind.planner),
        'codex',
      );
    });
  });

  group('R10, R11: linha do provedor nos diálogos', () {
    Future<ProviderContainer> pumpLine(
      WidgetTester tester,
      StructuredRunInfo info, {
      VoidCallback? onRetry,
    }) async {
      final c = ProviderContainer(
        overrides: [databaseOverride(memoryDatabase())],
      );
      addTearDown(c.dispose);
      c.read(structuredRunsProvider.notifier).put('s', info);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 600,
                child: RunProviderLine(slot: 's', onRetry: onRetry),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('Codex: modelo, tokens e "custo indisponível"', (tester) async {
      await pumpLine(
        tester,
        const StructuredRunInfo(
          provider: 'codex',
          model: 'gpt-6.1-terra',
          running: false,
          tokens: 14200,
          elapsed: Duration(minutes: 1, seconds: 12),
        ),
      );
      expect(find.text('Codex'), findsOneWidget);
      expect(
        find.text(
          'gpt-6.1-terra · 14 mil tokens · custo indisponível · 1 min 12 s',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Claude Code: custo em US\$ quando o provedor informa', (
      tester,
    ) async {
      await pumpLine(
        tester,
        const StructuredRunInfo(
          provider: 'claude',
          model: 'opus',
          running: false,
          tokens: 900,
          costUsd: 0.42,
        ),
      );
      expect(find.textContaining('US\$ 0,42'), findsOneWidget);
    });

    testWidgets('falha ao iniciar: diz qual e por quê e oferece o outro só '
        'desta vez', (tester) async {
      var retried = 0;
      final c = await pumpLine(
        tester,
        const StructuredRunInfo(
          provider: 'codex',
          model: null,
          running: false,
          failure: StructuredProviderFailure(
            'Falha ao iniciar Codex: sem login',
            provider: 'codex',
            reason: 'Codex sem autenticação. Execute `codex login`.',
            alternative: 'claude',
          ),
        ),
        onRetry: () => retried++,
      );
      expect(find.text('O Codex não pôde rodar esta execução'), findsOneWidget);
      expect(find.textContaining('codex login'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-use-other')));
      await tester.pumpAndSettle();
      expect(retried, 1);
      final once = c.read(structuredRunsProvider.notifier).peekOnce('s');
      expect(once?.provider, 'claude');
      // The saved preference does not change.
      expect(
        c.read(appSettingsProvider)[ProviderKind.planner.settingKey],
        isNull,
      );
    });

    testWidgets('modelo sem imagem: avisa e oferece enviar sem os prints '
        '(R6)', (tester) async {
      var retried = 0;
      final c = await pumpLine(
        tester,
        const StructuredRunInfo(
          provider: 'codex',
          model: 'gpt-6-luna',
          running: false,
          failure: StructuredImagesUnsupported(
            'O modelo gpt-6-luna do Codex não lê imagens.',
            provider: 'codex',
            model: 'gpt-6-luna',
            count: 2,
          ),
        ),
        onRetry: () => retried++,
      );
      expect(
        find.text('O modelo gpt-6-luna do Codex não lê imagens.'),
        findsOneWidget,
      );
      expect(find.textContaining('2 prints'), findsOneWidget);
      expect(find.text('Usar o Claude Code desta vez'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-send-without-prints')));
      await tester.pumpAndSettle();
      expect(retried, 1);
      expect(
        c.read(structuredRunsProvider.notifier).peekOnce('s')?.dropImages,
        isTrue,
      );
    });
  });
}
