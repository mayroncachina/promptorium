import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/secrets/secret_guard.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/secrets/secret_blocks.dart';
import 'package:promptorium/features/secrets/secret_flow.dart';

import '../../features/sessions/session_test_utils.dart';
import '../../helpers/test_db.dart';
import '../git/git_test_utils.dart';
import 'fake_secrets.dart';

/// SPEC-085 R5, R6, R14: the guard of the app's and the Código's commits.
void main() {
  late Directory tmp;
  late String repo;
  late ProviderContainer c;
  late int ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-guard-');
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
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  SecretGuard guard() => c.read(secretGuardProvider);

  Future<void> check(
    SecretOrigin origin, {
    SecretCheckKind kind = SecretCheckKind.commit,
  }) => guard().check(repo, kind, workspaceId: ws, origin: origin);

  test('the app\'s commit with a .env throws SecretsFound and waits as '
      '"Segredo encontrado"; a clean one removes the request', () async {
    File('$repo/.env').writeAsStringSync('A=1\n');
    await expectLater(check(SecretOrigin.app), throwsA(isA<SecretsFound>()));
    final p = c.read(secretBlocksProvider)[appSecretKey(repo)]!;
    expect(p.worktree, repo);
    expect(p.detail, 'commit bloqueado · 1 achado');
    File('$repo/.env').deleteSync();
    await check(SecretOrigin.app);
    expect(c.read(secretBlocksProvider), isEmpty);
  });

  test('the switches of each origin and the main one (R14)', () async {
    File('$repo/k.ts').writeAsStringSync("k = '$fakeStripe'\n");
    final s = c.read(appSettingsProvider.notifier);
    await s.set(SecretSettingKeys.app, '0');
    await check(SecretOrigin.app);
    await expectLater(check(SecretOrigin.manual), throwsA(isA<SecretsFound>()));
    await s.set(SecretSettingKeys.manual, '0');
    await check(SecretOrigin.manual);
    await s.set(SecretSettingKeys.enabled, '0');
    await s.set(SecretSettingKeys.app, '1');
    await check(SecretOrigin.app);
  });

  test('a partial index checks only what is staged (manual commit)', () async {
    File('$repo/k.ts').writeAsStringSync("k = '$fakeStripe'\n");
    File('$repo/ok.txt').writeAsStringSync('ok\n');
    await gitIn(repo, ['add', 'ok.txt']);
    await check(SecretOrigin.manual, kind: SecretCheckKind.staged);
    await gitIn(repo, ['add', 'k.ts']);
    await expectLater(
      check(SecretOrigin.manual, kind: SecretCheckKind.staged),
      throwsA(isA<SecretsFound>()),
    );
  });

  test(
    'a staged secret is blocked after the working file is cleaned',
    () async {
      final f = File('$repo/k.ts');
      f.writeAsStringSync("k = '$fakeStripe'\n");
      await gitIn(repo, ['add', 'k.ts']);
      f.writeAsStringSync('k = null\n');
      await expectLater(check(SecretOrigin.app), throwsA(isA<SecretsFound>()));
    },
  );

  test('the push checks the commits not on a remote yet', () async {
    final bare = '${tmp.path}/remote.git';
    await Process.run('git', ['init', '-q', '--bare', bare]);
    await gitIn(repo, ['remote', 'add', 'origin', bare]);
    await gitIn(repo, ['push', '-q', '-u', 'origin', 'main']);
    await check(SecretOrigin.app, kind: SecretCheckKind.push);
    File('$repo/k.ts').writeAsStringSync("k = '$fakeGithub'\n");
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-qm', 'k']);
    await expectLater(
      check(SecretOrigin.app, kind: SecretCheckKind.push),
      throwsA(
        isA<SecretsFound>().having((e) => e.kind, 'kind', SecretCheckKind.push),
      ),
    );
  });

  testWidgets('the Código commit opens the window; "Remover e commitar" '
      'takes the .env out and the commit goes on (R6)', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      File('$repo/.env.local').writeAsStringSync('JWT_SECRET=x\n');
    });
    bool? result;
    String? error;
    late WidgetRef wref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                wref = ref;
                return TextButton(
                  onPressed: () async {
                    try {
                      result = await withSecretGuard(context, wref, () async {
                        await wref
                            .read(secretGuardProvider)
                            .check(
                              repo,
                              SecretCheckKind.commit,
                              workspaceId: ws,
                              origin: SecretOrigin.manual,
                            );
                        return true;
                      }, manual: true);
                    } catch (e, st) {
                      error = '$e\n$st';
                    }
                  },
                  child: const Text('Commit'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Commit'));
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.byType(Dialog).evaluate().isNotEmpty || error != null) break;
      }
    });
    await tester.pumpAndSettle();
    expect(error, isNull);
    expect(
      find.text('Este commit leva um arquivo de ambiente'),
      findsOneWidget,
    );
    expect(find.text('JWT_SECRET'), findsOneWidget);
    expect(find.text('Commitar mesmo assim…'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(
        find.byKey(const ValueKey('secret-dialog-remove-commit')),
      );
      for (var i = 0; i < 50 && result == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    expect(result, isTrue);
    expect(
      File('$repo/.gitignore').readAsStringSync(),
      contains('/.env.local'),
    );
    expect(File('$repo/.env.local').existsSync(), isTrue);
  });
}
