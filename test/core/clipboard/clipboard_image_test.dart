import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/clipboard/clipboard_image.dart';
import 'package:promptorium/features/project/environment_check.dart';

/// Fake `wl-paste` / `xclip`: [types] is what the list prints, [images] the
/// bytes of each type; [missing] = the tool is not installed.
class FakeClipboard {
  FakeClipboard({this.types = const [], this.images = const {}});

  List<String> types;
  Map<String, List<int>> images;
  bool missing = false;
  bool empty = false;
  final calls = <String>[];

  Future<ProcessResult> run(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    if (missing) throw ProcessException(exe, args, 'not found');
    if (exe == 'which') return ProcessResult(0, 0, '/usr/bin/x', '');
    if (empty) return ProcessResult(0, 1, '', 'Nothing is copied');
    return ProcessResult(0, 0, types.join('\n'), '');
  }

  Future<ProcessResult> runBinary(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    if (missing) throw ProcessException(exe, args, 'not found');
    final type = args[args.indexOf(exe == 'xclip' ? '-t' : '--type') + 1];
    final bytes = images[type];
    return bytes == null
        ? ProcessResult(0, 1, <int>[], 'no')
        : ProcessResult(0, 0, bytes, '');
  }

  ClipboardImageReader reader({bool wayland = false}) => ClipboardImageReader(
    run: run,
    runBinary: runBinary,
    environment: wayland ? const {'WAYLAND_DISPLAY': 'wayland-0'} : const {},
  );
}

void main() {
  group('ClipboardImageReader (SPEC-083 R2)', () {
    test('Wayland uses wl-paste: lists the types, reads image/png', () async {
      final fake = FakeClipboard(
        types: ['text/plain', 'image/png', 'image/jpeg'],
        images: {
          'image/png': [1, 2, 3],
        },
      );
      final r = await fake.reader(wayland: true).read();
      expect(r, isA<ClipboardImageFound>());
      final img = r as ClipboardImageFound;
      expect(img.mediaType, 'image/png');
      expect(img.bytes, [1, 2, 3]);
      expect(fake.calls, [
        'wl-paste --list-types',
        'wl-paste --no-newline --type image/png',
      ]);
    });

    test('X11 uses xclip with TARGETS and falls back to image/jpeg', () async {
      final fake = FakeClipboard(
        types: ['TARGETS', 'image/jpeg', 'UTF8_STRING'],
        images: {
          'image/jpeg': [9],
        },
      );
      final reader = fake.reader();
      expect(reader.wayland, isFalse);
      final r = await reader.read() as ClipboardImageFound;
      expect(r.mediaType, 'image/jpeg');
      expect(fake.calls, [
        'xclip -selection clipboard -t TARGETS -o',
        'xclip -selection clipboard -t image/jpeg -o',
      ]);
    });

    test('accepts image/webp when it is the only image type', () async {
      final fake = FakeClipboard(
        types: ['image/webp'],
        images: {
          'image/webp': [7],
        },
      );
      final r = await fake.reader().read() as ClipboardImageFound;
      expect(r.mediaType, 'image/webp');
    });

    test('text only (or an empty clipboard) gives no image', () async {
      final fake = FakeClipboard(types: ['text/plain', 'UTF8_STRING']);
      expect(await fake.reader().read(), isA<ClipboardNoImage>());
      expect(fake.calls, hasLength(1), reason: 'no read without an image');
      fake.empty = true;
      expect(await fake.reader(wayland: true).read(), isA<ClipboardNoImage>());
    });

    test('without the tool: the reason and the install command', () async {
      final fake = FakeClipboard()..missing = true;
      final x11 = await fake.reader().read() as ClipboardToolMissing;
      expect(x11.tool, 'xclip');
      expect(x11.command, 'sudo apt install xclip');
      final wl =
          await fake.reader(wayland: true).read() as ClipboardToolMissing;
      expect(wl.tool, 'wl-clipboard');
      expect(wl.command, 'sudo apt install wl-clipboard');
      expect(
        ClipboardToolMissing.message,
        'Para colar imagens, instale o wl-clipboard (Wayland) ou o xclip '
        '(X11).',
      );
      expect(await fake.reader().missingTool(), isNotNull);
    });

    test('the environment check lists the tool as optional', () async {
      final fake = FakeClipboard();
      final ok = await checkClipboard(fake.reader());
      expect(ok.kind, EnvKind.clipboard);
      expect(ok.state, EnvState.ok);
      expect(ok.title, contains('opcional'));
      fake.missing = true;
      final missing = await checkClipboard(fake.reader(wayland: true));
      expect(missing.state, EnvState.warning, reason: 'never blocks');
      expect(missing.blocks, isFalse);
      expect(missing.command, 'sudo apt install wl-clipboard');
      expect(envGate([missing]).canCreate, isTrue);
    });
  });
}
