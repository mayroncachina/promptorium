import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/specs/prototype/prototype_thumbnails.dart'
    show prototypeThumbnailsProvider;
import '../claude/claude_process.dart' show ProcessStarter;
import 'dev_server.dart' show DevServer, PortProbe;
import 'picked_element.dart';
import 'picker_script.dart';

/// The preview's Chromium (SPEC-051 R6, R7, R9, R10): one window per
/// worktree, with its own profile and the DevTools protocol (CDP) only on
/// 127.0.0.1, spoken over a WebSocket of `dart:io`.

/// Without Chrome or Chromium (R9): what "Apontar" says.
const previewInstallHint =
    'Apontar precisa do Google Chrome ou do Chromium. Instale um deles '
    '(ex.: sudo apt install chromium) e abra o preview de novo.';

class PreviewException implements Exception {
  const PreviewException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The CDP WebSocket (faked in tests).
abstract class CdpSocket {
  Stream<String> get messages;
  void send(String data);
  Future<void> close();
}

class _IoCdpSocket implements CdpSocket {
  _IoCdpSocket(this._ws);

  final WebSocket _ws;

  @override
  Stream<String> get messages => _ws.where((m) => m is String).cast<String>();

  @override
  void send(String data) => _ws.add(data);

  @override
  Future<void> close() => _ws.close();
}

typedef CdpConnector = Future<CdpSocket> Function(
  Uri url, {
  Map<String, String> headers,
});

/// `GET http://127.0.0.1:<port>/json/list`.
typedef CdpTargets = Future<List<Map<String, Object?>>> Function(int port);

Future<CdpSocket> _defaultConnect(
  Uri url, {
  Map<String, String> headers = const {},
}) async => _IoCdpSocket(await WebSocket.connect('$url', headers: headers));

Future<List<Map<String, Object?>>> _defaultTargets(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/list'),
    );
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final list = jsonDecode(body);
    return [
      if (list is List)
        for (final t in list)
          if (t is Map) t.cast<String, Object?>(),
    ];
  } finally {
    client.close(force: true);
  }
}

/// JSON-RPC over the CDP socket.
class CdpClient {
  CdpClient(this._socket) {
    _sub = _socket.messages.listen(
      _onMessage,
      onDone: _onDone,
      onError: (_) => _onDone(),
    );
  }

  final CdpSocket _socket;
  late final StreamSubscription<String> _sub;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _events = StreamController<Map<String, Object?>>.broadcast();
  var _id = 0;
  bool closed = false;

  /// `{method, params}` of every event.
  Stream<Map<String, Object?>> get events => _events.stream;

  void _onMessage(String raw) {
    Object? m;
    try {
      m = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (m is! Map) return;
    final id = m['id'];
    if (id is int) {
      final c = _pending.remove(id);
      if (c == null) return;
      final err = m['error'];
      if (err is Map) {
        c.completeError(PreviewException('CDP: ${err['message'] ?? err}'));
      } else {
        c.complete((m['result'] as Map?)?.cast<String, Object?>() ?? const {});
      }
    } else if (m['method'] is String) {
      _events.add(m.cast<String, Object?>());
    }
  }

  void _onDone() {
    closed = true;
    for (final c in _pending.values) {
      c.completeError(const PreviewException('A janela do preview fechou.'));
    }
    _pending.clear();
    if (!_events.isClosed) _events.close();
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    if (closed) {
      return Future.error(
        const PreviewException('A janela do preview fechou.'),
      );
    }
    final id = ++_id;
    final c = _pending[id] = Completer<Map<String, Object?>>();
    _socket.send(jsonEncode({'id': id, 'method': method, 'params': params}));
    return c.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw PreviewException('CDP: $method não respondeu');
      },
    );
  }

  /// `Runtime.evaluate` with the value back.
  Future<Object?> evaluate(String expression) async {
    final r = await call('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
    });
    final ex = r['exceptionDetails'];
    if (ex is Map) {
      throw PreviewException('script do preview: ${ex['text'] ?? ex}');
    }
    return (r['result'] as Map?)?['value'];
  }

  Future<void> close() async {
    await _sub.cancel();
    _onDone();
    await _socket.close();
  }
}

