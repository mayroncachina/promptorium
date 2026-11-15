import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/app_shutdown.dart';
import 'package:promptorium/core/dev/dev_server.dart';
import 'package:promptorium/core/dev/preview_browser.dart';
import 'package:promptorium/features/sessions/widgets/session_terminal.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';

AppShutdown _shutdown(
  List<String> calls, {
  Future<void>? database,
  Duration databaseTimeout = const Duration(seconds: 3),
}) => AppShutdown(
  stopWork: () async => calls.add('stopWork'),
  closeDatabase: () async {
    calls.add('closeDatabase');
    await database;
  },
  destroyWindow: () async => calls.add('destroyWindow'),
  exitWith: (code) => calls.add('exit $code'),
  kill: () => calls.add('kill'),
  databaseTimeout: databaseTimeout,
  log: calls.add,
);

/// The on-disk database of the app, in a drift isolate like
/// `AppDatabase.open()`.
AppDatabase _isolateDatabase(File file) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.createInBackground(file));
}

class _ThrowingTerminals extends SessionTerminals {
  @override
  void killAll() => throw StateError('pty');
}

class _Registry extends DevServerRegistry {
  _Registry(this.calls) : super(runDir: Directory.systemTemp.path);

  final List<String> calls;

  @override
  Future<void> stopAll() async => calls.add('servidores');
}

class _Preview extends PreviewBrowser {
  _Preview(this.calls)
    : super(findBrowser: () async => null, profileBase: '/nenhum');

  final List<String> calls;

  @override
  Future<void> closeAll() async => calls.add('preview');
}

void main() {
  group('SPEC-070 R9 · time limits', () {
    test('the forced exit comes after the slowest normal shutdown', () {
      expect(
        AppShutdown.defaultForceAfter,
        greaterThan(AppShutdown.workTimeout + const Duration(seconds: 3)),
      );
    });

    test('a step that fails does not keep the others from running', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <String>[];
      final c = ProviderContainer(
        overrides: [
          sessionTerminalsProvider.overrideWith(_ThrowingTerminals.new),
          devServerRegistryProvider.overrideWithValue(_Registry(calls)),
          previewBrowserProvider.overrideWithValue(_Preview(calls)),
          appDatabaseProvider.overrideWithValue(
            AppDatabase(NativeDatabase.memory()),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appShutdownProvider).stop();
      expect(calls, containsAll(['servidores', 'preview']));
    });
  });

  group('SPEC-070 R10 · closing during the installation', () {
    test('waits for it: the window comes back, and the close happens when '
        'the update ends with the app open', () async {
      final calls = <String>[];
      var refused = 0;
      final shutdown = AppShutdown(
        stopWork: () async => calls.add('stopWork'),
        closeDatabase: () async => calls.add('closeDatabase'),
        destroyWindow: () async => calls.add('destroyWindow'),
        exitWith: (code) => calls.add('exit $code'),
        onCloseRefused: () => refused++,
        log: (_) {},
      )..beginInstall();
      await shutdown.closeWindow();
      expect(calls, isEmpty);
      expect(refused, 1);
      await shutdown.settleClose();
      expect(calls, ['stopWork', 'closeDatabase', 'destroyWindow']);
    });

    test('once installed, the update closes the app itself', () async {
      final calls = <String>[];
      final shutdown = _shutdown(calls)
        ..beginInstall()
        ..endInstall();
      await shutdown.closeWindow();
      expect(calls, ['stopWork', 'closeDatabase', 'destroyWindow']);
    });

    test('without a close asked, the end of the update closes nothing',
        () async {
      final calls = <String>[];
      final shutdown = _shutdown(calls)..beginInstall();
      await shutdown.settleClose();
      expect(calls, isEmpty);
      expect(shutdown.installing, isFalse);
    });
  });

  group('SPEC-070 R2 · one way out', () {
    test('the window and the tray stop everything, close the database, then '
        'destroy the window, once', () async {
      final calls = <String>[];
      final shutdown = _shutdown(calls);
      await Future.wait([shutdown.closeWindow(), shutdown.closeWindow()]);
      expect(calls, ['stopWork', 'closeDatabase', 'destroyWindow']);
    });

    test('a database that does not close still lets the window go', () async {
      final calls = <String>[];
      await _shutdown(
        calls,
        database: Completer<void>().future,
        databaseTimeout: const Duration(milliseconds: 50),
      ).closeWindow();
      expect(calls.first, 'stopWork');
      expect(calls.last, 'destroyWindow');
    });

    test(
      'the update after the window started closing stops nothing twice',
      () async {
        final calls = <String>[];
        final shutdown = _shutdown(calls);
        await shutdown.closeWindow();
        await shutdown.exitProcess(log: (_) {});
        expect(calls, ['stopWork', 'closeDatabase', 'destroyWindow', 'exit 0']);
      },
    );
  });

  // The cause of bug 1: the update got stuck in "Instalando e reiniciando…"
  // because AppDatabase.close() never returned. drift closes each query
  // stream first and waits for its listeners, and Riverpod pauses the stream
  // of a provider nobody is watching any more (a screen that was left).
  group('SPEC-070 · the cause: a paused query stream', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('shutdown');
      file = File('${dir.path}/promptorium.sqlite');
    });
    tearDown(() => dir.delete(recursive: true));

    /// A provider over a query, as the screens have, that was watched and
    /// then left: Riverpod keeps it, paused.
    Future<(ProviderContainer, AppDatabase)> leftScreen() async {
      final db = _isolateDatabase(file);
      final watched = StreamProvider<Map<String, String>>(
        (ref) => AppSettingsRepo(db).watchAll(),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(watched, (_, _) {});
      await container.read(watched.future);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return (container, db);
    }

    test(
      'AppDatabase.close() does not return while the stream is paused',
      () async {
        final (container, db) = await leftScreen();
        var closed = false;
        final closing = db.close().then((_) => closed = true);
        await Future<void>.delayed(const Duration(seconds: 1));
        // What happened before: no exit, no new copy.
        expect(closed, isFalse);
        // Cancelling the subscription (not pausing it) lets it go.
        container.dispose();
        await closing.timeout(const Duration(seconds: 1));
      },
    );

    test(
      'closeDatabaseForExit closes it at once and keeps what was written',
      () async {
        final (_, db) = await leftScreen();
        await AppSettingsRepo(db).set(AppSettingKeys.justInstalled, '0.17.0');
        await closeDatabaseForExit(db).timeout(const Duration(seconds: 1));

        final again = _isolateDatabase(file);
        addTearDown(again.close);
        expect(
          await AppSettingsRepo(again).get(AppSettingKeys.justInstalled),
          '0.17.0',
        );
      },
    );

    test(
      'the update exits with the paused stream, without the 3 s limit',
      () async {
        final (_, db) = await leftScreen();
        final calls = <String>[];
        final lines = <String>[];
        final shutdown = AppShutdown(
          stopWork: () async {},
          closeDatabase: () => closeDatabaseForExit(db),
          destroyWindow: () async {},
          exitWith: (code) => calls.add('exit $code'),
          kill: () => calls.add('kill'),
        );
        final watch = Stopwatch()..start();
        await shutdown.exitProcess(log: lines.add);
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
        expect(calls, ['exit 0']);
        expect(lines[1], matches(RegExp(r'^banco fechado em \d+ ms$')));
      },
    );
  });
}
