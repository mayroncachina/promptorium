import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/context_usage.dart';
import 'package:promptorium/features/context/context_snapshot.dart';
import 'package:promptorium/features/context/context_sources.dart';
import 'package:promptorium/features/context/context_tracker.dart';
import 'package:promptorium/features/sessions/timeline.dart';

// Payloads shaped like the sanitized ones of
// docs/pesquisa/contexto-e-compactacao.md (CLI 2.1.329).
final t0 = DateTime(2026, 11, 20, 14, 0);

AgentEvent assistant(
  int input,
  int write,
  int read, {
  String id = 'm1',
  String model = 'claude-opus-5-5',
  String? parent,
  List<Map<String, dynamic>> content = const [],
}) => AgentEvent.fromJson({
  'type': 'assistant',
  'message': {
    'id': id,
    'model': model,
    'content': content,
    'usage': {
      'input_tokens': input,
      'cache_creation_input_tokens': write,
      'cache_read_input_tokens': read,
      'output_tokens': 40,
    },
  },
  'parent_tool_use_id': parent,
});

AgentEvent result({
  int window = 1000000,
  String model = 'claude-opus-5-5',
  int turns = 1,
}) => AgentEvent.fromJson({
  'type': 'result',
  'subtype': 'success',
  'num_turns': turns,
  'usage': {
    'input_tokens': 9,
    'cache_creation_input_tokens': 9999,
    'cache_read_input_tokens': 99999,
    'output_tokens': 80,
  },
  'modelUsage': {
    model: {'contextWindow': window, 'maxOutputTokens': 128000},
  },
});

AgentEvent init(String model) => AgentEvent.fromJson({
  'type': 'system',
  'subtype': 'init',
  'model': model,
  'session_id': 's',
  'tools': ['Read', 'mcp__github__a', 'mcp__github__b'],
  'mcp_servers': [
    {'name': 'github', 'status': 'connected'},
  ],
});

AgentEvent status(String? s, {String? result, String? error}) =>
    AgentEvent.fromJson({
      'type': 'system',
      'subtype': 'status',
      'status': s,
      'compact_result': ?result,
      'compact_error': ?error,
    });

AgentEvent boundary({String uuid = 'b1', int pre = 171000, int post = 30000}) =>
    AgentEvent.fromJson({
      'type': 'system',
      'subtype': 'compact_boundary',
      'uuid': uuid,
      'compact_metadata': {
        'trigger': 'auto',
        'pre_tokens': pre,
        'post_tokens': post,
      },
    });

AgentEvent usageAnswer({
  int threshold = 167000,
  int max = 200000,
  String model = 'claude-opus-5-5',
  bool measured = true,
}) => UnknownEvent(
  contextUsageEvent({
    'totalTokens': 1,
    'maxTokens': max,
    'autoCompactThreshold': threshold,
    'isAutoCompactEnabled': true,
    'autocompactSource': 'settings',
    'model': model,
    'apiUsage': measured ? {'input_tokens': 1} : null,
    'categories': [
      {
        'id': 'system_prompt',
        'name': 'System prompt',
        'tokens': 3531,
        'kind': 'used',
      },
      {
        'id': 'memory_files',
        'name': 'Memory files',
        'tokens': 900,
        'kind': 'used',
      },
      {'id': 'free_space', 'name': 'Free space', 'tokens': 9, 'kind': 'free'},
    ],
    'skills': {
      'skillFrontmatter': [
        {'path': '/home/x/SKILL.md'},
      ],
    },
  })!,
);

AgentEvent user(String text) =>
    UnknownEvent(AppEventTypes.userMessage(text, t0));

ContextTracker feed(List<AgentEvent> events, {bool live = true}) {
  final t = ContextTracker();
  var i = 0;
  for (final e in events) {
    t.apply(
      e,
      at: t0.add(Duration(minutes: i)),
      itemIndex: i,
      live: live,
    );
    i++;
  }
  return t;
}

