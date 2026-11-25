import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/features/context/context_snapshot.dart';
import 'package:promptorium/features/sessions/replay/file_at_step.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../core/codex/codex_replay.dart';

/// SPEC-095 R3, R4: the context meter of a Codex session, from the real
/// `contexto` transcript (two turns and a compaction, SPEC-093 R14).
void main() {
  test('tokenUsage.last with the model window; compaction waits', () async {
    final events = await replayCodex(
      'contexto',
      turns: 2,
      afterTurns: (run) =>
          run.rpc.request('thread/compact/start', {'threadId': 'x'}),
    );
    final t = Timeline();
    var afterTurn1 = ContextSnapshot.empty;
    var afterTurn2 = ContextSnapshot.empty;
    var results = 0;
    for (final e in events) {
      t.apply(e);
      if (e is Result) {
        results++;
        if (results == 1) afterTurn1 = t.context.snapshot;
        if (results == 2) afterTurn2 = t.context.snapshot;
      }
    }
    // Turn 1: last.totalTokens = 12 403 of a 258 400 window.
    expect(afterTurn1.current!.tokens, 12403);
    expect(afterTurn1.current!.source, ContextReadingSource.codexTokenUsage);
    expect(afterTurn1.capacity, 258400);
    expect(afterTurn1.percent, 5);
    expect(afterTurn1.current!.cacheRead, 10112);
    expect(afterTurn1.current!.input, 12393 - 10112);
    // Turn 2 replaces it (never a sum; `total` would be 26 455).
    expect(afterTurn2.current!.tokens, 14052);
    expect(afterTurn2.readings.map((r) => r.tokens), [12403, 14052]);
    // The compaction: marker with the new size, "aguardando medição".
    final s = t.context.snapshot;
    expect(s.current, isNull);
    expect(s.pendingAfterCompaction, isTrue);
    expect(s.phase, CompactionPhase.done);
    expect(s.lastCompaction!.postTokens, 15663);
    expect(s.lastCompaction!.trigger, 'auto');
    expect(s.last!.tokens, 14052);
    // The timeline shows the compaction notice.
    expect(
      t.items.whereType<NoticeItem>().map((n) => n.text),
      contains(Timeline.compactionNotice),
    );
    // A new reading ends the wait.
    t.apply(
      AgentEvent.fromJson(
        ContextUsageEvent.toJson(
          provider: 'codex',
          tokens: 16000,
          window: 258400,
          source: ContextUsageEvent.codexTokenUsage,
        ),
      ),
    );
    expect(t.context.snapshot.current!.tokens, 16000);
    expect(t.context.snapshot.pendingAfterCompaction, isFalse);
  });

  test('the stored rows rebuild the same readings', () async {
    final events = await replayCodex('contexto', turns: 2);
    final live = Timeline();
    final stored = Timeline();
    for (final e in events) {
      live.apply(e);
      if (isStoredEvent(e)) stored.applyStored(eventJson(e));
    }
    expect(stored.context.snapshot.readings.map((r) => (r.tokens, r.live)), [
      (12403, false),
      (14052, false),
    ]);
    expect(stored.context.snapshot.capacity, 258400);
    expect(live.context.snapshot.current!.live, isTrue);
  });

  group('P4 · the "antes" of a Codex edit from the diff', () {
    ToolItem change(String id, String kind, String diff) =>
        (Timeline()..apply(
              AgentEvent.fromJson(
                FileChangeEvent.toJson(
                  provider: 'codex',
                  toolUseId: id,
                  path: '/w/base.txt',
                  kind: FileChangeKind.parse(kind),
                  status: FileChangeStatus.applied,
                  diff: diff,
                ),
              ),
            ))
            .items
            .whereType<ToolItem>()
            .single;

    // The real update of edicao-turno.
    final update = change('e1', 'update', '@@ -1 +1 @@\n-base\n+linha dois\n');
    final steps = replaySteps([update], root: '/w');

    test('the step is an edit of the file, +1 −1', () {
      final s = steps.single;
      expect(s.kind, ReplayKind.edit);
      expect(s.filePath, '/w/base.txt');
      expect((s.added, s.removed), (1, 1));
    });

    test('rebuilt from the current file with the diff undone', () async {
      final r = FileBaseResolver(
        originalFiles: () async => const {},
        showAt: (_, _) async => fail('sem git'),
        readFile: (p) async => p == '/w/base.txt' ? 'linha dois\n' : null,
        root: '/w',
      );
      final edits = editsOf(steps, '/w/base.txt', root: '/w');
      final base = await r.resolve('/w/base.txt', edits, edits.single);
      expect(base!.source, FileBaseSource.reverseDiff);
      expect(base.label, 'reconstruído pelo diff');
      expect(base.text, 'base\n');
      final at = fileAtStep(base: base, edits: edits, target: edits.single);
      expect(at.text, 'linha dois\n');
      expect(at.highlighted, {1});
    });

    test(
      'a diff that does not undo: "conteúdo anterior indisponível"',
      () async {
        final r = FileBaseResolver(
          originalFiles: () async => const {},
          showAt: (_, _) async => null,
          readFile: (_) async => 'outra coisa\n',
          root: '/w',
        );
        final edits = editsOf(steps, '/w/base.txt', root: '/w');
        final base = await r.resolve('/w/base.txt', edits, edits.single);
        expect(base, isNull);
        final at = fileAtStep(base: base, edits: edits, target: edits.single);
        expect(at.ok, isFalse);
        expect(at.reason, startsWith('Conteúdo anterior indisponível'));
      },
    );
  });
}
