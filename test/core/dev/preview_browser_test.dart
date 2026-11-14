import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/dev/picker_script.dart';
import 'package:promptorium/core/dev/preview_browser.dart';

import 'dev_server_test.dart' show FakeProcess;

/// CDP of the tests: answers every call and records the methods.
class FakeCdp implements CdpSocket {
  final _in = StreamController<String>();
  final methods = <String>[];
  final params = <Map<String, Object?>>[];
  Object? evaluateValue = 'on';
  bool closed = false;

  /// Called after a `Runtime.evaluate` with the picker.
  void Function()? onPicker;

  @override
  Stream<String> get messages => _in.stream;

  void event(String method, Map<String, Object?> params) =>
      _in.add(jsonEncode({'method': method, 'params': params}));

  @override
  void send(String data) {
    final m = jsonDecode(data) as Map<String, dynamic>;
    final method = m['method'] as String;
    methods.add(method);
    params.add((m['params'] as Map).cast<String, Object?>());
    Map<String, Object?> result = const {};
    if (method == 'Runtime.evaluate') {
      final expr = '${m['params']['expression']}';
      final picker =
          expr.contains('__promptoriumInstall') || expr.contains('"binding"');
      result = {
        'result': {'type': 'string', 'value': picker ? evaluateValue : 'off'},
      };
      if (picker) scheduleMicrotask(() => onPicker?.call());
    } else if (method == 'Page.captureScreenshot') {
      result = {
        'data': base64Encode([137, 80, 78, 71]),
      };
    }
    scheduleMicrotask(
      () => _in.add(jsonEncode({'id': m['id'], 'result': result})),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late List<(String, List<String>)> started;
  late List<FakeProcess> processes;
  late List<Uri> fallbacks;
  late List<(Uri, Map<String, String>)> connects;
  late FakeCdp cdp;
  String? browserPath;
  var targetHost = '127.0.0.1';

  PreviewBrowser make() => PreviewBrowser(
    findBrowser: () async => browserPath,
    profileBase: '/tmp/promptorium-test-preview',
    freePort: () async => 9333,
    fallback: (u) async => fallbacks.add(u),
    starter: (exe, args, {workingDirectory, environment}) async {
      started.add((exe, args));
      final p = FakeProcess(7000 + processes.length);
      processes.add(p);
      return p;
    },
    targets: (port) async => [
      {
        'type': 'page',
        'url': 'http://localhost:4003/login',
        'webSocketDebuggerUrl': 'ws://$targetHost:$port/devtools/page/AB',
      },
    ],
    connect: (url, {headers = const {}}) async {
      connects.add((url, headers));
      return cdp;
    },
    cdpTimeout: const Duration(milliseconds: 300),
  );

  setUp(() {
    started = [];
    processes = [];
    fallbacks = [];
    connects = [];
    cdp = FakeCdp();
    browserPath = '/usr/bin/chromium';
    targetHost = '127.0.0.1';
  });

  final url = Uri.parse('http://localhost:4003/login');

  test('the preview Chromium has its own profile and CDP only on '
      '127.0.0.1; a second click brings the same window forward (R6, '
      'R10)', () async {
    final b = make();
    expect(await b.open(worktree: '/wt/a', url: url), PreviewOpen.opened);
    final (exe, args) = started.single;
    expect(exe, '/usr/bin/chromium');
    final profile = previewProfileDir('/tmp/promptorium-test-preview', '/wt/a');
    expect(profile, startsWith('/tmp/promptorium-test-preview/'));
    expect(args, contains('--user-data-dir=$profile'));
    expect(args, contains('--remote-debugging-address=127.0.0.1'));
    expect(args, contains('--remote-debugging-port=9333'));
    expect(args, contains('--remote-allow-origins=http://127.0.0.1:9333'));
    expect(args, contains('--app=http://localhost:4003/login'));
    expect(args.where((a) => a.startsWith('--user-data-dir')), hasLength(1));
    expect(
      previewProfileDir('/b', '/wt/a'),
      isNot(previewProfileDir('/b', '/wt/b')),
    );
    expect(b.isOpen('/wt/a'), isTrue);

    expect(await b.open(worktree: '/wt/a', url: url), PreviewOpen.reused);
    expect(started, hasLength(1));
    expect(cdp.methods, contains('Page.bringToFront'));
    final (ws, headers) = connects.single;
    expect(ws.host, '127.0.0.1');
    expect(headers['Origin'], 'http://127.0.0.1:9333');

    // Another worktree, another window.
    await b.open(worktree: '/wt/b', url: url);
    expect(started, hasLength(2));

    await b.close('/wt/a');
    expect(processes.first.kills, isNotEmpty);
    expect(b.isOpen('/wt/a'), isFalse);
    await b.closeAll();
    expect(processes.last.kills, isNotEmpty);
  });

  test('a DevTools target off 127.0.0.1 is never used (R10)', () async {
    targetHost = '0.0.0.0';
    final b = make();
    await b.open(worktree: '/wt/a', url: url);
    await expectLater(
      b.pick(worktree: '/wt/a', url: url),
      throwsA(isA<PreviewException>()),
    );
    expect(connects, isEmpty);
  });

  test('without Chrome or Chromium: Abrir preview uses xdg-open and Apontar '
      'is off with the reason (R9)', () async {
    browserPath = null;
    final b = make();
    expect(await b.unavailableReason(), previewInstallHint);
    expect(previewInstallHint, contains('Chromium'));
    expect(await b.open(worktree: '/wt/a', url: url), PreviewOpen.fallback);
    expect(fallbacks, [url]);
    expect(started, isEmpty);
    await expectLater(
      b.pick(worktree: '/wt/a', url: url),
      throwsA(
        isA<PreviewException>().having(
          (e) => e.message,
          'message',
          previewInstallHint,
        ),
      ),
    );
  });

  test('Apontar injects the picker, takes the click and both PNGs; a '
      'second Apontar cancels (R7)', () async {
    final b = make();
    cdp.onPicker = () => cdp.event('Runtime.bindingCalled', {
      'name': pickerBinding,
      'payload': jsonEncode({
        'selector': 'form.login > button[type=submit]',
        'html': '<button>Continuar</button>',
        'styles': {'color': '#fff'},
        'box': {'x': 400, 'y': 300, 'width': 348, 'height': 44},
        'url': 'http://127.0.0.1:4003/login',
      }),
    });
    final el = await b.pick(worktree: '/wt/a', url: url);
    expect(started, hasLength(1)); // opened the window first
    expect(el!.selector, 'form.login > button[type=submit]');
    expect(el.styles, {'color': '#fff'});
    expect(el.width, 348);
    expect(el.elementPng, [137, 80, 78, 71]);
    expect(el.pagePng, isNotNull);
    expect(el.imageCount, 2);
    expect(
      cdp.methods,
      containsAllInOrder([
        'Runtime.enable',
        'Runtime.addBinding',
        'Runtime.evaluate',
        'Page.captureScreenshot',
        'Runtime.evaluate', // mark the element for the page print
        'Page.captureScreenshot',
        'Runtime.evaluate',
      ]),
    );
    final clip =
        cdp.params.firstWhere((p) => p.containsKey('clip'))['clip'] as Map;
    expect(clip['x'], 384);
    expect(clip['width'], 380);
    expect(b.isPicking('/wt/a'), isFalse);

    // Second Apontar while waiting: cancelled, nothing captured.
    cdp.onPicker = null;
    final waiting = b.pick(worktree: '/wt/a', url: url);
    await pumpEventQueue();
    expect(b.isPicking('/wt/a'), isTrue);
    expect(await b.pick(worktree: '/wt/a', url: url), isNull);
    expect(await waiting, isNull);
    expect(b.isPicking('/wt/a'), isFalse);
  });

  test(
    'Esc in the page cancels; a page off the preview port is blocked',
    () async {
      final b = make();
      cdp.onPicker = () => cdp.event('Runtime.bindingCalled', {
        'name': pickerBinding,
        'payload': '{"cancel":true}',
      });
      expect(await b.pick(worktree: '/wt/a', url: url), isNull);

      cdp.evaluateValue = 'blocked';
      cdp.onPicker = null;
      await expectLater(
        b.pick(worktree: '/wt/a', url: url),
        throwsA(isA<PreviewException>()),
      );
    },
  );
}
