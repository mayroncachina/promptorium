import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../helpers/test_db.dart';
import 'prompt_test_utils.dart';

void main() {
  test('triggerAt detects @file and /prompt at the cursor', () {
    expect(triggerAt('veja @lib/a', 11), (char: '@', start: 5, query: 'lib/a'));
    expect(triggerAt('@', 1), (char: '@', start: 0, query: ''));
    expect(triggerAt('/tes', 4), (char: '/', start: 0, query: 'tes'));
    expect(triggerAt('oi\n/com', 7), (char: '/', start: 3, query: 'com'));
    // Paths and words in the middle of a line are not triggers.
    expect(triggerAt('abra lib/a', 10), isNull);
    expect(triggerAt('texto /x', 8), isNull);
    expect(triggerAt('email@x', 7), isNull);
    expect(triggerAt('@a ', 3), isNull);
  });

  test('mentionedFiles / filterFiles', () {
    expect(
      mentionedFiles(['olhe @lib/a.dart e @b.md.', 'de novo @lib/a.dart']),
      ['lib/a.dart', 'b.md'],
    );
    final files = [
      'lib/core/claude_process.dart',
      'lib/a.dart',
      'docs/process.md',
    ];
    expect(filterFiles(files, 'process'), [
      'lib/core/claude_process.dart',
      'docs/process.md',
    ]);
    expect(filterFiles(files, 'core'), ['lib/core/claude_process.dart']);
    expect(filterFiles(files, ''), files);
  });

  test('transcript / lastAnswer skip tools and subagents', () {
    final items = <TimelineItem>[
      UserItem('pergunta'),
      AssistantTextItem('sub', parentToolUseId: 't'),
      ToolItem(id: 't', name: 'Read', input: const {}),
      AssistantTextItem('resposta final'),
    ];
    expect(lastAnswer(items), 'resposta final');
    expect(lastUserMessage(items), 'pergunta');
    expect(transcriptOf(items), [
      (user: true, text: 'pergunta'),
      (user: false, text: 'resposta final'),
    ]);
  });

  group('database / files', () {
    late AppDatabase db;
    late ProviderContainer c;
    late Directory tmp;
    late Workspace ws;

    setUp(() async {
      db = memoryDatabase();
      c = ProviderContainer(overrides: [databaseOverride(db)]);
      tmp = await Directory.systemTemp.createTemp('prompt-actions-');
      ws = await addWorkspace(db, tmp.path);
      await c.read(appSettingsProvider.notifier).load();
    });

    tearDown(() async {
      c.dispose();
      await tmp.delete(recursive: true);
    });

    test(
      'createTaskFromAnswer: backlog task, summarized title, body',
      () async {
        const answer =
            '## Use `Process.start` e um LineSplitter para ler o stdout sem '
            'travar a interface do app\n\nDepois mapeie para uma sealed class.';
        final t = await createTaskFromAnswer(
          c.read(tasksRepoProvider),
          workspaceId: ws.id,
          answer: answer,
        );
        expect(t.code, 'T-001');
        expect(t.status, TaskStatus.backlog);
        expect(t.body, answer);
        expect(t.title, startsWith('Use Process.start e um LineSplitter'));
        expect(t.title.length, lessThanOrEqualTo(71));
        final again = await createTaskFromAnswer(
          c.read(tasksRepoProvider),
          workspaceId: ws.id,
          answer: 'Outra',
        );
        expect(again.code, 'T-002');
        expect(again.title, 'Outra');
      },
    );

    test('createSpecFromConversation writes specs/SPEC-NNN-slug.md and '
        'registers it', () async {
      // An existing file numbers the next spec.
      await Directory('${tmp.path}/specs').create();
      await File('${tmp.path}/specs/SPEC-002-antiga.md').writeAsString('x');
      final spec = await createSpecFromConversation(
        c.read(specsRepoProvider),
        workspace: ws,
        title: 'Parser stream-json em Dart',
        transcript: const [
          (user: true, text: 'Como ler o stream-json?'),
          (user: false, text: 'Use Process.start.'),
        ],
        now: DateTime(2026, 10, 15),
      );
      expect(spec.code, 'SPEC-003');
      expect(spec.path, 'specs/SPEC-003-parser-stream-json-em-dart.md');
      expect(spec.status, SpecStatus.draft);
      final text = await File('${tmp.path}/${spec.path}').readAsString();
      expect(
        text,
        startsWith(
          '---\nid: SPEC-003\nstatus: rascunho\n---\n\n'
          '# Parser stream-json em Dart\n',
        ),
      );
      expect(text, contains('**Pergunta:**\n\nComo ler o stream-json?'));
      expect(text, contains('**Resposta:**\n\nUse Process.start.'));
      final rows = await c
          .read(specsRepoProvider)
          .watchByWorkspace(ws.id)
          .first;
      expect(rows.single.code, 'SPEC-003');
    });

    test('seedSavedPrompts inserts the 5 defaults once', () async {
      final repo = c.read(savedPromptsRepoProvider);
      final settings = c.read(appSettingsProvider.notifier);
      await seedSavedPrompts(repo, settings);
      final all = await repo.watchAll().first;
      expect(all.map((p) => p.command).toSet(), {
        'explicar',
        'testes',
        'revisar-seguranca',
        'spec',
        'commit',
      });
      expect(all.every((p) => p.body.length > 80), isTrue);
      // A deleted default does not come back.
      await repo.delete('commit');
      await seedSavedPrompts(repo, settings);
      expect(await repo.getByCommand('commit'), isNull);
    });

    test('validateCommand', () {
      expect(validateCommand('/revisar-testes'), isNull);
      expect(validateCommand(''), isNotNull);
      expect(validateCommand('Com Espaço'), isNotNull);
    });
  });
}