/// Arguments of the preview's Chromium (R6, R10).
List<String> previewArgs({
  required String profileDir,
  required int cdpPort,
  required Uri url,
}) => [
  '--user-data-dir=$profileDir',
  '--remote-debugging-address=127.0.0.1',
  '--remote-debugging-port=$cdpPort',
  '--remote-allow-origins=http://127.0.0.1:$cdpPort',
  '--no-first-run',
  '--no-default-browser-check',
  '--disable-features=Translate',
  '--app=$url',
];

/// Profile folder of [worktree]'s preview (never the user's own profile).
String previewProfileDir(String base, String worktree) =>
    '$base/${sha1.convert(utf8.encode(worktree)).toString().substring(0, 12)}';

/// How "Abrir preview" went.
enum PreviewOpen { opened, reused, fallback }

class _Window {
  _Window(this.process, this.cdpPort, this.url);

  final Process process;
  final int cdpPort;
  Uri url;
  CdpClient? client;
  bool exited = false;
  Completer<String?>? picking;
  StreamSubscription<void>? server;

  void endPick() {
    final p = picking;
    if (p != null && !p.isCompleted) p.complete(null);
    picking = null;
  }
}

class PreviewBrowser {
  PreviewBrowser({
    required this.findBrowser,
    required this.profileBase,
    ProcessStarter? starter,
    CdpConnector? connect,
    CdpTargets? targets,
    Future<int> Function()? freePort,
    Future<void> Function(Uri url)? fallback,
    this.cdpTimeout = const Duration(seconds: 15),
  }) : _starter = starter ?? _start,
       _connect = connect ?? _defaultConnect,
       _targets = targets ?? _defaultTargets,
       _freePort = freePort ?? PortProbe.freePort,
       _fallback = fallback ?? _xdgOpen;

  final String profileBase;
  final Duration cdpTimeout;

  /// Same search as the thumbnails of SPEC-022 (R9).
  final Future<String?> Function() findBrowser;
  final ProcessStarter _starter;
  final CdpConnector _connect;
  final CdpTargets _targets;
  final Future<int> Function() _freePort;
  final Future<void> Function(Uri url) _fallback;

  final _windows = <String, _Window>{};
  final _changes = StreamController<void>.broadcast();

