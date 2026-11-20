import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/context_usage.dart';
import 'package:promptorium/core/claude/run_prefs.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/context/compaction_controller.dart';
import 'package:promptorium/features/context/context_snapshot.dart';
import 'package:promptorium/features/context/context_tracker.dart';
import 'package:promptorium/features/context/widgets/context_compaction.dart';

import '../../helpers/test_db.dart';

final t0 = DateTime(2026, 11, 20, 14, 36);

AgentEvent assistant(int tokens, {String id = 'a'}) => AgentEvent.fromJson({
  'type': 'assistant',
  'message': {
    'id': id,
    'model': 'claude-opus-5-5',
    'content': [],
    'usage': {
      'input_tokens': 2,
      'cache_creation_input_tokens': 0,
      'cache_read_input_tokens': tokens - 2,
    },
  },
});

final result = AgentEvent.fromJson({
  'type': 'result',
  'subtype': 'success',
  'num_turns': 1,
  'modelUsage': {
    'claude-opus-5-5': {'contextWindow': 1000000},
  },
});

AgentEvent usage(int threshold) => UnknownEvent(
  contextUsageEvent({
    'totalTokens': 1,
    'maxTokens': threshold + 33000,
    'autoCompactThreshold': threshold,
    'isAutoCompactEnabled': true,
    'model': 'claude-opus-5-5',
    'apiUsage': {},
  })!,
);

ContextSnapshot feed(List<AgentEvent> es) {
  final t = ContextTracker();
  for (final e in es) {
    t.apply(e, at: t0);
  }
  return t.snapshot;
}

Future<ProviderContainer> pump(WidgetTester tester, Widget child) async {
  final db = memoryDatabase();
  final c = ProviderContainer(overrides: [databaseOverride(db)]);
  await c.read(appSettingsProvider.notifier).load();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 520, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return c;
}