void main() {
  group('medição (R1)', () {
    test('a leitura substitui a anterior, nunca soma turnos ou cache', () {
      final t = feed([
        init('claude-opus-5-5'),
        assistant(2, 12918, 13392, id: 'a'),
        assistant(2, 12918, 13392, id: 'a'), // outra linha da mesma mensagem
        result(),
        assistant(2, 173, 26375, id: 'b'),
        result(),
      ]);
      final s = t.snapshot;
      expect(s.current!.tokens, 26550);
      expect(s.readings.map((r) => r.tokens), [26312, 26550]);
      expect(s.current!.cacheRead, 26375);
      expect(s.current!.hasComposition, isTrue);
      expect(s.current!.turn, 2);
      expect(s.current!.turnEnd, isTrue);
      expect(s.capacity, 1000000);
      expect(s.percent, 3);
    });

    test('subagente não entra na janela principal (R11)', () {
      final t = feed([
        assistant(2, 0, 50000, id: 'a'),
        assistant(2, 0, 900000, id: 'x', parent: 'toolu_1'),
      ]);
      expect(t.snapshot.current!.tokens, 50002);
      expect(t.snapshot.readings, hasLength(1));
    });

    test('sem result não há capacidade: total sem porcentagem (R2)', () {
      final t = feed([assistant(2, 0, 64000)]);
      expect(t.snapshot.current!.tokens, 64002);
      expect(t.snapshot.capacity, isNull);
      expect(t.snapshot.percent, isNull);
      expect(t.snapshot.free, isNull);
    });

    test('sem evento algum: aguardando medição, nunca 0%', () {
      final s = feed([init('claude-opus-5-5')]).snapshot;
      expect(s.hasReading, isFalse);
      expect(s.percent, isNull);
    });
  });

  group('limiar e compactação (R3, R7, R8)', () {
    test('limiar vem do agente, distinto da capacidade', () {
      final t = feed([
        UnknownEvent(ContextEventTypes.runEvent(autocompact: '200k')),
        assistant(2, 9000, 140000),
        result(),
        usageAnswer(),
      ]);
      final s = t.snapshot;
      expect(s.configuredAutocompact, '200k');
      expect(s.threshold, 167000);
      expect(s.autocompactWindow, 200000);
      expect(s.capacity, 1000000);
      expect(s.untilCompaction, 167000 - 149002);
      expect(s.phase, CompactionPhase.configured);
    });

    test('a resposta sanitizada não guarda caminhos de skill', () {
      final e = usageAnswer() as UnknownEvent;
      expect(e.json.toString(), isNot(contains('/home')));
      expect(e.json['categories'], hasLength(3));
    });

    test('compactar invalida a leitura até a próxima chamada', () {
      final t = feed([
        assistant(2, 0, 171000, id: 'a'),
        result(),
        status('compacting'),
      ]);
      expect(t.snapshot.phase, CompactionPhase.compacting);
      t.apply(status(null, result: 'success'), at: t0);
      t.apply(boundary(), at: t0, itemIndex: 7);
      var s = t.snapshot;
      expect(s.current, isNull);
      expect(s.pendingAfterCompaction, isTrue);
      expect(s.last!.tokens, 171002);
      expect(s.phase, CompactionPhase.done);
      expect(s.markers.single.preTokens, 171000);
      expect(s.markers.single.readingsBefore, 1);
      t.apply(assistant(2, 0, 46000, id: 'b'), at: t0);
      s = t.snapshot;
      expect(s.current!.tokens, 46002);
      expect(s.pendingAfterCompaction, isFalse);
    });

    test('eventos repetidos e reabertura marcam a compactação uma vez', () {
      final events = [
        assistant(2, 0, 171000, id: 'a'),
        result(),
        status('compacting'),
        status('compacting'),
        status(null, result: 'success'),
        boundary(),
        boundary(),
        assistant(2, 0, 46000, id: 'b'),
      ];
      final live = feed(events);
      final reopened = feed(events, live: false);
      for (final t in [live, reopened]) {
        expect(
          t.snapshot.markers.where(
            (m) => m.kind == ContextMarkerKind.compaction,
          ),
          hasLength(1),
        );
      }
      expect(reopened.snapshot.current!.live, isFalse);
      expect(reopened.snapshot.measuredLabel, startsWith('última medição às'));
    });

    test('falha mantém a leitura e informa o motivo', () {
      final t = feed([
        assistant(2, 0, 74000),
        result(),
        status('compacting'),
        status(null, result: 'failed', error: 'too_few_groups'),
      ]);
      final s = t.snapshot;
      expect(s.phase, CompactionPhase.failed);
      expect(s.compactError, 'too_few_groups');
      expect(s.current!.tokens, 74002);
    });

    test('sem evento de início não simula "compactando"', () {
      final t = feed([assistant(2, 0, 74000), result(), boundary()]);
      expect(t.snapshot.phase, CompactionPhase.done);
      expect(
        feed([assistant(2, 0, 1)]).snapshot.phase,
        CompactionPhase.notReported,
      );
    });

    test('/compact sozinho (num_turns 0) não conta como turno', () {
      final t = feed([
        assistant(2, 0, 30000, id: 'a'),
        result(),
        boundary(),
        result(turns: 0),
        assistant(2, 0, 27000, id: 'b'),
      ]);
      expect(t.snapshot.current!.turn, 2);
    });

    test('troca de modelo marca e invalida limites incompatíveis', () {
      final t = feed([
        init('claude-haiku-5-5'),
        assistant(2, 0, 26000, model: 'claude-haiku-5-5'),
        result(model: 'claude-haiku-5-5', window: 200000),
        usageAnswer(model: 'claude-haiku-5-5'),
        init('claude-sonnet-5-5'),
      ]);
      var s = t.snapshot;
      expect(s.markers.single.kind, ContextMarkerKind.modelChange);
      expect(s.markers.single.toModel, 'claude-sonnet-5-5');
      expect(s.threshold, isNull);
      t.apply(
        assistant(2, 13000, 13000, id: 'z', model: 'claude-sonnet-5-5'),
        at: t0,
      );
      s = t.snapshot;
      expect(s.capacity, isNull); // nada informado para o sonnet ainda
      expect(s.markers, hasLength(1));
    });
  });

  group('aviso (R10)', () {
    List<AgentEvent> base(int tokens, {String id = 'a'}) => [
      assistant(2, 0, tokens - 2, id: id),
    ];

    test('85% do limiar, uma vez por cruzamento, rearma abaixo de 75%', () {
      final t = feed([
        result(),
        usageAnswer(threshold: 200000),
        ...base(150000),
      ]);
      expect(t.snapshot.warning, isNull);
      t.apply(base(172000, id: 'b').single, at: t0);
      expect(t.snapshot.warning!.kind, ContextReference.threshold);
      expect(t.snapshot.warning!.percent, 86);
      t.dismissWarning();
      t.apply(base(180000, id: 'c').single, at: t0);
      expect(t.snapshot.warning, isNull, reason: 'mesmo cruzamento');
      t.apply(base(140000, id: 'd').single, at: t0);
      t.apply(base(175000, id: 'e').single, at: t0);
      expect(t.snapshot.warning, isNotNull, reason: 'rearmado abaixo de 75%');
    });

    test('sem limiar usa a capacidade e identifica a referência', () {
      final t = feed([result(window: 200000), ...base(171000, id: 'b')]);
      expect(t.snapshot.warning!.kind, ContextReference.capacity);
    });

    test('sem limite nenhum, sem alarme', () {
      expect(feed(base(990000)).snapshot.warning, isNull);
    });

    test('compactação confirmada rearma', () {
      final t = feed([
        result(),
        usageAnswer(threshold: 200000),
        ...base(172000),
      ]);
      expect(t.snapshot.warning, isNotNull);
      t.apply(boundary(), at: t0);
      expect(t.snapshot.warning, isNull);
      t.apply(base(190000, id: 'z').single, at: t0);
      expect(t.snapshot.warning, isNotNull);
    });

    test('leitura reconstruída do histórico não avisa', () {
      final t = feed([
        result(),
        usageAnswer(threshold: 200000),
        ...base(190000),
      ], live: false);
      expect(t.snapshot.warning, isNull);
    });
  });

  group('fontes (R4, R5)', () {
    test('evidência, estado e histórico após compactar', () {
      final t = feed([
        init('claude-opus-5-5'),
        user(
          'Leia @lib/a.dart e docs/specs/SPEC-087-x.md\n\n(imagem anexada: painel.png)',
        ),
        assistant(
          2,
          0,
          1000,
          content: [
            {
              'type': 'tool_use',
              'id': 't1',
              'name': 'Read',
              'input': {'file_path': 'lib/b.dart'},
            },
          ],
        ),
        result(),
        usageAnswer(),
      ]);
      final g = t.sources.grouped;
      expect(g[ContextSourceGroup.files]!.map((s) => s.label), [
        'lib/b.dart',
        'lib/a.dart',
      ]);
      final read = g[ContextSourceGroup.files]!.first;
      expect(read.stateLabel(1), 'leitura observada · t1');
      expect(read.weightLabel, 'peso indisponível');
      final spec = g[ContextSourceGroup.app]!.firstWhere((s) => s.ref != null);
      expect(spec.stateLabel(1), 'enviado neste turno');
      expect(spec.stateLabel(2), 'referência no histórico');
      final msg = g[ContextSourceGroup.app]!.firstWhere((s) => s.ref == null);
      expect(msg.weightLabel, startsWith('≈'));
      expect(msg.method, 'caracteres ÷ 4');
      expect(g[ContextSourceGroup.attachments]!.single.label, 'painel.png');
      final mcp = g[ContextSourceGroup.tools]!.firstWhere(
        (s) => s.label == 'github',
      );
      expect(mcp.detail, '2 ferramentas');
      expect(mcp.stateLabel(1), 'informado pelo agente');
      final mem = g[ContextSourceGroup.instructions]!.firstWhere(
        (s) => s.label.contains('CLAUDE'),
      );
      expect(mem.weightLabel, '≈ 900 · estimado');

      t.apply(boundary(), at: t0);
      final after = t.sources.grouped;
      expect(
        after[ContextSourceGroup.files]!.every((s) => s.historical),
        isTrue,
      );
      expect(
        after[ContextSourceGroup.files]!.first.stateLabel(2),
        'histórico · antes de compactar',
      );
      expect(
        after[ContextSourceGroup.tools]!.every((s) => !s.historical),
        isTrue,
      );
    });
  });

  group('fontes: mensagens e spec (R4)', () {
    test(
      'mensagens antigas viram uma linha; spec com @ entra no grupo do app',
      () {
        final t = feed([
          user('primeira'),
          assistant(2, 0, 1000, id: 'a'),
          result(),
          user('segunda'),
          assistant(2, 0, 2000, id: 'b'),
          result(),
          user('veja @docs/specs/SPEC-087-x.md'),
        ]);
        final app = t.sources.grouped[ContextSourceGroup.app]!;
        expect(app.map((s) => s.label), [
          'Mensagem do turno 3',
          '2 mensagens anteriores',
          'docs/specs/SPEC-087-x.md',
        ]);
        expect(t.sources.grouped[ContextSourceGroup.files], isNull);
        expect(app[1].weightLabel, 'peso indisponível');
      },
    );
  });

  group('timeline', () {
    test('a timeline alimenta o rastreador; o histórico não é ao vivo', () {
      final tl = Timeline()
        ..applyStored(
          '{"type":"assistant","message":{"id":"a","model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":95999}}}',
          at: t0,
        );
      expect(tl.context.snapshot.current!.tokens, 96000);
      expect(tl.context.snapshot.current!.live, isFalse);
      tl.apply(assistant(1, 0, 99999, id: 'b'));
      expect(tl.context.snapshot.current!.live, isTrue);
    });
  });

  group('formato', () {
    test('mil e milhão', () {
      expect(contextTokens(182000), '182 mil');
      expect(contextTokens(1000000), '1 milhão');
      expect(contextTokens(1200000), '1,2 milhão');
      expect(contextTokens(3400), '3,4 mil');
      expect(contextTokens(850), '850');
      expect(autocompactTokens('200k'), 200000);
      expect(autocompactTokens('auto'), isNull);
      expect(autocompactLabel('auto'), 'padrão do agente');
    });
  });
}
