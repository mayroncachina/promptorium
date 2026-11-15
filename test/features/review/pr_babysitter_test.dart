import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';

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
}
