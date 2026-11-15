import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/review/ci_fixer.dart';
import 'package:promptorium/features/review/ci_log.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/widgets/ci_panel.dart';

final _status = parsePrView(
  jsonEncode({
    'state': 'OPEN',
    'headRefOid': 'a1b2c3d4',
    'statusCheckRollup': [
      {
        'name': 'test (ubuntu)',
        'workflowName': 'CI',
        'conclusion': 'FAILURE',
        'detailsUrl': 'https://github.com/o/r/actions/runs/9/job/1',
      },
      {'context': 'Vercel · Preview', 'state': 'FAILURE', 'targetUrl': 'x'},
      {'name': 'build', 'conclusion': 'SUCCESS'},
    ],
  }),
)!;

class _Fixer extends CiFixer {
  _Fixer(this.flaky, this.states);
  final bool flaky;
  final Map<String, CiFixState> states;

  @override
  Map<String, CiFixState> build() => states;

  @override
  Future<CiFailure> failure(String sessionId, PrStatus status) async =>
      CiFailure(
        sha: status.headSha,
        total: status.checks.length,
        failed: status.failedChecks,
        excerpt: ciLogExcerpt(
          [
            'test (ubuntu)\tRun flutter test\t2026-11-15T10:00:00Z Expected: <90.0>',
            if (flaky) 'test (ubuntu)\tRun flutter test\tread ECONNRESET',
          ].join('\n'),
        ),
      );
}

Future<void> pump(
  WidgetTester tester, {
  bool flaky = false,
  Map<String, CiFixState> states = const {},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [ciFixerProvider.overrideWith(() => _Fixer(flaky, states))],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: CiPanel(sessionId: 's1', status: _status),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('SPEC-073 R2: the failed checks with the step, the excerpt '
      'and the check without log', (tester) async {
    await pump(tester);
    expect(find.text('CI falhou no commit a1b2c3d'), findsOneWidget);
    expect(find.textContaining('passo "Run flutter test"'), findsOneWidget);
    expect(
      find.textContaining('sem log disponível · não vai para o agente'),
      findsOneWidget,
    );
    expect(find.text('Abrir check'), findsOneWidget);
    expect(find.textContaining('1 check passou: build'), findsOneWidget);
    expect(find.byKey(const ValueKey('ci-flaky')), findsNothing);
    await tester.tap(find.text('test (ubuntu)'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ci-excerpt-test (ubuntu)')),
      findsOneWidget,
    );
  });

  testWidgets('SPEC-073 R8: an intermittent log says why', (tester) async {
    await pump(tester, flaky: true);
    expect(
      find.text('Parece intermitente: conexão reiniciada (ECONNRESET)'),
      findsOneWidget,
    );
  });

  testWidgets('SPEC-073 R5: queued, with Cancelar; fixing turns the button '
      'into "Corrigindo CI…"', (tester) async {
    await pump(
      tester,
      states: {
        's1': CiFixState(phase: CiFixPhase.queued, since: DateTime(2026)),
      },
    );
    expect(
      find.textContaining('Na fila: a sessão está ocupada'),
      findsOneWidget,
    );
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Corrigindo CI…'), findsOneWidget);
  });
}
