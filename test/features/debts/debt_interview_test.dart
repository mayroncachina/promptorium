import 'dart:io';

import 'package:drift/drift.dart' show Value;

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/data/repos/workspaces_repo.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_interview.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_service.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/specs/spec_draft.dart';
import 'package:promptorium/features/specs/spec_file.dart';

import '../../helpers/test_db.dart';

/// SPEC-112 R6, R7, R12, P2: the items born in the interview.
void main() {
  late Directory dir;
  late String root;
  late AppDatabase db;
  late DebtLinksRepo links;
  late DebtInterview interview;
  late Workspace ws;
  late Spec spec;

  const specPath = 'docs/specs/SPEC-033-limite.md';
  const specText = '''---
id: SPEC-033
status: rascunho
---

# Limite de arquivos

## Perguntas em aberto

- P5 · Guardar os arquivos recusados para auditoria?
  - Sugestão: guardar no S3 por 30 dias
- P6 · O que registrar no log quando um envio é recusado?
- P7 · Arquivo acima do limite: recusar no envio ou comprimir?
  - Sugestão: recusar no envio
''';

  String read(String rel, {String? at}) =>
      File('${at ?? root}/$rel').readAsStringSync();

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('debt_interview_');
    root = dir.path;
    File('$root/$specPath')
      ..createSync(recursive: true)
      ..writeAsStringSync(specText);
    db = memoryDatabase();
    links = DebtLinksRepo(db);
    final workspaces = WorkspacesRepo(db);
    final specs = SpecsRepo(db);
    ws = await workspaces.add(path: root, name: 'inscricoes');
    spec = await specs.insert(
      workspaceId: ws.id,
      code: 'SPEC-033',
      title: 'Limite de arquivos',
      path: specPath,
    );
    interview = DebtInterview(
      debts: DebtService(links: links, now: () => DateTime(2026, 11, 24)),
      links: links,
      specs: specs,
      workspaces: workspaces,
    );
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  OpenQuestion question(String id) =>
      SpecDocument.parse(read(specPath)).openQuestions
          .firstWhere((q) => q.id == id);

  test('"Simplificar agora → débito" writes the row with "(spec 33, P5)" '
      'and "→ débito técnico DT-01" in the answer (R6)', () async {
    final q = question('P5');
    final draft = DebtInterview.debtDraftFor(
      question: 'Arquivos recusados não ficam guardados',
      answer: 'por ora só recusamos o envio',
      suggestion: q.suggestion,
      origin: DebtInterview.originOf(spec, q.id),
    );
    final r = await interview.record(ws, spec, q.id, draft);
    expect(r.written.code, 'DT-01');
    expect(r.annotated, isTrue);
    final row = read('DEBITO_TECNICO.md');
    expect(
      row,
      contains(
        '| DT-01 | 2026-11-24 | **Arquivos recusados não ficam guardados**: '
        'por ora só recusamos o envio (spec 33, P5). | — | '
        'guardar no S3 por 30 dias |',
      ),
    );
    final out = read(specPath);
    expect(out, contains('- P5 · → débito técnico DT-01 (2026-11-24)'));
    expect(SpecDocument.parse(out).openQuestions.map((x) => x.id), [
      'P6',
      'P7',
    ]);
    final l = await links.byCode(root, 'DT-01');
    expect(l!.originSpecId, spec.id);
    expect(l.originQuestion, 'P5');
  });

  test('"Decidir depois → DP" writes the decision with the suggestion as the '
      'recommendation and "→ DP-01" in the answer (R6)', () async {
    final q = question('P7');
    final r = await interview.record(
      ws,
      spec,
      q.id,
      DebtInterview.decisionDraftFor(
        question: q.text,
        suggestion: q.suggestion,
        origin: DebtInterview.decisionOriginOf(spec, q.id),
      ),
    );
    expect(r.written.code, 'DP-01');
    final d = DebtDocument.parse(
      read('DECISOES_PENDENTES.md'),
      DebtKind.decision,
    ).decisions.single;
    expect(d.origin, '[Spec 33]($specPath) P7');
    expect(d.originSpecNumber, 33);
    expect(d.originQuestion, 'P7');
    expect(d.recommendation, 'recusar no envio');
    expect(d.decided, isFalse);
    expect(read(specPath), contains('- P7 · → DP-01 (2026-11-24)'));
  });

  test(
    'with an open worktree the row goes to the worktree file (R18)',
    () async {
      final wt = Directory('${dir.path}-wt')..createSync();
      addTearDown(() => wt.deleteSync(recursive: true));
      final withWt = spec.copyWith(worktreePath: Value(wt.path));
      await interview.record(
        ws,
        withWt,
        'P5',
        DebtInterview.debtDraftFor(question: 'X', origin: 'spec 33, P5'),
      );
      expect(File('$root/DEBITO_TECNICO.md').existsSync(), isFalse);
      expect(read('DEBITO_TECNICO.md', at: wt.path), contains('DT-01'));
    },
  );

  test('"bota em débito" in an answer is a suggestion, and nothing is '
      'written until it is accepted (R7)', () async {
    final q = question('P6');
    const answer = 'bota em débito, por ora só loga o nome do arquivo';
    final id = await interview.suggestFromAnswer(ws, spec, q, answer);
    expect(id, isNotNull);
    expect(File('$root/DEBITO_TECNICO.md').existsSync(), isFalse);
    expect(read(specPath), specText);
    // The same question again updates the same suggestion.
    expect(await interview.suggestFromAnswer(ws, spec, q, answer), id);
    expect(await interview.suggestFromAnswer(ws, spec, q, 'só o nome'), isNull);
    final l = (await links.byId(id!))!;
    expect(l.suggestionState, DebtSuggestionState.pending);
    expect(l.suggestionSource, DebtSuggestionSource.interview);
    expect(l.originSpecId, spec.id);
    expect(l.originQuestion, 'P6');
    expect(l.code, isNull);

    final w = await interview.accept(id);
    expect(w.code, 'DT-01');
    expect(read('DEBITO_TECNICO.md'), contains('(spec 33, P6)'));
    expect(
      read(specPath),
      contains('- P6 · $answer → débito técnico DT-01 (2026-11-24)'),
    );
  });

  test('P2: an item of the mini-planejamento waits for the spec number, '
      'then is written with "(spec 33, P5)"', () async {
    // The draft: no spec yet.
    final draftWs = ws;
    const dq = DraftQuestion(
      'Guardar os arquivos recusados para auditoria?',
      suggestion: 'guardar no S3 por 30 dias',
    );
    await interview.deferForDraft(
      draftWs,
      dq,
      0,
      DebtInterview.debtDraftFor(
        question: 'Recusados não ficam guardados',
        suggestion: dq.suggestion,
        origin: '',
      ),
    );
    await interview.suggestFromDraftReply(draftWs, const [
      PlanQuestion(text: 'Qual o limite?', options: []),
      PlanQuestion(text: 'O que logar na recusa?', options: []),
    ], '1 - 20 MB\n2 - bota em débito, só o nome');
    final pending = await interview.draftLinks(draftWs);
    expect(pending, hasLength(2));
    expect(File('$root/DEBITO_TECNICO.md').existsSync(), isFalse);

    final out = await interview.settleDraft(draftWs, spec);
    expect(out.single.written.code, 'DT-01');
    expect(out.single.annotated, isTrue);
    expect(
      read('DEBITO_TECNICO.md'),
      contains('**Recusados não ficam guardados** (spec 33, P5).'),
    );
    expect(read(specPath), contains('- P5 · → débito técnico DT-01'));
    // The suggestion of the detector stays pending, now tied to the spec.
    final all = await links.forRepo(root);
    final sug = all.singleWhere(
      (l) => l.suggestionState == DebtSuggestionState.pending,
    );
    expect(sug.originSpecId, spec.id);
    expect(sug.originSessionId, isNull);
    expect(await interview.draftLinks(draftWs), isEmpty);
  });

  test('P2: discarding the draft takes its suggestions', () async {
    await interview.deferForDraft(
      ws,
      const DraftQuestion('Q?'),
      0,
      DebtInterview.decisionDraftFor(question: 'Q?', origin: ''),
    );
    await interview.discardDraft(ws);
    expect(await links.forRepo(root), isEmpty);
  });

  test('answering a DP fills "Decisão", takes the answer to the spec and '
      '"Virar débito" links DT and DP at both ends (R12)', () async {
    final q = question('P7');
    await interview.record(
      ws,
      spec,
      q.id,
      DebtInterview.decisionDraftFor(
        question: q.text,
        suggestion: q.suggestion,
        origin: DebtInterview.decisionOriginOf(spec, q.id),
      ),
    );
    DecisionItem dp() => DebtDocument.parse(
      read('DECISOES_PENDENTES.md'),
      DebtKind.decision,
    ).decisions.single;
    const answer = 'Recusar no envio. Comprimir no servidor fica para depois.';
    expect(DebtInterview.specPreview(dp(), answer), 'P7 → DP-01: $answer');
    final r = await interview.answerDecision(root, dp(), answer);
    expect(r.annotated, isTrue);
    expect(r.decision.decision, '**Decidido (2026-11-24):** $answer');
    expect(dp().decided, isTrue);
    expect(read(specPath), contains('- P7 · → DP-01: $answer (2026-11-24)'));

    final draft = DebtInterview.debtDraftFromDecision(
      dp(),
      leftover: 'Comprimir no servidor',
    );
    expect(draft.origin, 'spec 33, DP-01');
    final w = await interview.debtFromDecision(root, 'DP-01', draft);
    expect(w.code, 'DT-01');
    expect(
      read('DEBITO_TECNICO.md'),
      contains('**Comprimir no servidor** (spec 33, DP-01).'),
    );
    expect(dp().decision, endsWith('gerou o DT-01.'));
    expect((await links.byCode(root, 'DT-01'))!.originDecision, 'DP-01');
    // Marking twice does not repeat.
    await interview.markGenerated(root, 'DP-01', 'DT-01');
    expect('gerou o DT-01'.allMatches(dp().decision), hasLength(1));
  });

  test('a decision changed in the file since it was read is not '
      'overwritten (R5)', () async {
    await interview.record(
      ws,
      spec,
      'P7',
      DebtInterview.decisionDraftFor(question: 'Q?', origin: 'x'),
    );
    final rel = DebtFiles.relPath(
      interview.debts.configOf(root),
      DebtKind.decision,
    );
    final d = DebtDocument.parse(read(rel), DebtKind.decision).decisions.single;
    File('$root/$rel')
        .writeAsStringSync(read(rel).replaceFirst('**Q?**', '**Q editada?**'));
    expect(
      () => interview.answerDecision(root, d, 'sim'),
      throwsA(isA<DebtRowChanged>()),
    );
  });
}
