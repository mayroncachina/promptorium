import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/cost/quota_ruler.dart';
import 'package:promptorium/features/cost/usage_ledger.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

Result result({
  double cost = 0.10,
  int input = 100,
  int cacheWrite = 0,
  int cacheRead = 0,
  int output = 20,
  Map<String, Object?>? modelUsage,
}) => ClaudeEvent.fromJson({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': cost,
  'usage': {
    'input_tokens': input,
    'cache_creation_input_tokens': cacheWrite,
    'cache_read_input_tokens': cacheRead,
    'output_tokens': output,
  },
  'modelUsage': ?modelUsage,
  'result': '{}',
}) as Result;

// SPEC-081 R1, R2, R4.
void main() {
  group('turnCost', () {
    test('is the difference of the cumulative cost in the process', () {
      expect(turnCost(0.30, lastSeen: 0.10), closeTo(0.20, 1e-9));
      expect(turnCost(0.10), 0.10);
      expect(turnCost(0), 0);
    });

    test('a resumed process: restored cost or starting from zero', () {
      // The CLI brought back the 1.00 the session had.
      expect(turnCost(1.20, stored: 1.00), closeTo(0.20, 1e-9));
      // It started from zero again.
      expect(turnCost(0.15, stored: 1.00), 0.15);
      // A smaller total in the same process: a new count.
      expect(turnCost(0.05, lastSeen: 0.40), 0.05);
    });
  });

  test('resultModel takes the model that cost the most', () {
    expect(
      resultModel(
        result(
          modelUsage: {
            'claude-haiku': {'costUSD': 0.01},
            'claude-sonnet': {'costUSD': 0.09},
          },
        ),
      ),
      'claude-sonnet',
    );
    expect(resultModel(result(), 'opus'), 'opus');
  });

  test('specCodeInText reads the frontmatter or a leading "Spec CODE"', () {
    expect(specCodeInText('---\nid: SPEC-081\nstatus: x\n---\n'), 'SPEC-081');
    expect(specCodeInText('Spec VIBE-007:\n<spec>…'), 'VIBE-007');
    expect(
      specCodeInText('Rascunho que depende da SPEC-076'),
      isNull,
      reason: 'a code in the middle may be a dependency',
    );
  });

  group('UsageLedger', () {
    late AppDatabase db;
    late ProviderContainer c;
    late int ws;
    late int spec;
    late int vibe;

    setUp(() async {
      db = memoryDatabase();
      c = ProviderContainer(overrides: [databaseOverride(db)]);
      await c.read(appSettingsProvider.notifier).load();
      ws = await db
          .into(db.workspaces)
          .insert(WorkspacesCompanion.insert(path: '/r', name: 'r'));
      spec = await db
          .into(db.specs)
          .insert(
            SpecsCompanion.insert(
              workspaceId: ws,
              code: 'SPEC-073',
              title: 'Corrigir CI',
              path: 'docs/specs/SPEC-073.md',
            ),
          );
      vibe = await db
          .into(db.specs)
          .insert(
            SpecsCompanion.insert(
              workspaceId: ws,
              code: 'VIBE-001',
              title: 'Botão',
              path: 'docs/vibe/VIBE-001.md',
            ),
          );
    });
    tearDown(() => c.dispose());

    Future<void> session(String id, {int? specId, String? steps}) => db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            workspaceId: ws,
            worktreePath: '/r',
            branch: 'b',
            model: 'sonnet',
            specId: Value(specId),
            steps: Value(steps),
          ),
        );

    Future<int> conversation({int? specId, String? refine}) => db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            workspaceId: ws,
            title: 'c',
            model: 'opus',
            specId: Value(specId),
            refineSpecCode: Value(refine),
          ),
        );

    Future<List<UsageEntry>> entries() => (db.select(
      db.usageEntries,
    )..orderBy([(e) => OrderingTerm.asc(e.id)])).get();

    test('a turn of a step, a REVn step and one the CI fixer marked', () async {
      final ledger = c.read(usageLedgerProvider);
      await session('s1', specId: spec, steps: 'R2');
      await session('s2', specId: spec, steps: 'REV1');
      await session('s3');
      await ledger.recordSessionTurn('s1', result(), costUsd: 0.10);
      await ledger.recordSessionTurn('s2', result(), costUsd: 0.05);
      ledger.markNextTurn(sessionId: 's1', source: UsageSource.ci);
      await ledger.recordSessionTurn('s1', result(), costUsd: 0.07);
      // The mark is of one turn only.
      await ledger.recordSessionTurn('s1', result(), costUsd: 0.01);
      await ledger.recordSessionTurn('s3', result(), costUsd: 0.02);
      final list = await entries();
      expect(
        [for (final e in list) (e.specId, e.source, e.step)],
        [
          (spec, UsageSource.etapa, 'R2'),
          (spec, UsageSource.etapa, 'REV1'),
          (spec, UsageSource.ci, 'R2'),
          (spec, UsageSource.etapa, 'R2'),
          (null, UsageSource.livre, null),
        ],
      );
      expect(list.first.model, 'sonnet');
      expect(list.first.tokensIn, 100);
      expect(list.first.tokensOut, 20);
      expect(list.first.workspaceId, ws);
    });

    test('a turn without tokens records nothing', () async {
      await session('s1', specId: spec, steps: 'R1');
      await c
          .read(usageLedgerProvider)
          .recordSessionTurn(
            's1',
            result(cost: 0, input: 0, output: 0),
            costUsd: 0,
          );
      expect(await entries(), isEmpty);
    });

    test('VIBE, refinement by the code and the free Prompt', () async {
      final ledger = c.read(usageLedgerProvider);
      final v = await conversation(specId: vibe);
      final r = await conversation(refine: 'SPEC-073');
      final free = await conversation();
      await ledger.recordConversationTurn(v, result(), costUsd: 0.1);
      await ledger.recordConversationTurn(r, result(), costUsd: 0.1);
      await ledger.recordConversationTurn(free, result(), costUsd: 0.1);
      // CI fix of a VIBE: the mark goes from its session to its conversation.
      ledger
        ..markNextTurn(sessionId: 'vibe-1', source: UsageSource.ci)
        ..moveMark('vibe-1', v);
      await ledger.recordConversationTurn(v, result(), costUsd: 0.1);
      expect(
        [for (final e in await entries()) (e.specId, e.source, e.model)],
        [
          (vibe, UsageSource.vibe, 'opus'),
          (spec, UsageSource.refino, 'opus'),
          (null, UsageSource.livre, 'opus'),
          (vibe, UsageSource.ci, 'opus'),
        ],
      );
    });

    test('the reviewer, the Orchestrator and the verification by the code of '
        'the spec; no spec found is a free turn', () async {
      final ledger = c.read(usageLedgerProvider);
      Future<void> rec(UsageSource s, {int? id, String? code}) => ledger.record(
        workspaceId: ws,
        specId: id,
        specCode: code,
        source: s,
        usage: result().usage,
        costUsd: 0.2,
      );
      await rec(UsageSource.revisor, id: spec);
      await rec(UsageSource.orquestrador, id: spec);
      await rec(UsageSource.verificacao, code: 'SPEC-073');
      await rec(UsageSource.outros, code: 'SPEC-999');
      expect(
        [for (final e in await entries()) (e.specId, e.source)],
        [
          (spec, UsageSource.revisor),
          (spec, UsageSource.orquestrador),
          (spec, UsageSource.verificacao),
          (null, UsageSource.livre),
        ],
      );
    });

    test('the weight comes from the ruler of the moment and never changes; '
        'one recorded without a ruler receives it later (R4)', () async {
      final ledger = c.read(usageLedgerProvider);
      await session('s1', specId: spec, steps: 'R1');
      await ledger.recordSessionTurn('s1', result(), costUsd: 1.0);
      var list = await entries();
      expect(list.single.weekPct, isNull);
      expect(list.single.fiveHourPct, isNull);

      final ruler = c.read(quotaRulerProvider.notifier);
      final resets = DateTime.utc(2026, 11, 17, 14);
      ruler.onReading(fiveHour: (used: 0.1, resetsAt: resets));
      for (var i = 1; i <= 3; i++) {
        ruler.addCost(1);
        ruler.onReading(fiveHour: (used: 0.1 + i * 0.04, resetsAt: resets));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      list = await entries();
      expect(list.single.fiveHourPct, closeTo(0.04, 1e-9));
      expect(list.single.weekPct, isNull, reason: 'no weekly ruler yet');

      // A turn now is weighed at once; later readings do not change it.
      await ledger.recordSessionTurn('s1', result(), costUsd: 0.5);
      for (var i = 4; i <= 8; i++) {
        ruler.addCost(1);
        ruler.onReading(fiveHour: (used: 0.1 + i * 0.1, resetsAt: resets));
      }
      list = await entries();
      expect(list.last.fiveHourPct, closeTo(0.02, 1e-9));
      expect(list.first.fiveHourPct, closeTo(0.04, 1e-9));
    });
  });

  test('runReadOnlyClaude records its turn with the spec and the origin '
      'given (the reviewer)', () async {
    final cli = FakeCli();
    final db = memoryDatabase();
    final c = ProviderContainer(
      overrides: sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: '/r', name: 'r');
    final spec = await db
        .into(db.specs)
        .insert(
          SpecsCompanion.insert(
            workspaceId: ws.id,
            code: 'SPEC-073',
            title: 'x',
            path: 'x.md',
          ),
        );
    final run = Provider(
      (ref) =>
          () => runReadOnlyClaude(
            ref,
            cwd: '/r',
            workspaceId: ws.id,
            options: const ClaudeOptions(model: 'opus'),
            prompt: 'Revise',
            specId: spec,
            usageSource: UsageSource.revisor,
            usageStep: 'rodada 2',
          ),
    );
    final done = c.read(run)();
    await settle();
    cli.last.emit(jsonEncode(result(cost: 0.3).json));
    await done;
    final e = await db.select(db.usageEntries).getSingle();
    expect(e.specId, spec);
    expect(e.source, UsageSource.revisor);
    expect(e.step, 'rodada 2');
    expect(e.costUsd, 0.3);
    expect(e.model, 'opus');
  });
}