  static Future<Process> _start(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.start(exe, args, environment: environment);

  static Future<void> _xdgOpen(Uri url) async {
    try {
      await Process.run('xdg-open', ['$url']);
    } catch (e) {
      debugPrint('xdg-open preview: $e');
    }
  }

  /// Fires when a window opens / closes or "Apontar" turns on / off.
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<String?> browser() => findBrowser();

  /// Why "Apontar" is off (null = it works): no Chrome / Chromium (R9).
  Future<String?> unavailableReason() async =>
      await browser() == null ? previewInstallHint : null;

  bool isOpen(String worktree) => _windows[worktree]?.exited == false;

  bool isPicking(String worktree) => _windows[worktree]?.picking != null;

  /// "Abrir preview" (R6): a second call brings the same window forward.
  /// Without a browser, `xdg-open` (R9). The window closes when [server]
  /// is no longer up (R10).
  Future<PreviewOpen> open({
    required String worktree,
    required Uri url,
    DevServer? server,
  }) async {
    final w = _windows[worktree];
    if (w != null && !w.exited) {
      try {
        final c = await _client(worktree, w);
        await c.call('Page.bringToFront');
      } catch (e) {
        debugPrint('preview: trazer para frente — $e');
      }
      return PreviewOpen.reused;
    }
    final exe = await browser();
    if (exe == null) {
      await _fallback(url);
      return PreviewOpen.fallback;
    }
    final cdpPort = await _freePort();
    final profile = previewProfileDir(profileBase, worktree);
    await Directory(profile).create(recursive: true);
    final process = await _starter(
      exe,
      previewArgs(profileDir: profile, cdpPort: cdpPort, url: url),
    );
    final win = _windows[worktree] = _Window(process, cdpPort, url);
    if (server != null) {
      win.server = server.changes.listen((_) {
        if (!server.isUp) unawaited(close(worktree));
      });
    }
    process.stdout.drain<void>().ignore();
    process.stderr.drain<void>().ignore();
    unawaited(
      process.exitCode.then((_) {
        win.exited = true;
        win.endPick();
        unawaited(win.server?.cancel());
        unawaited(win.client?.close());
        if (identical(_windows[worktree], win)) _windows.remove(worktree);
        _notify();
      }),
    );
    _notify();
    return PreviewOpen.opened;
  }

  /// The CDP client of the preview page (waits for the DevTools endpoint).
  Future<CdpClient> _client(String worktree, _Window w) async {
    final open = w.client;
    if (open != null && !open.closed) return open;
    final end = DateTime.now().add(cdpTimeout);
    while (true) {
      if (w.exited) throw const PreviewException('A janela do preview fechou.');
      try {
        // The page of the server first; another page only after a while
        // (the app window may still be opening).
        final lenient = DateTime.now().isAfter(end.subtract(cdpTimeout ~/ 2));
        final page = _pageTarget(
          await _targets(w.cdpPort),
          w.url,
          lenient: lenient,
        );
        if (page != null) {
          final c = w.client = CdpClient(
            await _connect(
              page,
              headers: {'Origin': 'http://127.0.0.1:${w.cdpPort}'},
            ),
          );
          return c;
        }
      } catch (e) {
        if (e is PreviewException) rethrow;
      }
      if (DateTime.now().isAfter(end)) {
        throw const PreviewException(
          'O Chromium do preview não abriu o protocolo de depuração.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  /// The `page` target of the preview, only on 127.0.0.1 (R10).
  static Uri? _pageTarget(
    List<Map<String, Object?>> targets,
    Uri url, {
    bool lenient = true,
  }) {
    Uri? any;
    for (final t in targets) {
      if (t['type'] != 'page') continue;
      final ws = Uri.tryParse('${t['webSocketDebuggerUrl'] ?? ''}');
      if (ws == null || ws.host != '127.0.0.1') continue;
      final page = Uri.tryParse('${t['url'] ?? ''}');
      if (page != null && page.port == url.port) return ws;
      any ??= ws;
    }
    return lenient ? any : null;
  }

  /// "Apontar" (R7) on the preview of [worktree] (server at [url]): turns
  /// the picker on and waits for the click. Null when cancelled (Esc, a
  /// second "Apontar", window closed). Opens the window when needed.
  Future<PickedElement?> pick({
    required String worktree,
    required Uri url,
    DevServer? server,
  }) async {
    final current = _windows[worktree];
    if (current?.picking != null) {
      await cancelPick(worktree);
      return null;
    }
    final how = await open(worktree: worktree, url: url, server: server);
    if (how == PreviewOpen.fallback) {
      throw const PreviewException(previewInstallHint);
    }
    final w = _windows[worktree]!;
    final c = await _client(worktree, w);
    final picked = w.picking = Completer<String?>();
    _notify();
    try {
      await c.call('Runtime.enable');
      try {
        await c.call('Runtime.addBinding', {'name': pickerBinding});
      } on PreviewException {
        // Already added in this page.
      }
      final sub = c.events.listen((e) {
        if (e['method'] != 'Runtime.bindingCalled') return;
        final p = e['params'];
        if (p is Map && p['name'] == pickerBinding && !picked.isCompleted) {
          picked.complete('${p['payload']}');
        }
      });
      try {
        await c.call('Page.bringToFront');
        // Right after "Abrir preview" the page may still be loading (or
        // navigating, which destroys the context of the evaluate).
        Object? on;
        PreviewException? last;
        for (var i = 0; i < 20; i++) {
          try {
            on = await c.evaluate(pickerExpression(url.port));
          } on PreviewException catch (e) {
            if (c.closed) rethrow;
            last = e;
            on = null;
          }
          if (on == 'on' || picked.isCompleted) break;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (on == 'blocked') {
          throw PreviewException(
            'A janela do preview saiu de localhost:${url.port}. Volte para a '
            'página do servidor e aponte de novo.',
          );
        }
        if (on != 'on' && !picked.isCompleted) {
          throw last ??
              const PreviewException('Não deu para ligar o Apontar na página.');
        }
        final payload = await picked.future;
        if (payload == null) return null;
        final el = PickedElement.fromPayload(payload);
        if (el == null) return null;
        final box = (jsonDecode(payload) as Map)['box'] as Map;
        final shots = await _screenshots(c, box);
        return el.withImages(element: shots.$1, page: shots.$2);
      } finally {
        await sub.cancel();
        try {
          await c.evaluate(pickerStopExpression);
        } catch (_) {}
      }
    } finally {
      if (identical(w.picking, picked)) w.picking = null;
      _notify();
    }
  }

  Future<(Uint8List?, Uint8List?)> _screenshots(CdpClient c, Map box) async {
    double n(Object? v) => v is num ? v.toDouble() : 0;
    const margin = 16.0;
    final x = (n(box['x']) - margin).clamp(0, double.infinity).toDouble();
    final y = (n(box['y']) - margin).clamp(0, double.infinity).toDouble();
    Future<Uint8List?> shot(Map<String, Object?> params) async {
      try {
        final r = await c.call('Page.captureScreenshot', {
          'format': 'png',
          ...params,
        });
        final data = r['data'];
        return data is String ? base64Decode(data) : null;
      } catch (e) {
        debugPrint('preview: print — $e');
        return null;
      }
    }

    final element = await shot({
      'captureBeyondViewport': true,
      'clip': {
        'x': x,
        'y': y,
        'width': n(box['width']) + margin * 2,
        'height': n(box['height']) + margin * 2,
        'scale': 1,
      },
    });
    try {
      await c.evaluate(pickerMarkExpression);
    } catch (_) {}
    final page = await shot(const {});
    return (element, page);
  }

  /// Turns "Apontar" off without capturing (a second "Apontar", R7).
  Future<void> cancelPick(String worktree) async {
    final w = _windows[worktree];
    final p = w?.picking;
    if (w == null || p == null) return;
    if (!p.isCompleted) p.complete(null);
  }

  /// `Runtime.evaluate` on the preview page (null when it is not open).
  Future<Object?> evaluate(String worktree, String expression) async {
    final w = _windows[worktree];
    if (w == null || w.exited) return null;
    return (await _client(worktree, w)).evaluate(expression);
  }

  /// `Page.reload` (R11).
  Future<void> reload(String worktree) async {
    final w = _windows[worktree];
    if (w == null || w.exited) return;
    await (await _client(worktree, w)).call('Page.reload');
  }

  /// Closes the window of [worktree] (server stopped, session deleted, R10).
  Future<void> close(String worktree) async {
    final w = _windows.remove(worktree);
    if (w == null) return;
    w.endPick();
    unawaited(w.server?.cancel());
    try {
      await w.client?.close();
    } catch (_) {}
    if (!w.exited) {
      w.process.kill();
      await w.process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          w.process.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
    }
    _notify();
  }

  /// Every window (closing the app, R10).
  Future<void> closeAll() =>
      Future.wait([for (final w in _windows.keys.toList()) close(w)]);
}

/// `$XDG_CACHE_HOME` or `~/.cache`, then `promptorium/preview` (R6).
final previewProfileBaseProvider = Provider<String>((ref) {
  final env = Platform.environment;
  final base = env['XDG_CACHE_HOME']?.isNotEmpty == true
      ? env['XDG_CACHE_HOME']!
      : '${env['HOME'] ?? Directory.systemTemp.path}/.cache';
  return '$base/promptorium/preview';
});

/// Same search as the thumbnails of SPEC-022 (R9).
final previewBrowserProvider = Provider<PreviewBrowser>((ref) {
  final thumbs = ref.watch(prototypeThumbnailsProvider);
  return PreviewBrowser(
    findBrowser: thumbs.findBrowser,
    profileBase: ref.watch(previewProfileBaseProvider),
  );
});

/// Ticks when a preview window opens / closes or "Apontar" changes.
final previewBrowserTickProvider = StreamProvider.autoDispose<int>((ref) {
  var n = 0;
  return ref.watch(previewBrowserProvider).changes.map((_) => ++n);
});

/// "Apontar" is off with this reason (null = available), R9.
final previewUnavailableProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(previewBrowserProvider).unavailableReason(),
);
