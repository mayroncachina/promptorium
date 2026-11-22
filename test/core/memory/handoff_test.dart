import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/handoff.dart';

import 'fake_ai_memory.dart';

/// SPEC-098: the handoff model from the JSON of ai-memory 3.5.1 (R9–R11).
void main() {
  const ws = '/repo/promptorium-wt/spec-parser';

  test('parses the wire row: agent, time, origin, owner, directory and '
      'content', () {
    final list = HandoffList.parse(
      jsonDecode(handoffListJson()),
      workspacePath: ws,
    );
    expect(list.handoffs, hasLength(2));
    final h = list.handoffs.first;
    expect(h.agentName, 'Claude Code');
    expect(h.origin, 'automática · fim da sessão');
    expect(h.createdAt, DateTime.utc(2026, 11, 20, 14, 41).toLocal());
    expect(h.summary, startsWith('Parser trocado'));
    expect(h.openQuestions, ['Front-matter vazio deve virar erro?']);
    expect(h.nextSteps, ['Escrever test/spec_parser_bom_test.dart']);
    expect(h.filesTouched, ['lib/core/spec_parser.dart']);
    expect(h.shortId, '01JDX4…');
    expect(list.ownerLabel(h), 'você');
    expect(list.directoryLabel(h), isNull);
    expect(list.directoryLabel(list.handoffs[1]), 'worktree: review-021');
    expect(list.handoffs[1].agentName, 'Codex');
    expect(list.unended, isNull);
  });

  test('delivery order: manual first, then the newest automatic one of the '
      'directory gets the "será entregue" badge', () {
    final rows = <String, Object?>{
      'handoffs': <Object?>[
        {
          'id': 'auto-old',
          'from_session_id': 's1',
          'from_agent': 'codex',
          'cwd': ws,
          'state': 'open',
          'created_at': '2026-11-20T09:00:00Z',
        },
        {
          'id': 'auto-new-elsewhere',
          'from_session_id': 's2',
          'from_agent': 'codex',
          'cwd': '/outro',
          'state': 'open',
          'created_at': '2026-11-20T12:00:00Z',
        },
        {
          'id': 'auto-new',
          'from_session_id': 's3',
          'from_agent': 'claude-code',
          'cwd': ws,
          'state': 'open',
          'created_at': '2026-11-20T11:00:00Z',
        },
      ],
    };
    var list = HandoffList.parse(rows, workspacePath: ws);
    expect(list.handoffs.map((h) => h.id), [
      'auto-new-elsewhere',
      'auto-new',
      'auto-old',
    ]);
    expect(list.nextDelivered?.id, 'auto-new');

    (rows['handoffs']! as List<Object?>).add(<String, Object?>{
      'id': 'manual',
      'from_session_id': null,
      'from_agent': 'claude-code',
      'state': 'open',
      'created_at': '2026-11-19T08:00:00Z',
    });
    list = HandoffList.parse(rows, workspacePath: ws);
    expect(list.handoffs.first.id, 'manual');
    expect(list.handoffs.first.origin, 'manual');
    expect(list.nextDelivered?.id, 'manual');
  });

  test(
    'owner: unattributed server = você; attributed = você or '
    'compartilhada; discarding only on open handoffs of their owner (P6)',
    () {
      final single = HandoffList.parse(jsonDecode(handoffListJson()));
      expect(single.canDiscard(single.handoffs.first), isTrue);

      final team = HandoffList.parse({
        'handoffs': [
          {
            'id': 'mine',
            'from_session_id': 's',
            'from_agent': 'codex',
            'owner_user': 'alice',
            'state': 'open',
          },
          {
            'id': 'shared',
            'from_agent': 'codex',
            'owner_user': null,
            'state': 'open',
          },
          {
            'id': 'done',
            'from_agent': 'codex',
            'owner_user': 'alice',
            'state': 'accepted',
            'accepted_by': 'claude-code',
            'accepted_at': '2026-11-20T10:00:00Z',
          },
        ],
      });
      final byId = {for (final h in team.handoffs) h.id: h};
      expect(team.ownerLabel(byId['mine']!), 'você');
      expect(team.ownerLabel(byId['shared']!), 'compartilhada');
      expect(team.canDiscard(byId['mine']!), isTrue);
      expect(team.canDiscard(byId['shared']!), isFalse);
      expect(team.canDiscard(byId['done']!), isFalse);
      expect(team.closed.single.acceptedBy, 'claude-code');
      expect(
        team.ownerOf(byId['mine']!, operator: 'bob'),
        HandoffOwnerKind.other,
      );
    },
  );

  test('newer_unended_session (R10)', () {
    final list = HandoffList.parse(jsonDecode(handoffListJson(unended: true)));
    final u = list.unended!;
    expect(u.agentName, 'Codex');
    expect(u.shortId, '019a3f2c');
    expect(u.lastActivityAt, DateTime.utc(2026, 11, 20, 15, 20).toLocal());
  });

  test('briefing: scope, counts and five recent pages (R8, R12)', () {
    final b = MemoryBriefing.parse(jsonDecode(briefingJson()));
    expect(b.scope, 'default/promptorium');
    expect(b.pages, 138);
    expect(b.sessions, 27);
    expect(b.observations, 4198);
    expect(b.recentPages.first.path, 'sessions/2026-11-20-claude-code.md');
    expect(b.lastObservationAt, isNotNull);
  });

  test('rows without an id are skipped, odd shapes do not throw', () {
    expect(HandoffList.parse(null).handoffs, isEmpty);
    expect(HandoffList.parse({'handoffs': 'x'}).handoffs, isEmpty);
    expect(
      HandoffList.parse({
        'handoffs': [
          {'summary': 'sem id'},
          42,
        ],
      }).handoffs,
      isEmpty,
    );
    expect(MemoryBriefing.parse('x').pages, 0);
  });
}