void main() {
  group('Auto compactar (R7)', () {
    testWidgets('a mudança vale para as próximas; a atual mantém o valor', (
      tester,
    ) async {
      final s = feed([
        UnknownEvent(ContextEventTypes.runEvent(autocompact: '200k')),
        assistant(120000),
        result,
        usage(167000),
      ]);
      final c = await pump(tester, AutocompactControl(snapshot: s));
      expect(find.textContaining('Esta execução usa este valor'), findsOne);
      expect(find.textContaining('compacta em 167 mil'), findsOne);
      await tester.tap(find.byKey(const ValueKey('context-autocompact-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('context-autocompact-300k')));
      await tester.pumpAndSettle();
      expect(c.read(runPrefsProvider).autocompact, '300k');
      expect(
        find.textContaining(
          '300 mil vale para as próximas execuções. Esta execução segue em '
          '200 mil (--autocompact 200k)',
        ),
        findsOne,
      );
      // "Padrão" restores the existing preference's default.
      await tester.tap(
        find.byKey(const ValueKey('context-autocompact-default')),
      );
      await tester.pumpAndSettle();
      expect(c.read(runPrefsProvider).autocompact, RunPrefs.defaultAutocompact);
    });
  });

  group('estados da compactação (R8)', () {
    test(
      'compactando, concluída aguardando medição, falhou e nada sem evento',
      () {
        Widget? row(List<AgentEvent> es) => compactionStatusRow(feed(es));
        AgentEvent status(String? s, [String? r]) => AgentEvent.fromJson({
          'type': 'system',
          'subtype': 'status',
          'status': s,
          'compact_result': ?r,
        });
        expect(
          row([assistant(1000), status('compacting')])!.key,
          const ValueKey('compaction-compacting'),
        );
        expect(
          row([
            assistant(1000),
            AgentEvent.fromJson({
              'type': 'system',
              'subtype': 'compact_boundary',
              'uuid': 'b',
              'compact_metadata': {'trigger': 'auto', 'pre_tokens': 1000},
            }),
          ])!.key,
          const ValueKey('compaction-pending'),
        );
        expect(
          row([assistant(1000), status('compacting'), status(null, 'failed')])!
              .key,
          const ValueKey('compaction-failed'),
        );
        expect(row([assistant(1000)]), isNull);
      },
    );
  });

  group('aviso (R10)', () {
    testWidgets('identifica a referência, não bloqueia e dispensa', (
      tester,
    ) async {
      final s = feed([result, usage(200000), assistant(182000)]);
      expect(s.warning, isNotNull);
      var dismissed = 0;
      var opened = 0;
      await pump(
        tester,
        ContextWarningBanner(
          snapshot: s,
          onOpenPanel: () => opened++,
          onDismiss: () => dismissed++,
          attachments: 2,
          onReviewAttachments: () {},
        ),
      );
      expect(
        find.textContaining(
          '182 mil = 91% do limiar de compactação (200 mil), não da janela '
          '(1 milhão). Faltam 18 mil tokens. O envio segue liberado.',
        ),
        findsOne,
      );
      expect(find.text('Revisar próximos anexos (2)'), findsOne);
      await tester.tap(find.byKey(const ValueKey('context-warning-open')));
      await tester.tap(find.byKey(const ValueKey('context-warning-dismiss')));
      expect((opened, dismissed), (1, 1));
    });
  });

  group('ações (R9)', () {
    testWidgets('Compactar agora desabilitado explica o motivo', (
      tester,
    ) async {
      final s = feed([assistant(1000)]);
      var calls = 0;
      await pump(
        tester,
        ContextActions(
          snapshot: s,
          availability: compactAvailability(
            provider: 'codex',
            busy: false,
            snapshot: s,
          ),
          onCompact: (_) async => calls++,
          onAdjust: () {},
        ),
      );
      expect(find.textContaining('não confirmou um comando nativo'), findsOne);
      await tester.tap(find.byKey(const ValueKey('context-compact-now')));
      await tester.pump();
      expect(calls, 0);
    });

    testWidgets('com suporte envia o foco; falha mantém a conversa', (
      tester,
    ) async {
      final s = feed([assistant(1000)]);
      final focus = <String?>[];
      var fail = false;
      await pump(
        tester,
        ContextActions(
          snapshot: s,
          availability: CompactAvailability.available,
          onCompact: (f) async {
            focus.add(f);
            if (fail) throw const FileSystemException('stdin fechada');
          },
          onAdjust: () {},
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('context-compact-focus')),
        'decisões do plano',
      );
      await tester.tap(find.byKey(const ValueKey('context-compact-now')));
      await tester.pump();
      expect(focus, ['decisões do plano']);
      fail = true;
      await tester.tap(find.byKey(const ValueKey('context-compact-now')));
      await tester.pump();
      expect(find.textContaining('A conversa segue como estava'), findsOne);
    });

    testWidgets('nova conversa: vazia direto, ou resumo revisado antes', (
      tester,
    ) async {
      final s = feed([assistant(1000)]);
      final started = <String?>[];
      await pump(
        tester,
        ContextActions(
          snapshot: s,
          availability: CompactAvailability.available,
          onCompact: (_) async {},
          onAdjust: () {},
          onNewConversation: started.add,
          summary: () => 'Continuação da conversa "X".',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('context-new-go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('context-summary-text')), findsOne);
      await tester.enterText(
        find.byKey(const ValueKey('context-summary-text')),
        'Resumo editado',
      );
      await tester.tap(find.byKey(const ValueKey('context-summary-use')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('context-new-empty')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('context-new-go')));
      await tester.pump();
      expect(started, ['Resumo editado', null]);
    });

    testWidgets('próximo envio: remover só tira do próximo envio', (
      tester,
    ) async {
      final removed = <String>[];
      await pump(
        tester,
        NextSendSection(
          paths: const ['/tmp/a/flutter-test.log', '/tmp/a/mock.png'],
          onRemove: removed.add,
        ),
      );
      expect(find.textContaining('não contam no contexto medido'), findsOne);
      await tester.tap(
        find.byKey(const ValueKey('context-next-remove-mock.png')),
      );
      expect(removed, ['/tmp/a/mock.png']);
    });
  });
}
