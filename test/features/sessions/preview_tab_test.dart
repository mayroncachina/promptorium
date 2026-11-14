import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/dev/dev_server.dart';
import 'package:promptorium/core/dev/preview_browser.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/sessions/session_dev.dart';
import 'package:promptorium/features/sessions/widgets/dev_server_control.dart';
import 'package:promptorium/features/sessions/widgets/point_button.dart';
import 'package:promptorium/features/sessions/widgets/preview_tab.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/dev/dev_server_test.dart' show FakeProcInfo, FakeProcess;

/// SPEC-051 R2, R3, R4, R5: the server control of the header and the
/// Preview tab.
void main() {
  late Directory tmp;
  late FakeProcInfo proc;
  late FakeProcess process;
  late List<(int, ProcessSignal)> signals;
  late List<String> sent;
  var ssOut = '';

  const dev = SessionDev(
    config: DevServerConfig(command: 'npm run dev', path: '/login'),
    worktree: '/wt/login',
    root: '/repo',
    port: 4003,
    specCode: 'SPEC-012',
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('preview_tab_');
    proc = FakeProcInfo();
    process = FakeProcess(48211);
    signals = [];
    sent = [];
    ssOut = '';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  DevServerRegistry registry() => DevServerRegistry(
    runDir: '${tmp.path}/run',
    proc: proc,
    appPid: 1,
    pollInterval: const Duration(milliseconds: 5),
    stopGrace: const Duration(milliseconds: 100),
    starter: (exe, args, {workingDirectory, environment}) async {
      proc.groups[process.pid] = [process.pid];
      return process;
    },
    signal: (pgid, s) async {
      signals.add((pgid, s));
      proc.groups.remove(pgid);
      process.exit(-15);
    },
    probe: PortProbe(
      proc: proc,
      run: (e, a) async => ProcessResult(1, 0, ssOut, ''),
      http: (_) async => false,
    ),
  );

  Future<DevServerRegistry> pump(
    WidgetTester tester, {
    DevServerRegistry? reg,
  }) async {
    final r = reg ?? registry();
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [devServerRegistryProvider.overrideWithValue(r)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: [
                DevServerControl(dev: dev, onShowLogs: () {}),
                Expanded(
                  child: PreviewTab(
                    dev: dev,
                    sendToSession: (t) async => sent.add(t),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return r;
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('header: Servidor parado → Iniciar servidor → Iniciando… '
      ':porta with Parar; logs with the 2.000-line limit and search (R2, '
      'R4)', (tester) async {
    final r = await pump(tester);
    expect(find.text('Servidor parado'), findsOneWidget);
    expect(
      find.text(
        'Sem logs ainda. Inicie o servidor no cabeçalho da '
        'sessão.',
      ),
      findsOneWidget,
    );
    expect(text(tester, 'preview-state'), 'Parado');

    await tester.tap(find.byKey(const ValueKey('dev-start')));
    await settleUntil(
      tester,
      () =>
          find.text('Iniciando… :4003').evaluate().isNotEmpty &&
          r.of(dev.worktree).pid != null,
    );
    expect(find.text('Iniciando… :4003'), findsOneWidget);
    expect(find.byKey(const ValueKey('dev-stop')), findsOneWidget);
    expect(text(tester, 'preview-process'), 'PID 48211 · grupo 48211');

    final s = r.of(dev.worktree);
    await tester.runAsync(() async {
      for (var i = 0; i < 2100; i++) {
        process.say('linha $i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (var i = 0; i < 50 && s.logs.length < 2000; i++) {
      await settle(tester);
    }
    expect(s.logs.length, 2000);
    expect(text(tester, 'preview-log-count'), 'Logs · 2.000 de 2.000 linhas');

    await tester.enterText(
      find.byKey(const ValueKey('preview-log-search')),
      'linha 2099',
    );
    await tester.pump();
    final list = find.byKey(const ValueKey('preview-log-list'));
    expect(
      find.descendant(of: list, matching: find.text('linha 2099')),
      findsOneWidget,
    );
    expect(find.text('linha 2098'), findsNothing);

    // No error in the log: nothing to send.
    await tester.tap(find.byKey(const ValueKey('preview-send-error')));
    await settle(tester);
    expect(sent, isEmpty);

    await tester.tap(find.byKey(const ValueKey('dev-stop')));
    await settleUntil(
      tester,
      () => find.text('Servidor parado').evaluate().isNotEmpty,
    );
    expect(signals.first, (48211, ProcessSignal.sigterm));
    expect(find.text('Servidor parado'), findsOneWidget);
  });

  testWidgets('Falhou with the reason and Ver logs; Mandar erro para a '
      'sessão sends the last lines (R2, R4)', (tester) async {
    final r = await pump(tester);
    await tester.runAsync(
      () => r
          .of(dev.worktree)
          .start(config: dev.config, port: 4003, environment: dev.environment),
    );
    await tester.runAsync(() async {
      process.say('> vite --port 4003');
      process.say('Error: Cannot find module "vite"');
      process.exit(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settleUntil(
      tester,
      () => find
          .text('Falhou · o comando terminou (código 1)')
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('Falhou · o comando terminou (código 1)'), findsWidgets);
    expect(find.byKey(const ValueKey('dev-show-logs')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preview-send-error')));
    await settleUntil(tester, () => sent.isNotEmpty);
    expect(sent, hasLength(1));
    expect(sent.single, contains('falhou: o comando terminou (código 1)'));
    expect(sent.single, contains('Error: Cannot find module "vite"'));
    expect(sent.single, contains('`npm run dev`'));
  });

  testWidgets('port taken by another process: PID, command and folder, '
      '"Usar o que está no ar" and nothing killed (R3)', (tester) async {
    ssOut =
        'LISTEN 0 511 127.0.0.1:4003 0.0.0.0:* '
        'users:(("node",pid=39120,fd=23))\n';
    proc.groups[39120] = [39120];
    proc.cmd[39120] = 'vite --port 4003';
    final r = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('dev-start')));
    await settleUntil(
      tester,
      () => find.text('Falhou · porta 4003 ocupada').evaluate().isNotEmpty,
    );
    expect(find.text('Falhou · porta 4003 ocupada'), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-port-taken')), findsOneWidget);
    expect(
      find.text('O servidor não subiu: a porta 4003 já está em uso'),
      findsOneWidget,
    );
    expect(text(tester, 'preview-owner-pid'), 'PID 39120 · node');
    expect(find.text('vite --port 4003'), findsOneWidget);
    expect(find.text('/home/eu/loja-web'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preview-use-running')));
    await settle(tester);
    expect(find.text('No ar :4003'), findsOneWidget);
    expect(r.of(dev.worktree).external, isTrue);
    expect(text(tester, 'preview-process'), 'de fora do app (não é encerrado)');
    await tester.tap(find.byKey(const ValueKey('dev-stop')));
    await settle(tester);
    expect(signals, isEmpty);
  });

  testWidgets('a server left by a run that crashed is offered: Encerrar '
      'ends its group (R5)', (tester) async {
    proc.groups[31877] = [31877];
    proc.env[31877] = {'PROMPTORIUM_WORKTREE': '/wt/busca'};
    final r = registry();
    await tester.runAsync(
      () => r.writeRecord(
        DevServerRecord(
          pid: 31877,
          pgid: 31877,
          worktree: '/wt/busca',
          port: 4001,
          command: 'npm run dev',
          startedAt: DateTime(2026),
          appPid: 2,
        ),
      ),
    );
    await pump(tester, reg: r);
    for (var i = 0; i < 50; i++) {
      if (find
          .byKey(const ValueKey('preview-leftover-31877'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await settle(tester);
    }
    expect(
      find.byKey(const ValueKey('preview-leftover-31877')),
      findsOneWidget,
    );
    expect(find.textContaining('busca · :4001 · PID 31877'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preview-leftover-end-31877')));
    for (var i = 0; i < 50; i++) {
      if (find
          .byKey(const ValueKey('preview-leftover-31877'))
          .evaluate()
          .isEmpty) {
        break;
      }
      await settle(tester);
    }
    expect(signals, [(31877, ProcessSignal.sigterm)]);
    expect(find.byKey(const ValueKey('preview-leftover-31877')), findsNothing);
  });

  testWidgets('no ar :porta shows Abrir preview, Apontar and Parar '
      'servidor; without Chrome or Chromium Apontar is off with the reason '
      '(R2, R9)', (tester) async {
    final r = registry();
    final opened = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          devServerRegistryProvider.overrideWithValue(r),
          previewBrowserProvider.overrideWithValue(
            PreviewBrowser(
              findBrowser: () async => null,
              profileBase: tmp.path,
              fallback: (u) async => opened.add(u),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => DevServerControl(
                dev: dev,
                onShowLogs: () {},
                onOpenPreview: (s) => openPreviewWindow(ref, context, s),
                extra: const [PointButton(sessionId: 's1', dev: dev)],
              ),
            ),
          ),
        ),
      ),
    );
    r.of(dev.worktree).useRunning(4003);
    Tooltip tooltip() => tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const ValueKey('dev-point')),
        matching: find.byType(Tooltip),
      ),
    );
    await settleUntil(
      tester,
      () =>
          find.byKey(const ValueKey('dev-point')).evaluate().isNotEmpty &&
          tooltip().message == previewInstallHint,
    );
    expect(find.text('No ar :4003'), findsOneWidget);
    expect(find.text('Abrir preview'), findsOneWidget);
    expect(find.text('Apontar'), findsOneWidget);
    expect(find.text('Esquecer'), findsOneWidget); // not started by the app
    final tip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const ValueKey('dev-point')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tip.message, previewInstallHint);

    await tester.tap(find.byKey(const ValueKey('dev-open-preview')));
    await settleUntil(tester, () => opened.isNotEmpty);
    expect(opened, [Uri.parse('http://localhost:4003/')]);
  });

  test('uptime and the error message', () {
    expect(uptimeLabel(const Duration(seconds: 20)), 'há menos de 1 min');
    expect(uptimeLabel(const Duration(minutes: 4)), 'há 4 min');
    expect(uptimeLabel(const Duration(minutes: 125)), 'há 2 h 5 min');
  });
}

/// Real IO (files, fake processes) between frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await settle(tester);
  }
}
