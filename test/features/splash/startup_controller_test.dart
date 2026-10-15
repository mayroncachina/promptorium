import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:drift/native.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/splash/splash_screen.dart';
import 'package:promptorium/features/splash/startup_controller.dart';
import 'package:promptorium/ui/shell/footer_stats.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

Future<ProcessResult> missing(String exe, List<String> args) async =>
    throw ProcessException(exe, args, 'No such file or directory', 2);

Future<ProcessResult> fakeClaude(String exe, List<String> args) async =>
    ProcessResult(1, 0, '2.1.300 (Claude Code)\n', '');

ProviderContainer container(
  ProcessRunner runner,
  List<String> candidates, {
  AppDatabase? db,
}) {
  final c = ProviderContainer(
    overrides: [
      databaseOverride(db ?? memoryDatabase()),
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
          databaseOverride(memoryDatabase()),
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
      expect(s.total, 6);
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

  group('database steps', () {
    test('opens the database and loads app_settings', () async {
      final db = memoryDatabase();
      await AppSettingsRepo(db).set(AppSettingKeys.lastSection, 'mcp');
      final c = container(fakeClaude, ['claude'], db: db);
      await c.read(startupControllerProvider.notifier).run();

      expect(c.read(startupControllerProvider).status, StartupStatus.done);
      expect(c.read(appSettingsProvider)[AppSettingKeys.lastSection], 'mcp');
    });

    test('a stale active workspace falls back to the first one', () async {
      final db = memoryDatabase();
      final ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: '/repo/a', name: 'a'),
          );
      await AppSettingsRepo(db).set(AppSettingKeys.activeWorkspace, '999');
      final c = container(fakeClaude, ['claude'], db: db);
      final sub = c.listen(workspacesProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(startupControllerProvider.notifier).run();

      expect(
        await AppSettingsRepo(db).get(AppSettingKeys.activeWorkspace),
        '${ws.id}',
      );
      await c.read(workspacesProvider.future);
      expect(c.read(activeWorkspaceProvider)?.path, '/repo/a');
    });

    test('no workspaces clears the selection', () async {
      final db = memoryDatabase();
      await AppSettingsRepo(db).set(AppSettingKeys.activeWorkspace, '1');
      final c = container(fakeClaude, ['claude'], db: db);
      await c.read(startupControllerProvider.notifier).run();
      expect(
        await AppSettingsRepo(db).get(AppSettingKeys.activeWorkspace),
        isNull,
      );
      expect(c.read(startupControllerProvider).status, StartupStatus.done);
    });

    test('database that cannot be opened stops on the second step', () async {
      final db = AppDatabase(
        NativeDatabase(File('/nonexistent/promptorium-test/x.sqlite')),
      );
      final c = container(fakeClaude, ['claude'], db: db);
      await c.read(startupControllerProvider.notifier).run();

      final s = c.read(startupControllerProvider);
      expect(s.status, StartupStatus.failed);
      expect(s.completed, 1);
      expect(s.label, 'Não foi possível abrir o banco local');
      expect(s.error?.hint, contains('promptorium.sqlite'));
    });
  });

  group('SplashScreen', () {
    Widget app(ProcessRunner runner, VoidCallback onFinished) => ProviderScope(
      overrides: [
        databaseOverride(memoryDatabase()),
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
      await tester.pump(Duration.zero); // drift stream-cancel timer
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
      await tester.pump(Duration.zero); // drift stream-cancel timer
    });
  });
}
