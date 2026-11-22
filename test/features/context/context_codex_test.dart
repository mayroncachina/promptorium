import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/run_prefs.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/context_events.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/context/compaction_controller.dart';
import 'package:promptorium/features/context/context_snapshot.dart';
import 'package:promptorium/features/context/context_sources.dart';
import 'package:promptorium/features/context/context_tracker.dart';
import 'package:promptorium/features/context/widgets/context_chart.dart';
import 'package:promptorium/features/context/widgets/context_compaction.dart';
import 'package:promptorium/features/context/widgets/context_indicator.dart';
import 'package:promptorium/features/context/widgets/context_panel.dart';
import 'package:promptorium/features/sessions/replay/replay_state.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../helpers/test_db.dart';

/// SPEC-107 T2–T4: the SPEC-087 contract fed by the Codex events.

final t0 = DateTime(2026, 11, 22, 14, 31);

const _model = 'gpt-6.1-terra';

/// The `tokenUsage.last` of one call as the adapter stores it.
AgentEvent reading(
  int tokens, {
  int? window = 400000,
  int cached = 0,
  int output = 0,
  int cacheWrite = 0,
  String model = _model,
  String turnId = 't',
}) => AgentEvent.fromJson(
  ContextUsageEvent.toJson(
    provider: 'codex',
    tokens: tokens,
    input: tokens - cached - output,
    cacheRead: cached,
    cacheWrite: cacheWrite,
    output: output,
    window: window,
    model: model,
    turnId: turnId,
    source: ContextUsageEvent.codexTokenUsage,
  ),
);

AgentEvent turnEnd() => AgentEvent.fromJson({
  'type': 'result',
  'subtype': 'success',
  'num_turns': 1,
  'provider': 'codex',
});

AgentEvent compaction(
  CompactionEventPhase phase, {
  String key = 'cc-1',
  String trigger = 'auto',
  int? post,
}) => AgentEvent.fromJson(
  CompactionEvent.toJson(
    provider: 'codex',
    phase: phase,
    trigger: trigger,
    key: key,
    postTokens: post,
  ),
);

AgentEvent run({String? autocompact = '300k'}) => UnknownEvent(
  ContextEventTypes.runEvent(
    autocompact: autocompact,
    model: _model,
    provider: 'codex',
  ),
);

AgentEvent rerouted(String from, String to) => UnknownEvent(
  ContextAppEvents.modelChangeEvent(
    provider: 'codex',
    from: from,
    to: to,
    reason: ContextAppEvents.rerouted,
  ),
);

ContextTracker feed(List<AgentEvent> es) {
  final t = ContextTracker();
  for (final e in es) {
    t.apply(e, at: t0);
  }
  return t;
}

/// The stored JSON of [e], as a reopened session reads it.
String stored(AgentEvent e) => eventJson(e);

