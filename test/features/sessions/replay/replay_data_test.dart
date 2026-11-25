import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_neutral.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/codex_conversations.dart';
import 'package:promptorium/features/sessions/replay/replay_data.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';

import '../../../core/codex/fake_codex.dart';
import '../../../core/git/git_test_utils.dart';
import '../../../helpers/test_db.dart';
import 'replay_fixtures.dart';

void main() {
  late Directory tmp;
  late String repo;
  late ProviderContainer c;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-replay-result-');
    repo = await createRepo(tmp);
    final db = memoryDatabase();
    final ws = await db
        .into(db.workspaces)
        .insertReturning(
          WorkspacesCompanion.insert(name: 'Replay', path: repo),
        );
    final session = await db
        .into(db.sessions)
        .insertReturning(
          SessionsCompanion.insert(
            id: 's1',
            workspaceId: ws.id,
            worktreePath: repo,
            branch: 'main',
            model: 'sonnet',
          ),
        );
    final base = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
    c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        replaySourceProvider('s1')
            .overrideWith((ref) async => ReplaySource(session, startSha: base)),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await tmp.delete(recursive: true);
  });

  test('R8: result includes command-only tracked edits and untracked generated files', () async {
    File('$repo/a.txt').writeAsStringSync('formatado\n');
    File('$repo/gerado.sql').writeAsStringSync('SELECT 1;\nSELECT 2;\n');
    final files = await c.read(replayResultFilesProvider('s1').future);
    expect(
      files.map((f) => f.path),
      containsAll(['$repo/a.txt', '$repo/gerado.sql']),
    );
    final generated = files.singleWhere((f) => f.path.endsWith('gerado.sql'));
    expect(generated.added, 2);
    final diff = await c.read(
      replayFinalDiffProvider(('s1', '$repo/gerado.sql')).future,
    );
    expect(diff.error, isNull);
    expect(diff.rows.map((r) => r.text), ['SELECT 1;', 'SELECT 2;']);
    expect(diff.rows.every((r) => r.op == DiffOp.add), isTrue);
  });

  test(
    'R8: committed command edits, deletions and binary files remain visible',
    () async {
      File('$repo/a.txt').deleteSync();
      File('$repo/generated.bin').writeAsBytesSync([0, 1, 2]);
      await gitIn(repo, ['add', '.']);
      await gitIn(repo, ['commit', '-qm', 'gerado pelo comando']);
      final files = await c.read(replayResultFilesProvider('s1').future);
      expect(
        files.map((f) => f.path),
        containsAll(['$repo/a.txt', '$repo/generated.bin']),
      );
      expect(
        files.singleWhere((f) => f.path.endsWith('generated.bin')).added,
        -1,
      );
    },
  );

  test(
    'R8: untracked symlinks cannot preview a file outside the worktree',
    () async {
      File('${tmp.path}/outside.txt').writeAsStringSync('fora do projeto');
      Link('$repo/link.txt').createSync('${tmp.path}/outside.txt');
      final diff = await c.read(
        replayFinalDiffProvider(('s1', '$repo/link.txt')).future,
      );
      expect(diff.error, contains('fora da worktree'));
      expect(diff.rows, isEmpty);
    },
  );

  group('SPEC-110 R4 · saída completa pela RPC', () {
    late ProviderContainer c;
    late FakeCodexStore store;
    late List<FakeCodex> servers;
    late Session session;

    setUp(() async {
      store = FakeCodexStore()
        ..threads['thread-1'] = ['t-1']
        ..outputs[('*', 't-1', 'c1')] = 'saída inteira\n';
      servers = [];
      final db = memoryDatabase();
      c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          codexProcessStarterProvider.overrideWithValue((
            exe,
            args, {
            workingDirectory,
            environment,
          }) async {
            // Nenhum diretório do Codex entra na chamada.
            expect(args.join(' '), isNot(contains('.codex/sessions')));
            final f = FakeCodex()..store = store;
            servers.add(f);
            return f;
          }),
        ],
      );
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: tmp.path, name: 'w');
      session = await c
          .read(sessionsRepoProvider)
          .insert(
            id: 'sc',
            workspaceId: ws.id,
            worktreePath: tmp.path,
            branch: 'main',
            model: 'gpt',
            provider: 'codex',
            externalId: 'thread-1',
          );
    });

    tearDown(() => c.dispose());

    List<String> methods() => [
      for (final s in servers)
        for (final m in s.writtenJson) '${m['method']}',
    ];

    test('lê o item por thread/items/list, sem thread nem turno, e fecha o '
        'App Server', () async {
      final out = await c
          .read(codexConversationsProvider)
          .itemOutput(session, turnId: 't-1', itemId: 'c1');
      expect(out, 'saída inteira\n');
      expect(methods(), ['initialize', 'initialized', 'thread/items/list']);
      expect(servers.single.writtenJson.last['params'], {
        'threadId': 'thread-1',
        'turnId': 't-1',
        'limit': 100,
      });
      expect(servers.single.ended, isTrue);
    });

    test('o turno saiu da conversa: procura na cópia', () async {
      store.threads['thread-1'] = [];
      store.threads['copia-1'] = ['t-1'];
      final out = await c
          .read(codexConversationsProvider)
          .itemOutput(
            session,
            turnId: 't-1',
            itemId: 'c1',
            copies: ['copia-1'],
          );
      expect(out, 'saída inteira\n');
      expect(store.calls, ['items thread-1 t-1', 'items copia-1 t-1']);
    });

    test('sem o item, e com o App Server mudo: o motivo em palavras', () async {
      final conv = c.read(codexConversationsProvider);
      await expectLater(
        conv.itemOutput(session, turnId: 't-1', itemId: 'nada'),
        throwsA(predicate((e) => '$e'.contains('não guardou a saída'))),
      );
      store.fail['thread/items/list'] = 'no rollout found for thread id x';
      await expectLater(
        conv.itemOutput(session, turnId: 't-1', itemId: 'c1'),
        throwsA(predicate((e) => '$e'.contains('não achou a conversa'))),
      );
    });

    test('só quando falta: saída cortada ou não guardada, no Codex', () {
      CommandEvent cmd(String? output) => ClaudeEvent.fromJson(
        codexCommand({
          'id': 'c1',
          'command': 'x',
          'status': 'completed',
          'aggregatedOutput': output,
          'exitCode': 0,
        }),
      ) as CommandEvent;
      expect(replayOutputMissing(cmd('ok\n')), isFalse);
      expect(replayOutputMissing(cmd(null)), isTrue);
      expect(replayOutputMissing(cmd('l\n' * 3000)), isTrue);
    });

    test('sem o Codex instalado, ou sem turno, o motivo do botão', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      b.command('c1', 'x', const []);
      final step = replaySteps(b.items).last;
      const ready = ProviderAvailability(ProviderStatus.ready, 'ok');
      const missing = ProviderAvailability(ProviderStatus.missing, '…');
      expect(replayFetchBlock(step, ready), isNull);
      expect(replayFetchBlock(step, missing), contains('não está instalado'));
      final old = TimelineBuilder()..command('c1', 'x', const []);
      expect(
        replayFetchBlock(replaySteps(old.items).last, ready),
        contains('não foi identificado'),
      );
    });
  });
}
