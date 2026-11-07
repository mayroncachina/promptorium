import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/dictation/model_store.dart';
import 'package:promptorium/features/dictation/voice_io.dart';
import 'package:promptorium/features/dictation/voice_model.dart';

void main() {
  late Directory tmp;
  late HttpServer server;
  late List<int> body;
  late List<String?> ranges;
  int? cutAt; // the connection drops after this many bytes

  ModelStore store({
    String? hash,
    Future<String> Function(String)? hasher,
    Duration verifyLimit = const Duration(seconds: 5),
  }) => ModelStore(
    Directory('${tmp.path}/models'),
    urlOf: (_) => Uri.parse('http://127.0.0.1:${server.port}/m.bin'),
    hashOf: (_) => hash ?? crypto.sha256.convert(body).toString(),
    hash: hasher,
    verifyLimit: verifyLimit,
  );

  Future<void> download(ModelStore s, {ModelDownloadToken? token}) =>
      s.download(
        VoiceModel.fast,
        token: token,
        onProgress: (_, _) {},
        onVerifying: () {},
      );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-voice-');
    body = utf8.encode('modelo de voz ' * 2000);
    ranges = [];
    cutAt = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final range = r.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final from = range == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final rest = body.sublist(from);
      r.response
        ..statusCode = range == null ? 200 : 206
        ..contentLength = rest.length;
      if (cutAt != null) {
        final socket = await r.response.detachSocket();
        socket.add(rest.sublist(0, cutAt));
        await socket.flush();
        socket.destroy();
        return;
      }
      r.response.add(rest);
      await r.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  test(
    'R2: downloads, reports the progress and installs after the check',
    () async {
      final s = store();
      final seen = <int>[];
      var checked = false;
      await s.download(
        VoiceModel.fast,
        onProgress: (received, total) {
          seen.add(received);
          expect(total, body.length);
        },
        onVerifying: () => checked = true,
      );
      expect(seen.last, body.length);
      expect(checked, isTrue);
      expect(s.isInstalled(VoiceModel.fast), isTrue);
      expect(s.hasPartial(VoiceModel.fast), isFalse);
      expect(s.installed, {VoiceModel.fast});
    },
  );

  test('R2: a wrong sha256 is refused and deleted', () async {
    final s = store(hash: 'errado');
    await expectLater(download(s), throwsA(isA<ModelDownloadException>()));
    expect(s.isInstalled(VoiceModel.fast), isFalse);
    expect(s.hasPartial(VoiceModel.fast), isFalse);
  });

  test('R2: an interrupted download continues where it stopped', () async {
    final s = store();
    cutAt = 1000;
    await expectLater(download(s), throwsA(isA<ModelDownloadException>()));
    expect(s.hasPartial(VoiceModel.fast), isTrue);
    expect(s.isInstalled(VoiceModel.fast), isFalse);
    final kept = s.partOf(VoiceModel.fast).lengthSync();
    expect(kept, greaterThan(0));

    cutAt = null;
    await download(s);
    expect(ranges.last, 'bytes=$kept-');
    expect(s.fileOf(VoiceModel.fast).readAsBytesSync(), body);
  });

  test('R2: a check past the limit fails the download', () async {
    final s = store(
      hasher: (_) => Completer<String>().future,
      verifyLimit: const Duration(milliseconds: 20),
    );
    await expectLater(
      download(s),
      throwsA(
        isA<ModelDownloadException>().having(
          (e) => e.message,
          'message',
          contains('demorou'),
        ),
      ),
    );
    expect(s.isInstalled(VoiceModel.fast), isFalse);
  });

  test('Cancelar drops what arrived; pausing keeps it', () async {
    final hold = Completer<String>();
    final s = store(hasher: (_) => hold.future);
    final cancel = ModelDownloadToken();
    final run = s.download(
      VoiceModel.fast,
      token: cancel,
      onProgress: (_, _) {},
      onVerifying: cancel.cancel,
    );
    await expectLater(run, throwsA(isA<ModelDownloadCancelled>()));
    expect(s.hasPartial(VoiceModel.fast), isFalse);

    final pause = ModelDownloadToken();
    final paused = s.download(
      VoiceModel.fast,
      token: pause,
      onProgress: (_, _) {},
      onVerifying: pause.pause,
    );
    await expectLater(paused, throwsA(isA<ModelDownloadCancelled>()));
    expect(s.hasPartial(VoiceModel.fast), isTrue);
  });

  test('a server error fails and keeps nothing as installed', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      r.response.statusCode = 503;
      r.response.close();
    });
    final s = store();
    await expectLater(download(s), throwsA(isA<ModelDownloadException>()));
    expect(s.installed, isEmpty);
  });

  group('voice_io', () {
    test('the marks of silence are not speech', () {
      expect(cleanTranscript(' [BLANK_AUDIO]\n'), '');
      expect(cleanTranscript('(música) *risos*'), '');
      expect(cleanTranscript(' Olá,\n mundo. [BLANK_AUDIO]'), 'Olá, mundo.');
    });

    test('arecord -l lists the microphones', () {
      const out =
          '**** Lista de Dispositivos CAPTURE Hardware ****\n'
          'placa 0: sofhdadsp [sof-hda-dsp], dispositivo 0: HDA Analog (*) []\n'
          '  Dispositivo secundário: 1/1\n'
          'card 1: USB [Headset USB], device 0: USB Audio [USB Audio]\n';
      expect(parseArecordDevices(out), const [
        MicDevice('plughw:0,0', 'sof-hda-dsp'),
        MicDevice('plughw:1,0', 'Headset USB · USB Audio'),
      ]);
    });
  });
}
