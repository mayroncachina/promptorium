import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/features/splash/splash_screen.dart';
import 'package:promptorium/features/splash/startup_controller.dart';
import 'package:promptorium/ui/shell/footer_stats.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

Future<ProcessResult> missing(String exe, List<String> args) async =>
    throw ProcessException(exe, args, 'No such file or directory', 2);

Future<ProcessResult> fakeClaude(String exe, List<String> args) async =>
    ProcessResult(1, 0, '2.1.300 (Claude Code)\n', '');

ProviderContainer container(ProcessRunner runner, List<String> candidates) {
  final c = ProviderContainer(
    overrides: [
      processRunnerProvider.overrideWithValue(runner),
      claudeExecutableCandidatesProvider.overrideWithValue(candidates),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('StartupController', () {
    test(
      'missing executable reports a clear error on the first step',
      () async {
        final c = container(missing, ['/nonexistent/claude']);
        await c.read(startupControllerProvider.notifier).run();

        final s = c.read(startupControllerProvider);
        expect(s.status, StartupStatus.failed);
        expect(s.completed, 0);
        expect(s.label, 'Claude Code CLI não encontrado');
        expect(s.error?.hint, contains('PATH'));
        expect(s.error?.details, contains('No such file'));
        expect(c.read(footerStatsProvider).cliStatus, CliStatus.notFound);
      },
    );

    test('real Process.run on a nonexistent path also fails cleanly', () async {
      final c = ProviderContainer(
        overrides: [
          claudeExecutableCandidatesProvider.overrideWithValue([
            '/nonexistent/promptorium-test/claude',
          ]),
        ],
      );
      addTearDown(c.dispose);
      await c.read(startupControllerProvider.notifier).run();
      expect(c.read(startupControllerProvider).status, StartupStatus.failed);
    });

    test('non-zero exit code is treated as not found', () async {
      final c = container((e, a) async => ProcessResult(1, 127, '', 'boom'), [
        'claude',
      ]);
      await c.read(startupControllerProvider.notifier).run();
      final s = c.read(startupControllerProvider);
      expect(s.status, StartupStatus.failed);
      expect(s.error?.details, contains('127'));
    });

    test('falls back to the next candidate and runs every step', () async {
      final tried = <String>[];
      final c = container((exe, args) {
        tried.add(exe);
        return exe == 'claude' ? missing(exe, args) : fakeClaude(exe, args);
      }, ['claude', '/home/x/.local/bin/claude']);

      await c.read(startupControllerProvider.notifier).run();

      final s = c.read(startupControllerProvider);
      expect(tried, ['claude', '/home/x/.local/bin/claude']);
      expect(s.status, StartupStatus.done);
      expect(s.completed, s.total);
      expect(s.total, 5);
      expect(s.progress, 1);
      expect(s.claude?.version, '2.1.300');
      expect(s.claude?.executable, '/home/x/.local/bin/claude');
      final footer = c.read(footerStatsProvider);
      expect(footer.cliStatus, CliStatus.connected);
      expect(footer.claudeVersion, '2.1.300');
    });

    test('retry after failure succeeds once the CLI appears', () async {
      var installed = false;
      final c = container(
        (e, a) => installed ? fakeClaude(e, a) : missing(e, a),
        ['claude'],
      );
      final ctrl = c.read(startupControllerProvider.notifier);
      await ctrl.run();
      expect(c.read(startupControllerProvider).status, StartupStatus.failed);
      installed = true;
      await ctrl.run();
      expect(c.read(startupControllerProvider).status, StartupStatus.done);
    });
  });

  group('SplashScreen', () {
    Widget app(ProcessRunner runner, VoidCallback onFinished) => ProviderScope(
      overrides: [
        processRunnerProvider.overrideWithValue(runner),
        claudeExecutableCandidatesProvider.overrideWithValue(['claude']),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: SplashScreen(onFinished: onFinished),
      ),
    );

    testWidgets('shows the error and a retry button when the CLI is missing', (
      tester,
    ) async {
      var finished = false;
      await tester.pumpWidget(app(missing, () => finished = true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Claude Code CLI não encontrado'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(finished, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('finishes after the minimum duration when startup succeeds', (
      tester,
    ) async {
      var finished = false;
      await tester.pumpWidget(app(fakeClaude, () => finished = true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Pronto'), findsOneWidget);
      expect(find.text('Claude Code 2.1.300'), findsOneWidget);
      expect(finished, isFalse); // still within the 2.6 s minimum

      await tester.pump(const Duration(seconds: 3));
      expect(finished, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
