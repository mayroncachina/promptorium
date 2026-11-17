import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/secrets/secret_blocks.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/secret_block_card.dart';

import '../../features/sessions/session_test_utils.dart';
import '../../helpers/test_db.dart';
import '../git/git_test_utils.dart';
import 'fake_secrets.dart';

/// SPEC-085 R8: the whole flow with sentinel secrets; the value never shows
/// up in the hook log, the reason sent to the agent, `session_events`, the
/// database, the notifications, `debugPrint` or the rendered timeline.
void main() {
  // Fake, built at run time; "SENTINELA" makes a leak easy to spot.
  final stripe = [
    'sk',
    'live',
    'SENTINELA${fakeChars(24, seed: 70)}',
  ].join('_');
  const password = 'S3nh4SENTINELA';
  final pieces = [stripe, stripe.substring(8), password, 'SENTINELA'];

  void expectClean(String where, String text) {
    for (final p in pieces) {
      expect(text.contains(p), isFalse, reason: '$where contém $p');
    }
  }

  test('nothing leaks through the hook, the session and the database', () async {
    if (!await pythonAvailable()) return;
    final tmp = Directory.systemTemp.createTempSync('promptorium-leak-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);
    final printed = <String>[];
    final oldPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
    addTearDown(() => debugPrint = oldPrint);

    final hooks = ManagedHooks(runBase: '${tmp.path}/run');
    final cli = FakeCli();
    final db = memoryDatabase();
    final c = sessionContainer([
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      managedHooksProvider.overrideWithValue(hooks),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(
        workspace: ws,
        title: 'SPEC-031 · Stripe',
        prompt: 'oi',
        useWorktree: false,
      ),
    );
    final cfg = jsonDecode(
      File('${hooks.dirOf(id)}/hooks-config.json').readAsStringSync(),
    ) as Map;
    expect(cfg['segredos'], hooks.secretsOf(id));

    // The agent wrote the key and a .env, then tries to commit.
    Directory('$repo/src/config').createSync(recursive: true);
    File('$repo/src/config/pagamento.ts')
        .writeAsStringSync("export const stripeKey = '$stripe';\n");
    File('$repo/.env').writeAsStringSync(
      'DATABASE_URL=postgres://app:$password@db/loja\nSTRIPE_SECRET=$stripe\n',
    );
    const command = 'git add -A && git commit -m "SPEC-031 R2: integra Stripe"';
    final p = await Process.start('python3', [
      '${hooks.dirOf(id)}/promptorium_hook.py',
    ], workingDirectory: repo);
    p.stdin.add(
      utf8.encode(
        jsonEncode({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': command},
          'cwd': repo,
        }),
      ),
    );
    await p.stdin.close();
    final reason = await p.stdout.transform(utf8.decoder).join();
    await p.exitCode;
    expect(reason, contains('"deny"'));
    expectClean('motivo enviado ao agente', reason);
    expectClean('log de hooks', File(hooks.logOf(id)).readAsStringSync());

    // The tool result makes the app read the log.
    cli.last.emit(
      jsonEncode({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 't1',
              'content': 'PreToolUse:Bash hook error: bloqueado',
              'is_error': true,
            },
          ],
        },
        'session_id': id,
      }),
    );
    await until(
      () async =>
          (await c.read(sessionsRepoProvider).events(id))
              .any((e) => e.type == AppEventTypes.secrets),
    );
    expect(c.read(secretBlocksProvider)[sessionSecretKey(id)], isNotNull);

    final events = await c.read(sessionsRepoProvider).events(id);
    expectClean('session_events', [for (final e in events) e.json].join());
    final block = events.firstWhere((e) => e.type == AppEventTypes.secrets);
    expect(block.json, contains('sk_live_••••••••'));

    // Every table of the database.
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final dump = StringBuffer();
    for (final t in tables) {
      final name = t.read<String>('name');
      for (final r in await db.customSelect('SELECT * FROM "$name"').get()) {
        dump.writeln(r.data.values.join('|'));
      }
    }
    expectClean('banco', dump.toString());
    expectClean('debugPrint', printed.join('\n'));
    expectClean(
      'secrets.json do hook',
      File(hooks.secretsOf(id)).readAsStringSync(),
    );

    // The timeline as rendered (the item is rebuilt from the stored row).
    final t = Timeline()..applyStored(block.json);
    final item = t.items.whereType<SecretBlockItem>().single;
    expect(item.findings, hasLength(2));
    _rendered = (item, id);
  });

  testWidgets('nothing leaks in the rendered card', (tester) async {
    final r = _rendered;
    if (r == null) return; // no python3
    final (item, id) = r;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseOverride(memoryDatabase())],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SecretBlockCard(item: item, sessionId: id),
            ),
          ),
        ),
      ),
    );
    final texts = [
      for (final w in tester.widgetList<RichText>(find.byType(RichText)))
        w.text.toPlainText(),
    ].join('\n');
    expect(texts, contains('Vigia de segredos bloqueou o commit'));
    expect(texts, contains('sk_live_••••••••'));
    expect(texts, contains('DATABASE_URL, STRIPE_SECRET'));
    expectClean('timeline renderizada', texts);
    final semantics = tester.getSemantics(find.byType(SecretBlockCard));
    expectClean('leitor de tela', semantics.toStringDeep());
  });
}

(SecretBlockItem, String)? _rendered;
