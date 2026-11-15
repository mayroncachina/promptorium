import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/gh_issues.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/ideas/idea_import.dart' show ideaMaxChars;
import 'package:promptorium/features/issues/issue_actions.dart';
import 'package:promptorium/features/issues/issue_availability.dart';
import 'package:promptorium/features/issues/issue_import.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/fake_issues.dart';
import '../../helpers/test_db.dart';
import 'specs_screen_test.dart' show settleIo;

GhIssue issue(int n, String title, {String body = '', String? updatedAt}) =>
    GhIssue(
      number: n,
      title: title,
      body: body,
      updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt),
    );

/// "Importar issues": the text of the spec, the import without duplicates,
/// "Atualizar com a issue" and "Desligar da issue" (SPEC-074 R4, R5, R7).
void main() {
  group('the text of the issue becomes the Objetivo (R5)', () {
    test('HTML comments out, headings down, checklists, links and images '
        'kept', () {
      final r = issueToSpecText(
        issue(
          215,
          'Cupom não aplica em produto já com desconto',
          body:
              '<!-- Descreva o bug abaixo -->\n'
              '# Contexto\n'
              'O cupom some.\n\n'
              '## Passos\n'
              '- [ ] abrir o carrinho\n'
              '- [x] aplicar o cupom\n\n'
              'Veja [o print](https://x/a.png) e ![tela](https://x/b.png)\n'
              '```\n# não é título\n```\n'
              '<!--\nmodelo\n-->',
        ),
        'SPEC-025',
      );
      expect(r.truncated, isFalse);
      final doc = SpecDocument.parse(r.text);
      expect(doc.id, 'SPEC-025');
      expect(doc.status, SpecStatus.draft);
      expect(doc.issue, 215);
      expect(doc.title, 'Cupom não aplica em produto já com desconto');
      final o = doc.objective!;
      expect(o, isNot(contains('<!--')));
      expect(o, isNot(contains('modelo')));
      expect(o, contains('### Contexto'));
      expect(o, contains('#### Passos'));
      expect(o, contains('- [ ] abrir o carrinho'));
      expect(o, contains('- [x] aplicar o cupom'));
      expect(o, contains('[o print](https://x/a.png)'));
      expect(o, contains('![tela](https://x/b.png)'));
      expect(o, contains('```\n# não é título\n```'));
      // Requisitos and Critérios wait for the refinement.
      expect(doc.requirements, isEmpty);
      expect(doc.section('Requisitos'), contains('Refinar requisitos'));
      expect(doc.section('Critérios de aceite'), contains('Refinar'));
    });

    test('over 40.000 characters: cut at the end of a paragraph, with a '
        'notice', () {
      final para = '${'a' * 999}\n\n';
      final body = para * 45;
      final o = issueObjective(body);
      expect(o.truncated, isTrue);
      expect(o.text.length, lessThanOrEqualTo(ideaMaxChars));
      expect(o.text.endsWith('a'), isTrue);
      final r = issueToSpecText(issue(9, 'Grande', body: body), 'SPEC-009');
      expect(r.truncated, isTrue);
      expect(r.text, contains('foi cortado em $ideaMaxChars'));
      expect(issueObjective('curto').truncated, isFalse);
    });

    test('predicted codes and the final notice', () {
      expect(predictedCodes([212, 215, 218], 24), {
        212: 'SPEC-024',
        215: 'SPEC-025',
        218: 'SPEC-026',
      });
    });
  });

  group('import', () {
    late Directory root;
    late AppDatabase db;
    late Workspace ws;
    late SpecsRepo repo;
    late SpecService service;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('issue-import-');
      Directory('${root.path}/specs').createSync();
      File('${root.path}/specs/SPEC-023-pix.md').writeAsStringSync(
        '---\nid: SPEC-023\nstatus: aprovada\nissue: 226\n---\n# Pix\n',
      );
      db = memoryDatabase();
      ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: root.path, name: 'ws'),
          );
      repo = SpecsRepo(db);
      service = SpecService(repo);
      await service.sync(ws);
    });
    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });

    test('3 issues become 3 drafts with issue: N in the Bandeja; the one '
        'already imported is skipped', () async {
      final r = await importIssues(service, repo, ws, [
        issue(212, 'Carrinho some ao trocar de aba'),
        issue(215, 'Cupom não aplica'),
        issue(226, 'Pix com QR code'),
        issue(218, 'Frete grátis acima de R\$ 199'),
      ], now: () => DateTime(2026, 11, 15, 10));
      expect(r.created.map((s) => (s.code, s.issueNumber)), [
        ('SPEC-024', 212),
        ('SPEC-025', 215),
        ('SPEC-026', 218),
      ]);
      expect(r.skipped, {226: 'SPEC-023'});
      expect(r.message, '3 issues viraram SPEC-024 a SPEC-026, na Bandeja');
      for (final s in r.created) {
        expect(s.status, SpecStatus.draft);
        expect(s.inTray, isTrue);
        expect(s.issueImportedAt, DateTime(2026, 11, 15, 10));
        expect(s.issueState, IssueState.open);
        final text = (await service.read(ws, s))!;
        expect(SpecDocument.parse(text).issue, s.issueNumber);
      }
      // Imported again: nothing new.
      final again = await importIssues(service, repo, ws, [
        issue(212, 'Carrinho'),
      ]);
      expect(again.created, isEmpty);
      expect(again.skipped, {212: 'SPEC-024'});
    });

    test('two imports at the same time never make two specs for one issue '
        '(R4)', () async {
      final results = await Future.wait([
        importIssues(service, repo, ws, [issue(212, 'A'), issue(215, 'B')]),
        importIssues(service, repo, ws, [issue(215, 'B'), issue(218, 'C')]),
      ]);
      final all = await repo.watchByWorkspace(ws.id).first;
      final byIssue = <int, int>{};
      for (final s in all) {
        if (s.issueNumber case final n?) byIssue[n] = (byIssue[n] ?? 0) + 1;
      }
      expect(byIssue, {226: 1, 212: 1, 215: 1, 218: 1});
      expect(results.expand((r) => r.created), hasLength(3));
      expect(results[1].skipped.keys, [215]);
    });

    test('the issue changed after the import: "texto mudou"', () {
      final spec = Spec(
        id: 1,
        workspaceId: 1,
        code: 'SPEC-024',
        title: 'x',
        path: 'x',
        status: SpecStatus.draft,
        stage: SpecStage.backlog,
        requirements: const [],
        dependsOn: const [],
        hasPlan: false,
        autoAdvance: false,
        reviewRounds: 0,
        gateResends: 0,
        rejectedHunks: 0,
        inTray: true,
        kind: SpecKind.spec,
        issueCommentPending: false,
        issueNumber: 212,
        issueImportedAt: DateTime.utc(2026, 11, 10),
      );
      expect(
        issueChanged(spec, issue(212, 'x', updatedAt: '2026-11-12T00:00:00Z')),
        isTrue,
      );
      expect(
        issueChanged(spec, issue(212, 'x', updatedAt: '2026-11-09T00:00:00Z')),
        isFalse,
      );
    });
  });

  group('"Atualizar com a issue" and "Desligar da issue" (R7)', () {
    late Directory root;
    late AppDatabase db;
    late ProviderContainer c;
    late Workspace ws;
    late FakeIssuesGh gh;

    Future<Spec> pump(WidgetTester tester, String status) async {
      root = Directory.systemTemp.createTempSync('issue-update-');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/specs').createSync();
      File('${root.path}/specs/SPEC-024-carrinho.md').writeAsStringSync(
        '---\nid: SPEC-024\nstatus: $status\nissue: 212\n---\n# Carrinho\n\n'
        '## Objetivo\n\nTexto antigo.\n\n## Requisitos\n\n- R1 · x\n',
      );
      db = memoryDatabase();
      gh = FakeIssuesGh()
        ..add(
          212,
          'Carrinho',
          body: 'Texto novo da issue.',
          updatedAt: '2026-11-14T00:00:00Z',
        );
      c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          cliRunnerProvider.overrideWithValue(gh.call),
          issueAvailabilityProvider.overrideWith(
            (ref, root) async =>
                const IssueAvailability.ok(repo: 'ana-souza/loja-da-ana'),
          ),
        ],
      );
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      late Spec spec;
      await tester.runAsync(() async {
        ws = await c
            .read(workspacesRepoProvider)
            .add(path: root.path, name: 'ws');
        await c.read(specServiceProvider).sync(ws);
        spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-024'))!;
        await c
            .read(specsRepoProvider)
            .update(
              spec.id,
              SpecsCompanion(issueImportedAt: Value(DateTime.utc(2026, 11, 1))),
            );
        spec = (await c.read(specsRepoProvider).getById(spec.id))!;
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    TextButton(
                      key: const ValueKey('do-update'),
                      onPressed: () => updateFromIssue(context, ref, spec),
                      child: const Text('update'),
                    ),
                    TextButton(
                      key: const ValueKey('do-unlink'),
                      onPressed: () => unlinkIssue(context, ref, spec),
                      child: const Text('unlink'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return spec;
    }

    String file() =>
        File('${root.path}/specs/SPEC-024-carrinho.md').readAsStringSync();

    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('a draft: before and after, written only on confirmation', (
      tester,
    ) async {
      await pump(tester, 'rascunho');
      await tester.tap(key('do-update'));
      await settleIo(
        tester,
        until: () => key('issue-update-dialog').evaluate().isNotEmpty,
      );
      expect(find.text('Texto antigo.'), findsOneWidget);
      expect(find.text('Texto novo da issue.'), findsOneWidget);
      await tester.tap(key('issue-update-cancel'));
      await settleIo(tester);
      expect(file(), contains('Texto antigo.'));

      await tester.tap(key('do-update'));
      await settleIo(
        tester,
        until: () => key('issue-update-dialog').evaluate().isNotEmpty,
      );
      await tester.tap(key('issue-update-confirm'));
      await settleIo(tester, until: () => file().contains('Texto novo'));
      expect(file(), contains('## Objetivo\n\nTexto novo da issue.'));
      expect(file(), contains('- R1 · x'));
      expect(gh.writes, isEmpty, reason: 'nothing goes to GitHub');
    });

    testWidgets('an approved spec only gets a notice', (tester) async {
      await pump(tester, 'aprovada');
      await tester.tap(key('do-update'));
      await settleIo(
        tester,
        until: () =>
            find.textContaining('não é mais rascunho').evaluate().isNotEmpty,
      );
      expect(key('issue-update-dialog'), findsNothing);
      expect(file(), contains('Texto antigo.'));
    });

    testWidgets('unlinking asks, then removes issue:', (tester) async {
      final spec = await pump(tester, 'rascunho');
      await tester.tap(key('do-unlink'));
      await settleIo(
        tester,
        until: () => key('issue-unlink-dialog').evaluate().isNotEmpty,
      );
      await tester.tap(key('issue-unlink-cancel'));
      await settleIo(tester);
      expect(file(), contains('issue: 212'));
      await tester.tap(key('do-unlink'));
      await settleIo(
        tester,
        until: () => key('issue-unlink-dialog').evaluate().isNotEmpty,
      );
      await tester.tap(key('issue-unlink-confirm'));
      await settleIo(tester, until: () => !file().contains('issue:'));
      await settleIo(tester);
      expect(file(), contains('id: SPEC-024\nstatus: rascunho\n---'));
      Spec? after;
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () async => after = await c.read(specsRepoProvider).getById(spec.id),
        );
        if (after?.issueImportedAt == null) break;
        await settleIo(tester);
      }
      expect(after!.issueNumber, isNull);
      expect(after!.issueImportedAt, isNull);
    });
  });
}
