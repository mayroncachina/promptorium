import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/prompt/spec_from_answer.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';

const spec = '''---
id: SPEC-016
status: aprovada
depende-de: [SPEC-001]
---

# Salvar a spec da resposta

## Objetivo

Salvar com um clique.

## Requisitos

- R1 · Mostrar a barra.
- R2 · Gravar só a spec.

## Critérios de aceite

- [ ] [R1] A barra aparece. verificar: `flutter test`
- [ ] [R2] O arquivo tem só a spec.
''';

String fenced(String body, {String lang = 'markdown'}) =>
    'Neste modo não tenho ferramenta de escrita. Salve em docs/specs:\n\n'
    '```$lang\n$body```\n\nSe quiser, detalho o R2.';

void main() {
  group('detectAnswerSpec', () {
    test('fenced block with frontmatter: only the spec, chat left out', () {
      final s = detectAnswerSpec(fenced(spec))!;
      expect(s.markdown, spec);
      expect(s.leftover, isTrue);
      expect(s.id, 'SPEC-016');
      expect(s.title, 'Salvar a spec da resposta');
      expect(s.requirements, 2);
      expect(s.criteria, hasLength(2));
    });

    test('fenced block with sections only, no frontmatter', () {
      final body = spec.substring(spec.indexOf('# Salvar'));
      final s = detectAnswerSpec(fenced(body, lang: 'md'))!;
      expect(s.id, isNull);
      expect(s.requirements, 2);
    });

    test('the answer itself is the spec (no block)', () {
      final s = detectAnswerSpec('Segue a spec:\n\n$spec')!;
      expect(s.markdown, spec);
      expect(s.leftover, isTrue);
      expect(detectAnswerSpec(spec)!.leftover, isFalse);
    });

    test('a block nesting a bash example ends at its own fence', () {
      final body = spec.replaceFirst(
        'Salvar com um clique.',
        'Salvar com um clique.\n\n```bash\nflutter test\n```',
      );
      final s = detectAnswerSpec(fenced(body))!;
      expect(s.markdown, contains('```bash\nflutter test\n```'));
      expect(s.markdown, endsWith('O arquivo tem só a spec.\n'));
    });

    test('ordinary answers and code blocks are not specs', () {
      expect(detectAnswerSpec('Use `flutter test` para rodar.'), isNull);
      expect(
        detectAnswerSpec('```dart\nvoid main() {}\n```\n\n## Requisitos'),
        isNull,
      );
      expect(
        detectAnswerSpec('## Objetivo\n\nx\n\n## Requisitos\n\n- R1 · y'),
        isNull,
        reason: 'sections without a title are a discussion, not a spec',
      );
    });

    test('several specs in one answer: the last wins', () {
      final other = spec
          .replaceFirst('SPEC-016', 'SPEC-017')
          .replaceFirst('# Salvar', '# Outra');
      final s = detectAnswerSpec('${fenced(spec)}\n\n${fenced(other)}')!;
      expect(s.id, 'SPEC-017');
    });

    test('lastAnswerSpec skips streaming and subagent answers', () {
      final items = <TimelineItem>[
        AssistantTextItem(fenced(spec)),
        UserItem('e agora?'),
        AssistantTextItem('ok, sem mudanças'),
        AssistantTextItem(fenced(spec), parentToolUseId: 't1'),
        AssistantTextItem(fenced(spec), live: true),
      ];
      final s = lastAnswerSpec(items)!;
      expect(s.id, 'SPEC-016');
      expect(lastAnswerSpec([UserItem('oi')]), isNull);
    });
  });

  test('withSpecTitle replaces or adds the title', () {
    expect(
      withSpecTitle(spec, 'Novo título'),
      contains('---\n\n# Novo título\n\n## Objetivo'),
    );
    expect(withSpecTitle('## Objetivo\n', 'T'), '# T\n\n## Objetivo\n');
  });

  test('lineDiff marks removed and added lines', () {
    final d = lineDiff('a\nb\nc', 'a\nx\nc');
    expect(d.map((l) => '${l.op.name}:${l.text}'), [
      'same:a',
      'del:b',
      'add:x',
      'same:c',
    ]);
  });

  group('saving', () {
    late Directory tmp;
    late AppDatabase db;
    late Workspace ws;
    late SpecsRepo repo;
    late SpecService service;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-answer-spec-');
      db = memoryDatabase();
      ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'ws'),
          );
      repo = SpecsRepo(db);
      service = SpecService(repo);
    });

    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    test('new spec: next code, draft, other keys kept, registered', () async {
      Directory('${tmp.path}/specs').createSync();
      File('${tmp.path}/specs/SPEC-004-x.md').writeAsStringSync('# X\n');
      final s = detectAnswerSpec(fenced(spec))!;
      final saved = await saveAnswerSpecAsNew(service, ws, s.markdown);
      expect(saved.code, 'SPEC-005');
      expect(saved.path, 'specs/SPEC-005-salvar-a-spec-da-resposta.md');
      expect(saved.status, SpecStatus.draft);
      expect(saved.requirements.map((r) => r.id), ['R1', 'R2']);
      final text = File('${tmp.path}/${saved.path}').readAsStringSync();
      expect(text, startsWith('---\nid: SPEC-005\nstatus: rascunho\n'));
      expect(text, contains('depende-de: [SPEC-001]'));
      expect(text, isNot(contains('ferramenta de escrita')));
      expect(text, isNot(contains('detalho o R2')));
      expect(await repo.getByCode(ws.id, 'SPEC-005'), isNotNull);
    });

    test(
      'apply keeps id and status; a spec out of the Backlog is refused',
      () async {
        final target = await service.create(
          ws,
          title: 'Antiga',
          render: (code) =>
              '---\nid: $code\nstatus: em-revisao\n---\n\n# Antiga\n',
        );
        final current = await service.read(ws, target);
        final s = detectAnswerSpec(
          fenced(spec.replaceFirst('SPEC-016', target.code)),
        )!;
        final applied = await applyAnswerSpec(
          service,
          ws,
          target,
          s.markdown,
          expectedText: current,
        );
        final text = (await service.read(ws, applied))!;
        expect(text, contains('id: ${target.code}'));
        expect(text, contains('status: em-revisao'));
        expect(text, contains('# Salvar a spec da resposta'));
        expect(applied.title, 'Salvar a spec da resposta');

        await repo.setStage(target.id, SpecStage.running);
        final running = (await repo.getById(target.id))!;
        expect(applyBlockedReason(running), contains('em execução'));
        await expectLater(
          applyAnswerSpec(service, ws, running, s.markdown, expectedText: text),
          throwsA(isA<SpecException>()),
        );
      },
    );

    test('a file changed after the preview is not overwritten', () async {
      final target = await service.create(ws, title: 'Antiga');
      final shown = await service.read(ws, target);
      File('${tmp.path}/${target.path}').writeAsStringSync('mudou fora\n');
      await expectLater(
        applyAnswerSpec(service, ws, target, spec, expectedText: shown),
        throwsA(isA<SpecException>()),
      );
      expect(
        File('${tmp.path}/${target.path}').readAsStringSync(),
        'mudou fora\n',
      );
    });
  });
}
