import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../helpers/test_db.dart';

/// Autopilot, Review draft and notices survive a "reopen": a new container
/// on the same database file.
void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tmp = Directory.systemTemp.createTempSync('promptorium-durable-');
    file = File('${tmp.path}/db.sqlite');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer open() {
    final c = ProviderContainer(
      overrides: [databaseOverride(AppDatabase(NativeDatabase(file)))],
    );
    c.listen(sessionManagerProvider, (_, _) {});
    return c;
  }

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

  test('autopilot on before closing is on again after restore; off stays '
      'off', () async {
    var c = open();
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: tmp.path, name: 'w');
    // A running spec keeps it on (nothing to start, but not finished).
    final spec = await c
        .read(specsRepoProvider)
        .insert(workspaceId: ws.id, code: 'SPEC-001', title: 'A', path: 'a');
    await c.read(specsRepoProvider).setStage(spec.id, SpecStage.running);
    await c.read(autopilotProvider.notifier).start(ws.id);
    expect(c.read(autopilotProvider), {ws.id});
    await pump();
    c.dispose();

    c = open();
    expect(c.read(autopilotProvider), isEmpty);
    await c.read(autopilotProvider.notifier).restore();
    expect(c.read(autopilotProvider), {ws.id});
    await c.read(autopilotProvider.notifier).stop(ws.id);
    await pump();
    c.dispose();

    c = open();
    await c.read(autopilotProvider.notifier).restore();
    expect(c.read(autopilotProvider), isEmpty);
    c.dispose();
  });

  test('review draft: comments and accepted hunks come back', () async {
    var c = open();
    final draft = c.read(reviewDraftProvider('s1').notifier);
    draft
      ..addComment(
        const ReviewComment(
          path: 'lib/a.dart',
          line: 3,
          text: 'renomeie',
          snippet: ['+ var x = 1;'],
          anchor: 'h1#2',
        ),
      )
      ..toggleAccepted('h2');
    await draft.saved;
    c.dispose();

    c = open();
    c.listen(reviewDraftProvider('s1'), (_, _) {});
    c.read(reviewDraftProvider('s1'));
    await pump();
    final back = c.read(reviewDraftProvider('s1'));
    expect(back.comments.single.text, 'renomeie');
    expect(back.comments.single.anchor, 'h1#2');
    expect(back.comments.single.snippet, ['+ var x = 1;']);
    expect(back.accepted, {'h2'});

    // Emptied = removed.
    final n = c.read(reviewDraftProvider('s1').notifier)
      ..clearComments()
      ..toggleAccepted('h2');
    await n.saved;
    expect(await c.read(durableStateRepoProvider).reviewDraft('s1'), isNull);
    c.dispose();
  });

  test('notices not delivered come back for the next message', () async {
    var c = open();
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: tmp.path, name: 'w');
    await c
        .read(sessionsRepoProvider)
        .insert(
          id: 's1',
          workspaceId: ws.id,
          worktreePath: tmp.path,
          branch: 'main',
          model: 'sonnet',
        );
    // No live process: queued (and stored).
    expect(
      await c.read(sessionManagerProvider.notifier).notifyUserEdit('s1', 'x'),
      isFalse,
    );
    c.dispose();

    c = open();
    final m = c.read(sessionManagerProvider.notifier);
    expect(m.pendingNotices('s1'), isEmpty);
    await m.restoreNotices();
    expect(m.pendingNotices('s1'), [SessionManager.userEditNotice('x')]);
    c.dispose();
  });
}
