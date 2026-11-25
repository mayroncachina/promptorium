import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/features/context/compaction_controller.dart';
import 'package:promptorium/features/context/context_snapshot.dart';
import 'package:promptorium/features/context/context_tracker.dart';

ContextSnapshot withReading({bool compacting = false}) {
  final t = ContextTracker()
    ..apply(
      AgentEvent.fromJson({
        'type': 'assistant',
        'message': {
          'id': 'a',
          'content': [],
          'usage': {
            'input_tokens': 2,
            'cache_creation_input_tokens': 0,
            'cache_read_input_tokens': 9000,
          },
        },
      }),
      at: DateTime(2026),
    );
  if (compacting) {
    t.apply(
      AgentEvent.fromJson({
        'type': 'system',
        'subtype': 'status',
        'status': 'compacting',
      }),
      at: DateTime(2026),
    );
  }
  return t.snapshot;
}

void main() {
  test('o comando nativo, com foco opcional numa linha', () {
    expect(compactCommand(), '/compact');
    expect(compactCommand('  '), '/compact');
    expect(compactCommand('manter\n os testes'), '/compact manter os testes');
  });

  group('disponibilidade (R9)', () {
    test('pela capacidade, com histórico, ocioso e sem compactação em '
        'curso', () {
      final s = withReading();
      expect(
        compactAvailability(provider: 'claude', busy: false, snapshot: s).ok,
        isTrue,
      );
      // SPEC-107 R8: the Codex has `compactNow`; an ACP agent does not.
      expect(
        compactAvailability(provider: 'codex', busy: false, snapshot: s).ok,
        isTrue,
      );
      expect(
        compactAvailability(
          provider: 'gemini',
          busy: false,
          snapshot: s,
        ).reason,
        contains('não confirmou um comando nativo'),
      );
      expect(
        compactAvailability(provider: 'claude', busy: true, snapshot: s).reason,
        contains('ocioso'),
      );
      expect(
        compactAvailability(
          provider: 'claude',
          busy: false,
          snapshot: ContextSnapshot.empty,
        ).reason,
        contains('Nada para compactar'),
      );
      expect(
        compactAvailability(
          provider: 'claude',
          busy: false,
          snapshot: withReading(compacting: true),
        ).reason,
        contains('já está compactando'),
      );
    });
  });

  group('controlador', () {
    test('envia uma vez; um segundo pedido em curso não sai', () async {
      final c = CompactionController();
      final sent = <String>[];
      final gate = Completer<void>();
      final first = c.request('conv:1', CompactAvailability.available, (cmd) {
        sent.add(cmd);
        return gate.future;
      }, focus: 'testes');
      expect(c.isRunning('conv:1'), isTrue);
      final second = await c.request(
        'conv:1',
        CompactAvailability.available,
        (cmd) async => sent.add(cmd),
      );
      expect(second, isFalse);
      gate.complete();
      expect(await first, isTrue);
      expect(sent, ['/compact testes']);
      expect(c.isRunning('conv:1'), isFalse);
    });

    test('sem suporte comprovado não envia nada', () async {
      final c = CompactionController();
      final sent = <String>[];
      final ok = await c.request(
        'conv:1',
        compactAvailability(
          provider: 'gemini',
          busy: false,
          snapshot: withReading(),
        ),
        (cmd) async => sent.add(cmd),
      );
      expect(ok, isFalse);
      expect(sent, isEmpty);
    });

    test('falha propaga e libera um novo pedido', () async {
      final c = CompactionController();
      await expectLater(
        c.request(
          'conv:1',
          CompactAvailability.available,
          (_) async => throw StateError('stdin fechada'),
        ),
        throwsStateError,
      );
      expect(c.isRunning('conv:1'), isFalse);
    });
  });
}
