import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/auto_reviewer.dart';
import 'package:promptorium/features/review/merge_readiness.dart';
import 'package:promptorium/features/review/reviewer_provider.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-102 R7, R9, R2: who reviewed each round in the Review.
void main() {
  Future<(ProviderContainer, int)> setUp(
    WidgetTester tester, {
    required List<ReviewCommentsCompanion Function(int specId)> rows,
    String executedBy = 'claude',
    bool ownAgent = false,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-author-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-031.md').writeAsStringSync(
      '---\nid: SPEC-031\n---\n# Pagamento\n\n## Requisitos\n\n- R1 · x\n',
    );
    if (ownAgent) {
      File('${tmp.path}/.claude/agents/spec-reviewer.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    final id = await tester.runAsync(() async {
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: tmp.path, name: 'w');
      final s = await c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-031',
            title: 'Pagamento',
            path: 'specs/SPEC-031.md',
            requirements: const [(id: 'R1', text: 'x')],
          );
      await c
          .read(sessionsRepoProvider)
          .insert(
            id: 'exec',
            workspaceId: ws.id,
            worktreePath: tmp.path,
            branch: 'b',
            model: 'm',
            provider: executedBy,
            specId: s.id,
          );
      await c.read(reviewCommentsRepoProvider).insertAll([
        for (final r in rows) r(s.id),
      ]);
      return s.id;
    });
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: SpecReviewPanel(specId: id!)),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    return (c, id);
  }

  ReviewCommentsCompanion Function(int) verdict(
    int round, {
    String? provider,
    String? model,
    String verdict = 'corrigir',
  }) =>
      (id) => ReviewCommentsCompanion.insert(
        specId: Value(id),
        round: round,
        author: 'revisor',
        body: 'Resumo $round',
        verdict: Value(verdict),
        commitSha: const Value('9f3c2a1ffff'),
        provider: Value(provider),
        model: Value(model),
      );

  ReviewCommentsCompanion Function(int) comment(int round) =>
      (id) => ReviewCommentsCompanion.insert(
        specId: Value(id),
        round: round,
        author: 'revisor',
        path: const Value('lib/a.dart'),
        line: const Value(42),
        body: 'trate o erro',
        severity: const Value('alta'),
      );

  String title(WidgetTester tester, int round) =>
      tester.widget<Text>(find.byKey(ValueKey('review-round-$round'))).data!;

  testWidgets('rodada nova mostra provedor e modelo; a antiga, sem o dado, '
      'continua como antes (R9)', (tester) async {
    await setUp(
      tester,
      executedBy: 'codex',
      rows: [
        verdict(1),
        comment(1),
        verdict(2, provider: 'codex', model: 'gpt-6.1-terra'),
        comment(2),
        comment(2),
        comment(2),
      ],
    );
    expect(
      title(tester, 1),
      'Rodada 1 · Revisor automático · pediu correções · 9f3c2a1',
    );
    expect(
      title(tester, 2),
      'Rodada 2 · Revisor automático · Codex gpt-6.1-terra · pediu correções '
      '· 3 comentários · 9f3c2a1',
    );
    expect(find.byKey(const ValueKey('review-own-agent-notice')), findsNothing);
  });

  testWidgets('o outro provedor leva "segunda opinião"; revisor do projeto '
      'no Codex mostra o aviso uma vez (R7, R9)', (tester) async {
    await setUp(
      tester,
      ownAgent: true,
      rows: [
        verdict(1, provider: 'codex', model: 'gpt-6.1-terra'),
        verdict(
          2,
          provider: 'codex',
          model: 'gpt-6.1-terra',
          verdict: 'aprovar',
        ),
      ],
    );
    expect(
      title(tester, 2),
      'Rodada 2 · Revisor automático · Codex gpt-6.1-terra · segunda opinião '
      '· aprovou · 9f3c2a1',
    );
    expect(find.text(ownReviewerAgentNotice), findsOneWidget);
  });

  testWidgets('falha do provedor oferece o outro "desta vez" (R2)', (
    tester,
  ) async {
    await setUp(
      tester,
      rows: [
        (id) => ReviewCommentsCompanion.insert(
          specId: Value(id),
          round: 1,
          author: 'revisor',
          body: '${AutoReviewer.failurePrefix}: Falha ao iniciar Codex: x',
          provider: const Value('codex'),
        ),
      ],
    );
    expect(
      find.widgetWithText(Material, 'Revisar com o Claude Code desta vez'),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('review-retry-other-1')), findsOneWidget);
  });

  test('prontidão do merge mostra quem revisou (R9)', () {
    final r = evaluateReadiness(
      const ReadinessInputs(
        hasSpec: true,
        reviewerAuthor: 'Codex · segunda opinião · pediu correções',
      ),
    );
    final item = r.items.firstWhere((i) => i.id == 'revisor');
    expect(item.detail, 'Codex · segunda opinião · pediu correções');
    expect(item.level, ReadinessLevel.ok);
    // Without the data (rounds of before): as before.
    final old = evaluateReadiness(const ReadinessInputs(hasSpec: true));
    expect(old.items.firstWhere((i) => i.id == 'revisor').detail, 'OK');
  });
}
