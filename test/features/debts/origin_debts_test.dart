import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/data/repos/review_comments_repo.dart';
import 'package:promptorium/features/debts/debt_service.dart';
import 'package:promptorium/features/debts/origin_debts.dart';
import 'package:promptorium/features/review/comment_anchor.dart';
import 'package:promptorium/features/review/merge_readiness.dart';

import '../../helpers/test_db.dart';

/// SPEC-112 R8, R9: the forms of "Virar débito" and the review comment that
/// became a debt (resolved, out of the count, undone).
void main() {
  group('pure helpers', () {
    test('the selected excerpt wins; else the first paragraph (R9)', () {
      const msg =
          '## Resumo\n\nO upload lê o arquivo inteiro.\nIsso pesa no worker.'
          '\n\nSegundo parágrafo.';
      expect(
        messageDebtExcerpt(msg),
        'Resumo',
        reason: 'a heading is a paragraph of its own, without the marks',
      );
      const body =
          'O upload lê o arquivo inteiro.\nIsso pesa no worker.\n\n'
          '```py\nx = 1\n```\n\nSegundo parágrafo.';
      expect(
        messageDebtExcerpt(body),
        'O upload lê o arquivo inteiro. Isso pesa no worker.',
      );
      expect(
        messageDebtExcerpt(body, selection: '  Segundo parágrafo.  '),
        'Segundo parágrafo.',
      );
      expect(
        messageDebtExcerpt(body, selection: '   '),
        startsWith('O upload'),
      );
      expect(
        messageDebtExcerpt('```\ncode\n```\n\n- item da lista'),
        'item da lista',
      );
    });

    test('the message form: first sentence as title, the rest as motive', () {
      final d = messageDebtDraft(
        'O upload lê o arquivo inteiro. Um vídeo de 1 GB pesa no worker.\n\n'
        'Depois.',
        origin: 'sessão upload',
      );
      expect(d.title, 'O upload lê o arquivo inteiro');
      expect(d.reason, 'Um vídeo de 1 GB pesa no worker');
      expect(d.origin, 'sessão upload');
    });

    test('the function of "Onde" comes from the hunk', () {
      final file = DiffParser.parse(
        'diff --git a/app/arquivos.py b/app/arquivos.py\n'
        '--- a/app/arquivos.py\n'
        '+++ b/app/arquivos.py\n'
        '@@ -40,3 +40,4 @@ class Upload:\n'
        ' def validar_upload(arquivo: UploadFile) -> None:\n'
        '-    pass\n'
        '+    LIMITE = 20\n'
        '+    conteudo = arquivo.file.read()\n'
        '+    return conteudo\n',
      ).single;
      expect(enclosingFunction(file, 42), 'validar_upload');
      expect(functionNameIn('  Future<void> save(String x) async {'), 'save');
      expect(functionNameIn('const parse = (t) => {'), 'parse');
      expect(functionNameIn('  if (x) {'), isNull);
      expect(functionNameIn('class Upload:'), isNull);
    });
  });

  group('review comment (R8)', () {
    late Directory dir;
    late String repo, wt;
    late AppDatabase db;
    late DebtService service;
    late OriginDebts origin;
    late ReviewCommentsRepo comments;
    late DebtLinksRepo links;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('origin_debts_');
      repo = '${dir.path}/repo';
      wt = '${dir.path}/wt';
      Directory(repo).createSync();
      Directory(wt).createSync();
      db = memoryDatabase();
      links = DebtLinksRepo(db);
      comments = ReviewCommentsRepo(db);
      service = DebtService(links: links, now: () => DateTime(2026, 11, 25));
      origin = OriginDebts(links: links, comments: comments);
      await db.customStatement(
        "INSERT INTO workspaces(path,name) VALUES('$repo','r')",
      );
      await db.customStatement(
        "INSERT INTO specs(workspace_id,code,title,path) "
        "VALUES(1,'SPEC-033','Limite','specs/33.md')",
      );
      await comments.insertAll([
        for (final (line, body) in [
          (
            42,
            'validar_upload lê o arquivo inteiro na memória. Um vídeo de 1 GB pesa.',
          ),
          (44, 'ArquivoGrande não tem handler.'),
          (45, 'Log sem o tamanho.'),
        ])
          ReviewCommentsCompanion.insert(
            specId: const Value(1),
            round: 1,
            author: 'revisor',
            body: body,
            path: const Value('backend/app/arquivos.py'),
            line: Value(line),
          ),
      ]);
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    Future<ReadinessInputs> inputs() async {
      final rows = await comments.bySpec(1);
      return ReadinessInputs(
        hasSpec: true,
        openComments: rows.where(isOpenReviewComment).length,
        debtComments: await links.codesOfReviewComments([
          for (final r in rows) r.id,
        ]),
      );
    }

    ReadinessItem comentarios(ReadinessInputs f) =>
        evaluateReadiness(f).items.firstWhere((i) => i.id == 'comentarios');

    Future<DebtWritten> turn(ReviewCommentRow c) async {
      final draft = reviewCommentDraft(
        c,
        specLabel: 'spec 33',
        function: 'validar_upload',
      );
      expect(draft.title, 'validar_upload lê o arquivo inteiro na memória');
      expect(draft.reason, 'Um vídeo de 1 GB pesa');
      expect(draft.where, '`backend/app/arquivos.py`, `validar_upload`');
      expect(draft.origin, 'revisão da spec 33');
      final w = await service.create(
        repo,
        draft,
        writeRoot: wt,
        link: DebtLinksCompanion(
          originSpecId: const Value(1),
          originReviewCommentId: Value(c.id),
        ),
      );
      await origin.settleReviewComment(w, c.id);
      return w;
    }

    test('"Virar débito" resolves the comment, gives the seal, lowers the '
        'count and frees the merge; Desfazer gives it back', () async {
      final before = await inputs();
      expect(before.openComments, 3);
      expect(comentarios(before).detail, '3 comentários abertos');
      final first = (await comments.bySpec(1)).first;
      final w = await turn(first);
      expect(w.code, 'DT-01');
      expect(w.root, wt, reason: 'the row goes to the worktree of the spec');
      expect(
        File('$wt/DEBITO_TECNICO.md').readAsStringSync(),
        contains(
          '| DT-01 | 2026-11-25 | **validar_upload lê o arquivo inteiro na '
          'memória**: Um vídeo de 1 GB pesa (revisão da spec 33). | '
          '`backend/app/arquivos.py`, `validar_upload` | — |',
        ),
      );
      expect(File('$repo/DEBITO_TECNICO.md').existsSync(), isFalse);
      // The seal comes from the link.
      expect(await links.watchReviewCommentCodes().first, {first.id: 'DT-01'});
      final after = await inputs();
      expect(after.openComments, 2);
      expect(
        comentarios(after).detail,
        '2 comentários abertos · 1 virou débito: DT-01',
      );
      // The suggestion strip never sees the row kept in the link.
      final link = (await links.ofReviewComment(first.id))!;
      expect(link.suggestionState, isNull);
      expect(OriginDebts.writtenRowOf(link), startsWith('| DT-01 |'));

      // With the other two treated, nothing about comments holds the merge.
      for (final c in (await comments.bySpec(1)).skip(1)) {
        await comments.setResolved(c.id, true);
      }
      final done = evaluateReadiness(await inputs());
      expect(
        done.items.firstWhere((i) => i.id == 'comentarios').level,
        ReadinessLevel.ok,
      );
      expect(done.blockers, isEmpty);
      expect(done.warnings.map((i) => i.id), isNot(contains('comentarios')));

      // Desfazer: the row leaves the worktree file, the link goes and the
      // comment counts again.
      final r = await origin.undoReviewComment(first.id, writeRoot: wt);
      expect(r, ReviewDebtUndo.removed);
      expect(
        File('$wt/DEBITO_TECNICO.md').readAsStringSync(),
        isNot(contains('DT-01')),
      );
      expect(await links.ofReviewComment(first.id), isNull);
      final undone = await inputs();
      expect(undone.openComments, 1);
      expect(undone.debtComments, isEmpty);
      expect(comentarios(undone).detail, '1 comentários abertos');
    });

    test('Desfazer keeps a row changed since it was written, and only '
        'warns', () async {
      final first = (await comments.bySpec(1)).first;
      await turn(first);
      final f = File('$wt/DEBITO_TECNICO.md');
      f.writeAsStringSync(
        f.readAsStringSync().replaceFirst('| — |', '| fazer em streaming |'),
      );
      final r = await origin.undoReviewComment(first.id, writeRoot: wt);
      expect(r, ReviewDebtUndo.rowChanged);
      expect(f.readAsStringSync(), contains('fazer em streaming'));
      expect(await links.ofReviewComment(first.id), isNull);
      expect(
        (await comments.bySpec(1)).firstWhere((c) => c.id == first.id).resolved,
        isFalse,
      );
    });
  });
}
