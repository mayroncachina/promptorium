import 'dart:io';

import 'package:drift/drift.dart' show Value;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/board/widgets/board_tray.dart';
import 'package:promptorium/features/issues/widgets/issue_badge.dart';
import 'package:promptorium/features/specs/spec_lint.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart';
import 'package:promptorium/features/specs/widgets/spec_list.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// The link between a spec and its GitHub issue (SPEC-074 R1, R12).
void main() {
  group('SpecDocument.issue', () {
    test('reads the number, writes it and removes it', () {
      final doc = SpecDocument.parse(
        '---\nid: SPEC-023\nstatus: rascunho\nissue: 226\n---\n# Pix\n',
      );
      expect(doc.issue, 226);
      expect(doc.hasInvalidIssue, isFalse);
      expect(
        SpecDocument.parse('---\nid: SPEC-1\nissue: "#215"\n---\n').issue,
        215,
      );
      expect(SpecDocument.parse('---\nid: SPEC-1\n---\n').issue, isNull);

      final linked = SpecDocument.parse(
        '---\nid: SPEC-027\nstatus: rascunho\n---\n# CSV\n',
      ).withIssue(251);
      expect(linked, contains('issue: 251\n'));
      expect(SpecDocument.parse(linked).issue, 251);
      final changed = SpecDocument.parse(linked).withIssue(252);
      expect(RegExp('issue:').allMatches(changed), hasLength(1));
      final off = SpecDocument.parse(linked).withIssue(null);
      expect(off, isNot(contains('issue:')));
      expect(off, contains('id: SPEC-027\nstatus: rascunho\n'));
    });

    test('an invalid value is a structure warning and has no number', () {
      const text =
          '---\nid: SPEC-023\nstatus: rascunho\nissue: abc\n---\n# Pix\n';
      final doc = SpecDocument.parse(text);
      expect(doc.issue, isNull);
      expect(doc.hasInvalidIssue, isTrue);
      final w = lintSpec(text)
          .where((w) => w.kind == SpecWarningKind.invalidIssue);
      expect(w.single.line, 4);
      expect(w.single.message, contains('abc'));
      // `issue:` is a known key: no "Chave desconhecida".
      expect(
        lintSpec('---\nid: SPEC-023\nissue: 226\n---\n')
            .where((w) => w.kind == SpecWarningKind.unknownFrontmatterKey),
        isEmpty,
      );
      expect(specIssueKey, 'issue');
      expect(knownFrontmatterKeys, contains(specIssueKey));
    });
  });

  group('sync', () {
    late Directory root;
    late AppDatabase db;
    late Workspace ws;
    late SpecsRepo repo;
    late SpecService service;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('spec-issue-');
      db = memoryDatabase();
      ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: root.path, name: 'ws'),
          );
      repo = SpecsRepo(db);
      service = SpecService(repo);
    });
    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });

    void write(String code, String meta) {
      final f = File('${root.path}/specs/$code.md');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('---\nid: $code\n$meta---\n# $code\n');
    }

    test('the specs that already have issue: get the number without any '
        'change; another number forgets the old state', () async {
      write('SPEC-023', 'status: aprovada\nissue: 226\n');
      write('SPEC-024', 'status: rascunho\nissue: abc\n');
      write('SPEC-025', 'status: rascunho\n');
      await service.sync(ws);
      final linked = (await repo.getByCode(ws.id, 'SPEC-023'))!;
      expect(linked.issueNumber, 226);
      expect((await repo.getByCode(ws.id, 'SPEC-024'))!.issueNumber, isNull);
      expect((await repo.getByCode(ws.id, 'SPEC-025'))!.issueNumber, isNull);

      await repo.update(
        linked.id,
        const SpecsCompanion(
          issueState: Value(IssueState.closed),
          issueClosedBy: Value('PR #250'),
        ),
      );
      await service.sync(ws);
      expect(
        (await repo.getByCode(ws.id, 'SPEC-023'))!.issueState,
        IssueState.closed,
      );
      write('SPEC-023', 'status: aprovada\nissue: 227\n');
      await service.sync(ws);
      final moved = (await repo.getByCode(ws.id, 'SPEC-023'))!;
      expect(moved.issueNumber, 227);
      expect(moved.issueState, isNull);
      expect(moved.issueClosedBy, isNull);
    });

    test('this repository: every spec with issue: gets its number', () async {
      final dir = Directory('docs/specs');
      final withIssue = <String, int>{};
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.md')) continue;
        final doc = SpecDocument.parse(f.readAsStringSync());
        if (doc.issue != null && doc.id != null) {
          withIssue[doc.id!] = doc.issue!;
        }
      }
      expect(withIssue['SPEC-074'], 243);
      final copy = Directory('${root.path}/specs')..createSync();
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.md')) {
          f.copySync('${copy.path}/${f.uri.pathSegments.last}');
        }
      }
      await service.sync(ws);
      for (final e in withIssue.entries) {
        expect(
          (await repo.getByCode(ws.id, e.key))?.issueNumber,
          e.value,
          reason: e.key,
        );
      }
    });
  });

  group('the badge', () {
    Spec spec({
      int? issue = 226,
      IssueState? state,
      DateTime? closedAt,
      String? closedBy,
      bool pending = false,
    }) => Spec(
      id: 1,
      workspaceId: 1,
      code: 'SPEC-023',
      title: 'Pix com QR code',
      path: 'specs/SPEC-023.md',
      status: SpecStatus.draft,
      stage: SpecStage.backlog,
      requirements: const [],
      dependsOn: const [],
      reviewRounds: 0,
      hasPlan: false,
      gateResends: 0,
      rejectedHunks: 0,
      inTray: true,
      kind: SpecKind.spec,
      issueNumber: issue,
      issueState: state,
      issueClosedAt: closedAt,
      issueClosedBy: closedBy,
      issueCommentPending: pending,
      autoAdvance: false,
    );

    test('the states are text: open, closed with who closed it, not found '
        'and a pending comment (R9, R10, R12)', () {
      expect(issueBadgeText(spec(state: IssueState.open)).text, '#226');
      expect(
        issueBadgeText(spec(state: IssueState.open)).semantics,
        'Issue 226, aberta',
      );
      final closed = issueBadgeText(
        spec(
          state: IssueState.closed,
          closedAt: DateTime(2026, 11, 14, 12),
          closedBy: 'PR #250',
        ),
      );
      expect(closed.text, '#226 fechada');
      expect(closed.semantics, 'Issue 226, fechada');
      expect(
        closed.tooltip,
        startsWith('Fechada no GitHub em 14/11, pelo PR #250'),
      );
      expect(
        issueBadgeText(spec(state: IssueState.closed, closedBy: 'à mão'))
            .tooltip,
        startsWith('Fechada no GitHub, à mão'),
      );
      expect(
        issueBadgeText(spec(state: IssueState.notFound)).text,
        '#226 não encontrada',
      );
      expect(
        issueBadgeText(spec(pending: true)).text,
        '#226 · comentário pendente',
      );
    });

    Future<void> pump(WidgetTester tester, Widget child) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseOverride(db)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: child),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the Bandeja, the list and the header show #N; without '
        'issue: no badge', (tester) async {
      final linked = spec();
      await pump(
        tester,
        Row(
          children: [
            BoardTray(workspaceId: 1, specs: [linked]),
            SizedBox(
              width: 300,
              child: SpecList(
                specs: [linked],
                selectedId: null,
                stepRows: const [],
                onSelect: (_) {},
              ),
            ),
            Expanded(
              child: SpecHeader(
                title: linked.title,
                path: linked.path,
                issueBadge: IssueBadge(spec: linked),
              ),
            ),
          ],
        ),
      );
      expect(
        find.byKey(const ValueKey('issue-badge-SPEC-023')),
        findsNWidgets(3),
      );
      expect(find.text('#226'), findsNWidgets(3));
      expect(find.bySemanticsLabel('Issue 226'), findsNWidgets(3));

      await pump(tester, BoardTray(workspaceId: 1, specs: [spec(issue: null)]));
      expect(find.byKey(const ValueKey('issue-badge-SPEC-023')), findsNothing);
    });
  });
}