void main() {
  group('R1 · readings never accumulate', () {
    test('several readings per turn: the newest replaces; a compaction '
        'makes it fall', () {
      final s = feed([
        run(),
        reading(120000, turnId: 't1'),
        reading(150000, turnId: 't1'),
        turnEnd(),
        reading(288000, turnId: 't2'),
        compaction(CompactionEventPhase.started),
        compaction(CompactionEventPhase.completed, post: 52000),
        reading(52000, turnId: 't2'),
        turnEnd(),
      ]).snapshot;
      expect(s.current!.tokens, 52000);
      expect(s.readings.map((r) => r.tokens), [120000, 150000, 288000, 52000]);
      final m = s.lastCompaction!;
      expect((m.preTokens, m.postTokens), (288000, 52000));
      expect(markerLines(s).single, contains('288 mil → 52 mil'));
    });

    test('P5: the chart keeps the last reading of each turn; the detail '
        'keeps them all', () {
      final s = feed([
        reading(100000, turnId: 't1'),
        reading(110000, turnId: 't1'),
        reading(130000, turnId: 't1'),
        turnEnd(),
        reading(140000, turnId: 't2'),
        turnEnd(),
      ]).snapshot;
      expect(s.readings, hasLength(4));
      expect(contextPoints(s).map((p) => p.reading.tokens), [130000, 140000]);
      expect(s.readings.map((r) => r.turnId), ['t1', 't1', 't1', 't2']);
    });
  });

  group('R2 · capacity', () {
    test('modelContextWindow is the capacity; without it, no percent', () {
      final withWindow = feed([reading(241000)]).snapshot;
      expect(withWindow.capacity, 400000);
      expect(withWindow.percent, 60);
      final without = feed([reading(241000, window: null)]).snapshot;
      expect(without.capacity, isNull);
      expect(without.percent, isNull);
    });

    testWidgets('the meter shows the total without a percent', (tester) async {
      final s = feed([reading(241000, window: null), turnEnd()]).snapshot;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextIndicator(snapshot: s, onOpen: () {}),
          ),
        ),
      );
      final text = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText())
          .join(' ');
      expect(text, contains('241 mil'));
      expect(text, contains('limite desconhecido'));
      expect(text, isNot(contains('%')));
    });
  });

  group('R3 · composition only when measured', () {
    test('new input, cache read, cache write and output add up', () {
      final c = feed([reading(241000, cached: 233000, output: 1000)])
          .snapshot
          .current!;
      expect(c.hasComposition, isTrue);
      expect(c.input, 7000);
      expect(c.isCodex, isTrue);
    });

    test('overlapping parts: "Detalhamento indisponível"', () {
      // Cache write counted inside the input: the parts pass the total.
      final c = feed([
        AgentEvent.fromJson(
          ContextUsageEvent.toJson(
            provider: 'codex',
            tokens: 1000,
            input: 900,
            cacheWrite: 300,
            source: ContextUsageEvent.codexTokenUsage,
          ),
        ),
      ]).snapshot.current!;
      expect(c.hasComposition, isFalse);
    });
  });

  group('R4, R5 · reopening', () {
    test('stored readings come back as history, never live', () {
      final events = [
        run(),
        reading(200000, turnId: 't1'),
        turnEnd(),
        reading(241000, turnId: 't18'),
        turnEnd(),
      ];
      final t = Timeline();
      for (final e in events) {
        t.applyStored(stored(e), at: t0);
      }
      final s = t.context.snapshot;
      expect(s.current!.tokens, 241000);
      expect(s.current!.live, isFalse);
      expect(s.current!.turnId, 't18');
      expect(s.measuredLabel, 'última medição às 14:31 · turno 2');
      expect(s.warning, isNull);
    });

    test('old Codex events without readings do not invent history', () {
      final t = Timeline();
      for (final j in [
        {
          'type': 'system',
          'subtype': 'codex_notification',
          'method': 'thread/tokenUsage/updated',
          'provider': 'codex',
        },
        {
          'type': 'result',
          'subtype': 'success',
          'num_turns': 1,
          'provider': 'codex',
          'usage': {'input_tokens': 9000, 'output_tokens': 30},
        },
      ]) {
        t.applyStored(eventJson(AgentEvent.fromJson(j)), at: t0);
      }
      final s = t.context.snapshot;
      expect(s.readings, isEmpty);
      expect(s.current, isNull);
      expect(s.capacity, isNull);
      expect(
        contextIndicatorParts(s).first.toPlainText(),
        'Aguardando medição',
      );
    });
  });

  group('R6 · threshold', () {
    test('the value sent to the Codex is the threshold; 85% warns', () {
      final t = feed([run(), reading(241000)]);
      var s = t.snapshot;
      expect(s.threshold, 300000);
      expect(s.thresholdSource, ContextThresholdSource.sent);
      expect(s.untilCompaction, 59000);
      expect(
        codexAutocompactLine(s),
        contains('em 300 mil (enviado ao Codex)'),
      );
      expect(s.warning, isNull);
      t.apply(reading(260000), at: t0);
      s = t.snapshot;
      expect(s.warning!.kind, ContextReference.threshold);
      expect(s.warning!.percent, 87);
      // Rearmed below 75%.
      t.apply(reading(200000), at: t0);
      expect(t.snapshot.warning, isNull);
    });

    test('"padrão do agente" without a value; config/read wins', () {
      final t = feed([run(autocompact: 'auto'), reading(241000)]);
      expect(t.snapshot.threshold, isNull);
      expect(
        codexAutocompactLine(t.snapshot),
        'Auto compactar: padrão do agente',
      );
      t.apply(
        UnknownEvent(
          ContextAppEvents.agentConfigEvent(
            provider: 'codex',
            autocompactLimit: 250000,
            autocompactScope: 'body_after_prefix',
          ),
        ),
        at: t0,
      );
      final s = t.snapshot;
      expect(s.threshold, 250000);
      expect(s.thresholdSource, ContextThresholdSource.config);
      expect(
        codexAutocompactLine(s),
        'Auto compactar: em 250 mil (efetivo, lido do Codex) · escopo: corpo '
        'depois do prefixo',
      );
    });

    test('the Codex preference is separate from Claude\'s (P1)', () {
      var prefs = const RunPrefs({});
      expect(prefs.codexAutocompact, 'auto');
      expect(prefs.autocompact, '200k');
      prefs = const RunPrefs({AppSettingKeys.codexAutocompact: '300k'});
      expect(prefs.autocompactOf('codex'), '300k');
      expect(prefs.autocompactOf('claude'), '200k');
      prefs = const RunPrefs({AppSettingKeys.autocompact: '500k'});
      expect(prefs.autocompactOf('codex'), 'auto');
      expect(RunPrefs.autocompactKey('codex'), 'codex.autocompact');
      expect(RunPrefs.autocompactKey('claude'), 'claude.autocompact');
      expect(prefs.autocompactOf('gemini'), isNull);
    });
  });

  group('R7 · compaction states', () {
    test('compacting → done once per item; pending until the next reading', () {
      final t = feed([run(), reading(288000)]);
      t.apply(compaction(CompactionEventPhase.started), at: t0);
      expect(t.snapshot.phase, CompactionPhase.compacting);
      for (var i = 0; i < 2; i++) {
        t.apply(compaction(CompactionEventPhase.completed), at: t0);
      }
      // A reopened history replays the same rows.
      t.apply(compaction(CompactionEventPhase.completed), at: t0);
      var s = t.snapshot;
      expect(
        s.markers.where((m) => m.kind == ContextMarkerKind.compaction),
        hasLength(1),
      );
      expect(s.phase, CompactionPhase.done);
      expect(s.current, isNull);
      expect(s.pendingAfterCompaction, isTrue);
      expect(
        contextIndicatorParts(s).first.toPlainText(),
        'Contexto compactado · aguardando medição',
      );
      t.apply(reading(52000), at: t0);
      s = t.snapshot;
      expect(s.current!.tokens, 52000);
      expect(s.pendingAfterCompaction, isFalse);
    });

    test('a failure keeps the reading and says why', () {
      final t = feed([reading(288000)]);
      t.apply(compaction(CompactionEventPhase.started), at: t0);
      t.apply(
        AgentEvent.fromJson(
          CompactionEvent.toJson(
            provider: 'codex',
            phase: CompactionEventPhase.failed,
            key: 'cc-1',
            error: 'falhou ao resumir',
          ),
        ),
        at: t0,
      );
      final s = t.snapshot;
      expect(s.phase, CompactionPhase.failed);
      expect(s.compactError, 'falhou ao resumir');
      expect(s.current!.tokens, 288000);
    });
  });

  group('R8 · Compactar agora by the capability', () {
    test('Codex with a reading and idle; busy or empty, not', () {
      final s = feed([reading(241000)]).snapshot;
      expect(
        compactAvailability(provider: 'codex', busy: false, snapshot: s).ok,
        isTrue,
      );
      expect(
        compactAvailability(provider: 'codex', busy: true, snapshot: s).ok,
        isFalse,
      );
      expect(
        compactAvailability(
          provider: 'codex',
          busy: false,
          snapshot: ContextSnapshot.empty,
        ).ok,
        isFalse,
      );
    });
  });

  group('R12 · subagents and model changes', () {
    test('a subagent never enters the main reading', () {
      final t = feed([
        reading(100000),
        AgentEvent.fromJson({
          'type': 'assistant',
          'provider': 'codex',
          'message': {
            'id': 'sa',
            'content': [
              {
                'type': 'tool_use',
                'id': 'sa',
                'name': 'Agent',
                'input': {
                  'prompt': 'explore',
                  'threads': ['7f2e9a10-sub'],
                },
              },
            ],
          },
        }),
      ]);
      final s = t.snapshot;
      expect(s.current!.tokens, 100000);
      expect(s.readings, hasLength(1));
      expect(s.subagents, ['subagente']);
      final row = t.sources.grouped[ContextSourceGroup.subagents]!.single;
      expect(row.label, 'subagente (thread 7f2e…)');
      expect(row.stateLabel(1), 'contexto separado · medição indisponível');
      expect(row.weightLabel, 'peso indisponível');
    });

    test('model/rerouted marks and invalidates the capacity', () {
      final t = feed([run(), reading(241000, model: 'gpt-6.2-sol')]);
      expect(t.snapshot.capacity, 400000);
      t.apply(rerouted('gpt-6.2-sol', 'gpt-6.1-terra'), at: t0);
      var s = t.snapshot;
      final m = s.markers.single;
      expect(m.kind, ContextMarkerKind.modelChange);
      expect(m.rerouted, isTrue);
      expect(s.capacity, isNull);
      expect(s.percent, isNull);
      // The threshold the app sent still holds.
      expect(s.threshold, 300000);
      expect(markerLines(s).single, contains('redirecionado pelo serviço'));
      // The next reading reports the new capacity.
      t.apply(reading(150000, window: 272000), at: t0);
      s = t.snapshot;
      expect(s.capacity, 272000);
      expect(s.markers, hasLength(1));
    });

    test('the timeline says the model was rerouted', () {
      final t = Timeline()..apply(rerouted('gpt-6.2-sol', 'gpt-6.1-terra'));
      expect(
        t.items.whereType<NoticeItem>().single.text,
        'Modelo trocado: gpt-6.2-sol → gpt-6.1-terra · redirecionado pelo '
        'serviço',
      );
    });
  });

  group('R10, R11 · sources', () {
    test('instructions, command reads, MCP calls: all without weight', () {
      final t = feed([
        UnknownEvent(
          ContextAppEvents.instructionsEvent(
            provider: 'codex',
            sources: ['/w/AGENTS.md', '/w/packages/api/CLAUDE.md'],
          ),
        ),
        AgentEvent.fromJson(
          CommandEvent.toJson(
            provider: 'codex',
            toolUseId: 'c1',
            command:
                "zsh -lc 'sed -n 1,120p lib/cache.dart; rg expiresAt lib/'",
            cwd: '/w',
            status: CommandStatus.completed,
            actions: const [
              CommandAction(type: 'read', path: '/w/lib/cache.dart'),
              CommandAction(type: 'search', path: 'lib/', query: 'expiresAt'),
              CommandAction(type: 'listFiles'),
            ],
          ),
        ),
        AgentEvent.fromJson(
          CommandEvent.toJson(
            provider: 'codex',
            toolUseId: 'c2',
            command: 'rm apagar.txt',
            status: CommandStatus.completed,
          ),
        ),
        AgentEvent.fromJson({
          'type': 'assistant',
          'provider': 'codex',
          'message': {
            'id': 'm1',
            'content': [
              {
                'type': 'tool_use',
                'id': 'm1',
                'name': 'mcp__github__search_issues',
                'input': {},
              },
            ],
          },
        }),
      ]);
      final g = t.sources.grouped;
      final instructions = g[ContextSourceGroup.instructions]!;
      expect(instructions.map((s) => s.label), [
        '/w/packages/api/CLAUDE.md',
        '/w/AGENTS.md',
      ]);
      expect(
        instructions.first.stateLabel(1),
        'carregamento informado pelo agente',
      );
      final files = g[ContextSourceGroup.files]!;
      expect(files.map((s) => (s.label, s.detail)), [
        ('/w', 'listFiles'),
        ('lib/ · "expiresAt"', 'search'),
        ('/w/lib/cache.dart', 'read'),
      ]);
      expect(files.last.stateLabel(1), 'leitura observada (comando) · t1');
      final mcp = g[ContextSourceGroup.tools]!.single;
      expect(mcp.label, 'github · search_issues');
      expect(mcp.stateLabel(1), 'chamada MCP · t1');
      for (final s in [...instructions, ...files, mcp]) {
        expect(s.weightLabel, 'peso indisponível');
      }
      // A command without classified actions is not a read (P4).
      expect(files.where((s) => s.label.contains('apagar')), isEmpty);
    });

    test('after a compaction the command reads become history; the loaded '
        'instructions stay', () {
      final t = feed([
        UnknownEvent(
          ContextAppEvents.instructionsEvent(
            provider: 'codex',
            sources: ['/w/AGENTS.md'],
          ),
        ),
        AgentEvent.fromJson(
          CommandEvent.toJson(
            provider: 'codex',
            toolUseId: 'c1',
            command: 'ls test/catalog',
            status: CommandStatus.completed,
            actions: const [
              CommandAction(type: 'listFiles', path: 'test/catalog/'),
            ],
          ),
        ),
        reading(288000),
        compaction(CompactionEventPhase.completed),
      ]);
      final g = t.sources.grouped;
      expect(g[ContextSourceGroup.files]!.single.historical, isTrue);
      expect(g[ContextSourceGroup.instructions]!.single.historical, isFalse);
    });
  });

  group('R13 · Comparar and Replay', () {
    test('each Compare side keeps its own meter, never summed', () {
      final a = Timeline()
        ..apply(
          AgentEvent.fromJson({
            'type': 'assistant',
            'message': {
              'id': 'x',
              'model': 'claude-opus-5-5',
              'content': [],
              'usage': {
                'input_tokens': 10,
                'cache_creation_input_tokens': 0,
                'cache_read_input_tokens': 90000,
              },
            },
          }),
        );
      final b = Timeline()
        ..apply(run())
        ..apply(reading(241000));
      expect(a.context.snapshot.current!.tokens, 90010);
      expect(b.context.snapshot.current!.tokens, 241000);
      expect(b.context.snapshot.threshold, 300000);
      expect(a.context.snapshot.threshold, isNull);
    });

    test('the Replay reads the reading of the selected point', () {
      final t = Timeline()
        ..apply(run())
        ..apply(
          AgentEvent.fromJson({
            'type': 'assistant',
            'provider': 'codex',
            'message': {
              'id': 'a1',
              'content': [
                {'type': 'text', 'text': 'primeira resposta'},
              ],
            },
          }),
        )
        ..apply(reading(120000, turnId: 't1'))
        ..apply(turnEnd())
        ..apply(
          AgentEvent.fromJson({
            'type': 'assistant',
            'provider': 'codex',
            'message': {
              'id': 'a2',
              'content': [
                {'type': 'text', 'text': 'segunda resposta'},
              ],
            },
          }),
        )
        ..apply(reading(241000, turnId: 't2'))
        ..apply(turnEnd());
      final steps = replaySteps(t.items, root: '/w');
      ReplayState at(int i) => replayStateAt(
        steps,
        i,
        context: t.contextTokens,
        ctx: t.context.snapshot,
      );
      final turns = [
        for (var i = 0; i < steps.length; i++)
          if (steps[i].itemIndex >= 0) i,
      ];
      expect(at(turns.last).contextTokens, 241000);
      final first = turns.firstWhere((i) => at(i).contextTokens != null);
      expect(at(first).contextTokens, 120000);
      expect(at(first).capacity, 400000);
    });
  });

  group('R6, R9 · panel widgets', () {
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
                child: SizedBox(width: 560, child: child),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return c;
    }

    testWidgets('the Codex threshold: sent value, own preference, Claude '
        'apart', (tester) async {
      final s = feed([run(), reading(241000)]).snapshot;
      final c = await pump(tester, AutocompactControl(snapshot: s));
      await c
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.codexAutocompact, '300k');
      await tester.pump();
      expect(find.text('Auto compactar · Codex'), findsOne);
      expect(find.text('Claude: 200 mil, separado'), findsOne);
      expect(find.textContaining('Enviado ao Codex nesta execução'), findsOne);
      await tester.tap(find.byKey(const ValueKey('context-autocompact-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('context-autocompact-500k')));
      await tester.pumpAndSettle();
      final prefs = c.read(runPrefsProvider);
      expect(prefs.codexAutocompact, '500k');
      // Changing the Codex never touches Claude.
      expect(prefs.autocompact, RunPrefs.defaultAutocompact);
      expect(find.textContaining('Esta segue em 300 mil'), findsOne);
    });

    testWidgets('Compactar agora in the Codex: no focus field, no focus sent', (
      tester,
    ) async {
      final s = feed([run(), reading(241000)]).snapshot;
      final focus = <String?>[];
      await pump(
        tester,
        ContextActions(
          snapshot: s,
          provider: 'codex',
          availability: compactAvailability(
            provider: 'codex',
            busy: false,
            snapshot: s,
          ),
          onCompact: (f) async => focus.add(f),
          onAdjust: () {},
        ),
      );
      expect(find.byKey(const ValueKey('context-compact-focus')), findsNothing);
      expect(
        find.text('Foco do resumo: o Codex não aceita foco na compactação.'),
        findsOne,
      );
      expect(find.textContaining('thread/compact/start'), findsOne);
      await tester.tap(find.byKey(const ValueKey('context-compact-now')));
      await tester.pump();
      expect(focus, [null]);
    });

    testWidgets('the Uso tab of the Codex: source, composition, categories', (
      tester,
    ) async {
      final t = feed([run(), reading(241000, cached: 233000, output: 1800)]);
      await pump(
        tester,
        SizedBox(
          height: 900,
          child: ContextPanel(
            snapshot: t.snapshot,
            sources: t.sources,
            place: 'Sessão',
            tab: ContextTab.usage,
            onTab: (_) {},
            onClose: () {},
          ),
        ),
      );
      expect(find.text('fonte: thread/tokenUsage (last)'), findsOne);
      final composition = tester
          .widget<Text>(find.byKey(const ValueKey('context-composition-codex')))
          .textSpan!
          .toPlainText();
      expect(composition, contains('Entrada nova 6,2 mil'));
      expect(composition, contains('leitura de cache 233 mil'));
      expect(composition, contains('saída da chamada 1,8 mil'));
      expect(composition, contains('detalhamento indisponível no Codex'));
    });
  });
}
