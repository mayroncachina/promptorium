import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/secrets/secret_guard.dart';
import 'package:promptorium/core/secrets/secret_rules.dart';
import 'package:promptorium/core/secrets/secret_scanner.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/secrets/secret_actions.dart';
import 'package:promptorium/features/secrets/secret_blocks.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/secret_block_card.dart';
import 'package:promptorium/features/sessions/widgets/tool_expanded_view.dart'
    show openInCodeProvider;
import 'package:promptorium/ui/widgets/secret_findings_dialog.dart';

import '../../../core/git/git_test_utils.dart';
import '../../../core/secrets/fake_secrets.dart';
import '../../../helpers/test_db.dart';
import '../session_test_utils.dart';

/// SPEC-085 R9, R11, R12: the actions of the card.
void main() {
  group('actions', () {
    late Directory tmp;
    late String repo;
    late ProviderContainer c;
    late int ws;
    const sid = 's-secret';

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-secret-card-');
      repo = await createRepo(tmp);
      c = sessionContainer(
        sessionOverrides(
          db: memoryDatabase(),
          cli: FakeCli(),
          notifier: FakeNotifier(),
        ),
      );
      await c.read(appSettingsProvider.notifier).load();
      ws = (await c.read(workspacesRepoProvider).add(path: repo, name: 'r')).id;
      await c
          .read(sessionsRepoProvider)
          .insert(
            id: sid,
            workspaceId: ws,
            worktreePath: repo,
            branch: 'main',
            model: 'sonnet',
            title: 'SPEC-031 · Stripe',
          );
    });

    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    /// Messages the session got (resumed with the notice, R9).
    Future<List<String>> sent() async => [
      for (final e in await c.read(sessionsRepoProvider).events(sid))
        if (e.type == AppEventTypes.user)
          (jsonDecode(e.json) as Map)['text'] as String,
    ];

    /// The findings of what a commit would take now, as a block of the
    /// session's timeline.
    Future<SecretBlockItem> block() async {
      final res = await c
          .read(secretGuardProvider)
          .scan(repo, SecretCheckKind.commit, workspaceId: ws);
      await c
          .read(sessionManagerProvider.notifier)
          .appendSecretEvent(
            sid,
            AppEventTypes.secretsEvent(
              block: 'b1',
              action: 'commit',
              findings: [for (final f in res.findings) f.toJson()],
            ),
          );
      c
          .read(secretBlocksProvider.notifier)
          .add(
            PendingSecret(
              key: sessionSecretKey(sid),
              workspaceId: ws,
              sessionId: sid,
              title: 't',
              findings: res.findings,
              at: DateTime.now(),
            ),
          );
      final t = Timeline();
      for (final e in await c.read(sessionsRepoProvider).events(sid)) {
        t.applyStored(e.json);
      }
      return t.secretBlock('b1')!;
    }

    test('"Remover" a .env takes it out of the index, into .gitignore, '
        'keeps it on disk; the agent hears it can commit again', () async {
      File('$repo/.env').writeAsStringSync('A=1\n');
      await gitIn(repo, ['add', '.env']);
      final b = await block();
      final env = b.findings.single;
      expect(env.ruleId, 'env-file');
      await c.read(secretActionsProvider).removeInSession(sid, b, env);
      final staged = await gitIn(repo, ['diff', '--cached', '--name-only']);
      expect(staged, isNot(contains('.env')));
      expect(File('$repo/.gitignore').readAsStringSync(), contains('/.env'));
      expect(File('$repo/.env').existsSync(), isTrue);
      expect(await sent(), [secretsResolvedMessage]);
      expect(c.read(secretBlocksProvider), isEmpty);
      // Nothing left for the next commit.
      final again = await c
          .read(secretGuardProvider)
          .scan(repo, SecretCheckKind.commit, workspaceId: ws);
      expect(again.findings, isEmpty);
    });

    test('"Remover" a key in the code asks the agent to read it from an '
        'environment variable', () async {
      File('$repo/pag.ts').writeAsStringSync("const k = '$fakeStripe';\n");
      final b = await block();
      await c
          .read(secretActionsProvider)
          .removeInSession(sid, b, b.findings.single);
      expect(await sent(), [
        'Tire o segredo de pag.ts:1 e leia de uma variável de ambiente '
            '(`STRIPE_SECRET`); depois repita o commit.',
      ]);
    });

    test('"Ignorar com justificativa" records the waiver; the finding does '
        'not block again', () async {
      File('$repo/pag.ts').writeAsStringSync("const k = '$fakeStripe';\n");
      final b = await block();
      final f = b.findings.single;
      await c
          .read(secretActionsProvider)
          .ignoreInSession(
            sid,
            b,
            f,
            reason: 'chave de teste revogada',
            byValue: true,
          );
      final rows = await c.read(secretWaiversRepoProvider).active(ws);
      expect(rows.single.reason, 'chave de teste revogada');
      expect(rows.single.origin, 'sessao:$sid');
      expect(rows.single.fingerprint, f.fingerprint);
      final events = await c.read(sessionsRepoProvider).events(sid);
      expect(
        events.lastWhere((e) => e.type == AppEventTypes.secretResolved).json,
        contains('Ignorado: Stripe live key em pag.ts:1 — chave de teste'),
      );
      // The same value in another file passes too (scope "valor").
      File('$repo/outro.ts').writeAsStringSync("x = '$fakeStripe';\n");
      final again = await c
          .read(secretGuardProvider)
          .scan(repo, SecretCheckKind.commit, workspaceId: ws);
      expect(again.findings, isEmpty);
      expect(again.waived, {rows.single.id});
    });
  });

  group('widgets', () {
    const finding = SecretFinding(
      path: 'src/config/pagamento.ts',
      line: 12,
      ruleId: 'stripe',
      ruleName: 'Stripe live key',
      kind: SecretRuleKind.pattern,
      masked: 'sk_live_••••••••(107)',
      fingerprint: 'f',
      maskedLine: "export const stripeKey = 'sk_live_••••••••(107)';",
    );

    testWidgets('"Ignorar" with fewer than 10 characters cannot confirm', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SecretWaiverChoice? got;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => got = await showSecretWaiverDialog(
                context,
                finding: finding,
                workspaceName: 'loja-api',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('secret-waiver-confirm'));
      await tester.enterText(
        find.byKey(const ValueKey('secret-waiver-reason')),
        'curta',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: confirm, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('faltam 5 caracteres'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('secret-waiver-reason')),
        'chave de teste revogada',
      );
      await tester.tap(find.byKey(const ValueKey('secret-waiver-file')));
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(got, (reason: 'chave de teste revogada', byValue: false));
    });

    testWidgets('the card shows the masked findings, the three actions and '
        '"Abrir o arquivo" opens the Código at the line', (tester) async {
      final opened = <(String, String, int)>[];
      final db = memoryDatabase();
      final item = SecretBlockItem(
        block: 'b1',
        action: 'commit',
        command: 'git add -A && git commit -m x',
        findings: [
          finding,
          const SecretFinding(
            path: '.env',
            ruleId: 'env-file',
            ruleName: 'arquivo de ambiente',
            kind: SecretRuleKind.file,
            masked: 'DATABASE_URL, STRIPE_SECRET',
            fingerprint: 'g',
          ),
        ],
      );
      await tester.runAsync(() async {
        await db.customStatement(
          "INSERT INTO workspaces (id, path, name) VALUES (1, '/w', 'w')",
        );
        await SessionsRepo(db).insert(
          id: 's1',
          workspaceId: 1,
          worktreePath: '/w',
          branch: 'main',
          model: 'sonnet',
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseOverride(db),
            openInCodeProvider.overrideWithValue((wt, path, line) async {
              opened.add((wt, path, line));
              return null;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SecretBlockCard(item: item, sessionId: 's1'),
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining(
          'Vigia de segredos bloqueou o commit',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('sk_live_••••••••(107)'), findsOneWidget);
      expect(find.text('DATABASE_URL, STRIPE_SECRET'), findsOneWidget);
      expect(find.text('Remover'), findsNWidgets(2));
      expect(find.text('Ignorar com justificativa…'), findsNWidgets(2));
      expect(find.text('Remover todos'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Stripe live key em pagamento.ts linha 12, valor oculto',
        ),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('secret-open-src/config/pagamento.ts')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(opened, [('/w', 'src/config/pagamento.ts', 12)]);
    });
  });
}
