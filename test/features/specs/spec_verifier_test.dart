import 'dart:io';
import 'dart:convert';

import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/claude/readonly_run.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/spec_verifier.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../../core/codex/fake_codex.dart';

const specText = '''---
id: SPEC-001
status: rascunho
---
# Existente
## Requisitos
- R1 · mostrar uma linha
## Critérios de aceite
- [ ] [R1] a linha aparece
''';

Map<String, dynamic> answer({
  String status = 'implementado',
  String path = 'a.txt',
  String quote = 'linha 1',
}) => {
  'items': [
    for (final id in ['R1', 'A1'])
      {
        'id': id,
        'status': status,
        'explanation': 'O comportamento está presente.',
        'evidence': [
          {'path': path, 'quote': quote, 'kind': 'codigo'},
        ],
      },
  ],
};

void main() {
  late Directory tmp;
  late AppDatabase db;
  late Workspace ws;
  late Spec spec;
  late ProviderContainer c;
  VerificationAgent agent = (ws, prompt, provider, token) async => answer();

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('spec-verifier-');
    final root = await createRepo(tmp);
    db = memoryDatabase();
    ws = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: root, name: 'ws'));
    agent = (ws, prompt, provider, token) async => answer();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        activeWorkspaceProvider.overrideWithValue(ws),
        verificationAgentProvider.overrideWithValue(
          (ws, prompt, provider, token) => agent(ws, prompt, provider, token),
        ),
      ],
    );
    Directory('$root/specs').createSync();
    File('$root/specs/SPEC-001.md').writeAsStringSync(specText);
    await c.read(specServiceProvider).sync(ws);
    spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-001'))!;
  });
  tearDown(() async {
    c.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('effective provider receives all requirements and criteria; complete report concludes both states', () async {
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'codex');
    agent = (ws, prompt, provider, token) async {
      expect(provider, 'codex');
      expect(prompt, contains('"A1"'));
      expect(prompt, contains('"R1"'));
      return answer();
    };
    final report = await c
        .read(specVerifierProvider)
        .verify(ws, spec, VerificationCancellation());
    expect(report['complete'], isTrue);
    final current = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect(current.status, SpecStatus.done);
    expect(current.stage, SpecStage.done);
    final text = (await c.read(specServiceProvider).read(ws, current))!;
    expect(text, specText.replaceFirst('rascunho', 'concluida'));
    expect(report['completedSpecHash'], specDigest(text));
    expect(await c.read(specVerifierProvider).report(ws, current), isNotNull);
    expect(await db.select(db.sessions).get(), isEmpty);
    expect(await db.select(db.specSteps).get(), isEmpty);
  });

  test('partial implementation persists evidence without concluding', () async {
    agent = (ws, prompt, provider, token) async => answer(status: 'parcial');
    final report = await c
        .read(specVerifierProvider)
        .verify(ws, spec, VerificationCancellation());
    expect(report['complete'], isFalse);
    expect(
      (await c.read(specsRepoProvider).getById(spec.id))!.stage,
      SpecStage.backlog,
    );
    expect(await c.read(specServiceProvider).read(ws, spec), specText);
  });

  test(
    'invented quotes or evidence in the spec itself cannot conclude',
    () async {
      for (final data in [
        answer(quote: 'não existe'),
        answer(path: spec.path, quote: 'mostrar uma linha'),
      ]) {
        agent = (ws, prompt, provider, token) async => data;
        final report = await c
            .read(specVerifierProvider)
            .verify(ws, spec, VerificationCancellation());
        expect(report['complete'], isFalse);
        expect((report['items'] as List).first['status'], 'nao-verificavel');
      }
    },
  );

  test('manual criterion needs a manual record, not code evidence', () async {
    File('${ws.path}/${spec.path}').writeAsStringSync(
      specText.replaceFirst('a linha aparece', 'validar manual no app'),
    );
    final report = await c
        .read(specVerifierProvider)
        .verify(ws, spec, VerificationCancellation());
    expect(report['complete'], isFalse);
  });

  test(
    'missing and duplicate items reject the response without status changes',
    () async {
      for (final items in [
        [],
        [answer()['items'][0], answer()['items'][0]],
      ]) {
        agent = (ws, prompt, provider, token) async => {'items': items};
        await expectLater(
          c
              .read(specVerifierProvider)
              .verify(ws, spec, VerificationCancellation()),
          throwsA(isA<SpecException>()),
        );
        expect(
          (await c.read(specsRepoProvider).getById(spec.id))!.stage,
          SpecStage.backlog,
        );
      }
    },
  );

  test(
    'a dirty edit during analysis invalidates even when HEAD is unchanged',
    () async {
      agent = (ws, prompt, provider, token) async {
        File('${ws.path}/a.txt').writeAsStringSync('mudou\n');
        return answer();
      };
      await expectLater(
        c
            .read(specVerifierProvider)
            .verify(ws, spec, VerificationCancellation()),
        throwsA(isA<SpecException>()),
      );
      expect(await c.read(specVerifierProvider).report(ws, spec), isNull);
      expect(await c.read(specServiceProvider).read(ws, spec), specText);
    },
  );

  test(
    'cancelling and starting an execution both prevent publication',
    () async {
      final token = VerificationCancellation();
      agent = (ws, prompt, provider, cancellation) async {
        cancellation.cancel();
        return answer();
      };
      await expectLater(
        c.read(specVerifierProvider).verify(ws, spec, token),
        throwsA(isA<SpecException>()),
      );
      agent = (ws, prompt, provider, cancellation) async {
        await c.read(specsRepoProvider).setStage(spec.id, SpecStage.running);
        return answer();
      };
      await expectLater(
        c
            .read(specVerifierProvider)
            .verify(ws, spec, VerificationCancellation()),
        throwsA(isA<SpecException>()),
      );
      expect(await c.read(specVerifierProvider).report(ws, spec), isNull);
    },
  );

  test(
    'fingerprint includes untracked files and ignores verification reports',
    () async {
      final before = await repositoryFingerprint(ws);
      final report = SpecVerifier.reportFile(ws, spec);
      report.parent.createSync(recursive: true);
      report.writeAsStringSync('{}');
      expect(await repositoryFingerprint(ws), before);
      File('${ws.path}/new.txt').writeAsStringSync('new');
      expect(await repositoryFingerprint(ws), isNot(before));
    },
  );
  test('real verification runner starts Codex read-only with structured output and supports cancellation', () async {
    final servers = <FakeCodex>[];
    final runner = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final server = FakeCodex();
          servers.add(server);
          return server;
        }),
      ],
    );
    addTearDown(runner.dispose);
    await runner.read(appSettingsProvider.notifier).load();
    Future<FakeCodex> started(int index) async {
      for (var i = 0; i < 500; i++) {
        if (servers.length > index &&
            servers[index].writtenJson.any(
              (r) => r['method'] == 'turn/start',
            )) {
          return servers[index];
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      fail('Codex did not start');
    }

    final result = runner.read(verificationAgentProvider)(
      ws,
      'Verifique',
      'codex',
      VerificationCancellation(),
    );
    final server = await started(0);
    final thread = server.writtenJson.singleWhere(
      (r) => r['method'] == 'thread/start',
    );
    expect(thread['params']['sandbox'], 'read-only');
    final turn = server.writtenJson.singleWhere(
      (r) => r['method'] == 'turn/start',
    );
    expect(turn['params']['outputSchema'], verificationSchema);
    server.emit(
      jsonEncode({
        'method': 'item/completed',
        'params': {
          'threadId': server.threadId,
          'item': {
            'id': 'answer',
            'type': 'agentMessage',
            'text': jsonEncode(answer()),
          },
        },
      }),
    );
    server.completeTurn();
    expect(await result, answer());
    final token = VerificationCancellation();
    final cancelled = runner.read(verificationAgentProvider)(
      ws,
      'Verifique',
      'codex',
      token,
    );
    final rejected = expectLater(cancelled, throwsA(isA<PlannerException>()));
    await started(1);
    token.cancel();
    await rejected;
  });
}
