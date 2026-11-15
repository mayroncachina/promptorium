import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/ci_fixer.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/pr_import.dart';

import '../../core/git/git_test_utils.dart';
import '../sessions/session_test_utils.dart';
import 'ci_fixer_test.dart';

void main() {
  group('SPEC-073 R1, R9 · checks com detalhe', () {
    final view = jsonEncode({
      'state': 'OPEN',
      'headRefOid': 'a1b2c3d4e5f6',
      'statusCheckRollup': [
        {
          '__typename': 'CheckRun',
          'name': 'test (ubuntu)',
          'status': 'COMPLETED',
          'conclusion': 'FAILURE',
          'workflowName': 'CI',
          'detailsUrl':
              'https://github.com/o/r/actions/runs/9182734/job/50112233',
        },
        {
          '__typename': 'CheckRun',
          'name': 'build',
          'status': 'IN_PROGRESS',
          'conclusion': '',
          'workflowName': 'CI',
          'detailsUrl': 'https://github.com/o/r/actions/runs/9182734/job/2',
        },
        {
          '__typename': 'StatusContext',
          'context': 'Vercel · Preview',
          'state': 'FAILURE',
          'targetUrl': 'https://vercel.com/o/r/abc',
        },
        {
          '__typename': 'CheckRun',
          'name': 'CodeQL',
          'status': 'COMPLETED',
          'conclusion': 'FAILURE',
          'workflowName': '',
          'detailsUrl': 'https://github.com/o/r/runs/77',
        },
      ],
    });

    test('run and job from the detailsUrl; headRefOid', () {
      final s = parsePrView(view)!;
      expect(s.headSha, 'a1b2c3d4e5f6');
      final test = s.checks.first;
      expect(test.name, 'test (ubuntu)');
      expect(test.workflow, 'CI');
      expect(test.runId, 9182734);
      expect(test.jobId, 50112233);
      expect(test.hasLog, isTrue);
      expect(test.failed, isTrue);
      expect(s.checks[1].state, 'IN_PROGRESS');
      expect(s.checks[1].running, isTrue);
      expect(s.ci, CiState.failed);
      expect(prViewFields, contains('headRefOid'));
    });

    test('a StatusContext or another app has no log', () {
      final s = parsePrView(view)!;
      final vercel = s.checks[2];
      expect(vercel.name, 'Vercel · Preview');
      expect(vercel.url, 'https://vercel.com/o/r/abc');
      expect(vercel.hasLog, isFalse);
      expect(vercel.failed, isTrue);
      expect(s.checks[3].hasLog, isFalse);
      expect(s.failedChecks.map((c) => c.name), [
        'test (ubuntu)',
        'Vercel · Preview',
        'CodeQL',
      ]);
    });

    test('actionsRunOf', () {
      expect(actionsRunOf('https://github.com/o/r/actions/runs/12/jobs/34'), (
        run: 12,
        job: 34,
      ));
      expect(actionsRunOf('https://github.com/o/r/actions/runs/12'), (
        run: 12,
        job: null,
      ));
      expect(actionsRunOf('https://vercel.com/x'), isNull);
      expect(actionsRunOf(null), isNull);
    });
  });

  group('SPEC-073 R11, R12 · corrigir sozinho', () {
    late Directory tmp;
    late String repo;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-ci-auto-');
      repo = await createRepo(tmp);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Future<Env> auto({bool on = true}) async {
      final e = await setUpCiPr(tmp, repo);
      if (on) {
        Directory('$repo/.promptorium').createSync();
        File('$repo/.promptorium/config.yml')
            .writeAsStringSync('review:\n  corrigir-ci: automatico\n');
      }
      return e;
    }

    PrBabysitter sitter(Env e) => e.c.read(prBabysitterProvider.notifier);
    List<String> titles(Env e) => e.notifier.shown.map((n) => n.$1).toList();

    test('off: nothing goes to the agent', () async {
      final e = await auto(on: false);
      await sitter(e).toggle(e.id);
      await settle();
      expect(e.ciMessages, isEmpty);
    });

    test('not watched: nothing goes to the agent', () async {
      final w = await auto();
      await sitter(w).check(w.id);
      await settle();
      expect(w.ciMessages, isEmpty);
    });

    test('waits for every check to finish, then once per red commit', () async {
      final e = await auto();
      e.cmds.prView = jsonEncode({
        ...jsonDecode(prJson()) as Map,
        'statusCheckRollup': [
          ...(jsonDecode(prJson()) as Map)['statusCheckRollup'] as List,
          {
            'name': 'e2e',
            'status': 'IN_PROGRESS',
            'conclusion': '',
            'detailsUrl': 'https://github.com/o/r/actions/runs/13/job/9',
          },
        ],
      });
      await sitter(e).toggle(e.id);
      await settle();
      expect(e.ciMessages, isEmpty);
      e.cmds.prView = prJson();
      await sitter(e).check(e.id);
      await settle();
      expect(e.ciMessages, hasLength(1));
      expect(e.st!.auto, isTrue);
      expect(e.fixer.record(e.id).auto, isTrue);
      expect(titles(e), contains('Corrigindo o CI de Cupom sozinho'));
      // The same commit never gets a second automatic fix.
      e.fixer.dismiss(e.id);
      await sitter(e).check(e.id);
      await settle();
      expect(e.ciMessages, hasLength(1));
    });

    test('the fix\'s commit red stops it; green gives it back', () async {
      final e = await auto();
      await sitter(e).toggle(e.id);
      await settle();
      expect(e.ciMessages, hasLength(1));
      final sha = await e.commit('fix.txt');
      e.cli.last.emit(answer('Corrigido.'));
      await until(() async => e.st?.phase == CiFixPhase.running);
      // Red again on the fix's commit: stop, warn, no second fix.
      e.cmds.prView = prJson(sha: sha);
      await sitter(e).check(e.id);
      await settle();
      expect(e.st!.phase, CiFixPhase.stopped);
      expect(
        titles(e),
        contains('O CI continua vermelho depois da correção automática'),
      );
      expect(e.fixer.record(e.id).stopped, isTrue);
      await sitter(e).check(e.id);
      await settle();
      expect(e.ciMessages, hasLength(1));
      // A new red commit while stopped: still nothing.
      e.cmds.prView = prJson(sha: 'outro1');
      await sitter(e).check(e.id);
      await settle();
      expect(e.ciMessages, hasLength(1));
      // Green: the automatic is back for the next red commit.
      e.cmds.prView = prJson(sha: 'verde1', green: true);
      await sitter(e).check(e.id);
      await settle();
      expect(e.fixer.record(e.id).stopped, isFalse);
      e.cmds.prView = prJson(sha: 'vermelho2');
      await sitter(e).check(e.id);
      await settle();
      expect(e.ciMessages, hasLength(2));
    });

    test('without a commit the automatic stops too', () async {
      final e = await auto();
      await sitter(e).toggle(e.id);
      await settle();
      e.cli.last.emit(answer('Não achei.'));
      await until(() async => e.st?.phase == CiFixPhase.noCommit);
      expect(e.fixer.record(e.id).stopped, isTrue);
    });

    test('an intermittent log runs again once before the fix', () async {
      final e = await auto();
      e.cmds.logs[11] = logRow(
        'test (ubuntu)',
        'Run',
        'npm ERR! request failed, reason: read ECONNRESET',
      );
      await sitter(e).toggle(e.id);
      await settle();
      expect(e.ciMessages, isEmpty);
      expect(
        e.cmds.calls.where((x) => x.$2.take(2).join(' ') == 'run rerun'),
        hasLength(1),
      );
      expect(titles(e), contains('Rodando de novo o CI de Cupom sozinho'));
      // Still red after the rerun: now the fix goes.
      e.fixer.dismiss(e.id);
      await sitter(e).check(e.id);
      await settle();
      expect(e.ciMessages, hasLength(1));
      expect(
        e.cmds.calls.where((x) => x.$2.take(2).join(' ') == 'run rerun'),
        hasLength(1),
      );
    });

    test(
      'a PR brought without write permission has no automatic (R10)',
      () async {
        final e = await auto();
        await e.c
            .read(appSettingsProvider.notifier)
            .set(
              ImportedPr.key(e.id),
              const ImportedPr(
                number: 7,
                url: 'https://github.com/o/r/pull/7',
              ).encode(),
            );
        await sitter(e).toggle(e.id);
        await settle();
        expect(e.ciMessages, isEmpty);
      },
    );
  });
}
