import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/process_runner.dart';

/// Reads an **image** from the system clipboard on Linux (SPEC-083 R2, P1).
///
/// Flutter's [Clipboard] only reads text, so the image comes from the
/// command line: `wl-paste` on Wayland (`WAYLAND_DISPLAY` set) and `xclip`
/// on X11. The available types are listed first (`wl-paste --list-types`,
/// `xclip -t TARGETS`) and the first of [clipboardImageTypes] wins.

/// Preferred order of the image types read from the clipboard.
const clipboardImageTypes = ['image/png', 'image/jpeg', 'image/webp'];

/// Runs a process and returns stdout as raw bytes (`List<int>`).
typedef BinaryProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<ProcessResult> defaultBinaryRunner(
  String executable,
  List<String> args,
) => Process.run(
  executable,
  args,
  stdoutEncoding: null,
  stderrEncoding: lenientUtf8,
);

/// What the clipboard gave.
sealed class ClipboardImageResult {
  const ClipboardImageResult();
}

/// An image of [mediaType].
class ClipboardImageFound extends ClipboardImageResult {
  const ClipboardImageFound(this.bytes, this.mediaType);

  final Uint8List bytes;
  final String mediaType;
}

/// No image in the clipboard (text, nothing, or an unknown type).
class ClipboardNoImage extends ClipboardImageResult {
  const ClipboardNoImage();
}

/// The tool of this session is not installed.
class ClipboardToolMissing extends ClipboardImageResult {
  const ClipboardToolMissing({required this.tool, required this.command});

  /// `wl-clipboard` or `xclip`.
  final String tool;

  /// `sudo apt install wl-clipboard`.
  final String command;

  static const message =
      'Para colar imagens, instale o wl-clipboard (Wayland) ou o xclip (X11).';
}

class ClipboardImageReader {
  ClipboardImageReader({
    this.run = defaultProcessRunner,
    this.runBinary = defaultBinaryRunner,
    Map<String, String>? environment,
    this.timeout = const Duration(seconds: 3),
  }) : _env = environment ?? Platform.environment;

  /// Lists the types and finds the tool (text output).
  final ProcessRunner run;

  /// Reads the image (binary output).
  final BinaryProcessRunner runBinary;
  final Map<String, String> _env;
  final Duration timeout;

  /// Wayland when `WAYLAND_DISPLAY` is set.
  bool get wayland => (_env['WAYLAND_DISPLAY'] ?? '').isNotEmpty;

  /// The executable of this session (`wl-paste` or `xclip`).
  String get executable => wayland ? 'wl-paste' : 'xclip';

  ClipboardToolMissing get _missing => wayland
      ? const ClipboardToolMissing(
          tool: 'wl-clipboard',
          command: 'sudo apt install wl-clipboard',
        )
      : const ClipboardToolMissing(
          tool: 'xclip',
          command: 'sudo apt install xclip',
        );

  List<String> get _listArgs => wayland
      ? const ['--list-types']
      : const ['-selection', 'clipboard', '-t', 'TARGETS', '-o'];

  List<String> _readArgs(String type) => wayland
      ? ['--no-newline', '--type', type]
      : ['-selection', 'clipboard', '-t', type, '-o'];

  /// The image of the clipboard, [ClipboardNoImage] or the missing tool.
  Future<ClipboardImageResult> read() async {
    final ProcessResult list;
    try {
      list = await run(executable, _listArgs).timeout(timeout);
    } on ProcessException {
      return _missing;
    } on TimeoutException {
      return const ClipboardNoImage();
    }
    // Empty clipboard: `wl-paste` exits 1 with "Nothing is copied".
    if (list.exitCode != 0) return const ClipboardNoImage();
    final types = '${list.stdout}'
        .split('\n')
        .map((l) => l.trim().toLowerCase())
        .where((l) => l.isNotEmpty)
        .toSet();
    final type = clipboardImageTypes.where(types.contains).firstOrNull;
    if (type == null) return const ClipboardNoImage();
    try {
      final r = await runBinary(executable, _readArgs(type)).timeout(timeout);
      final out = r.stdout;
      if (r.exitCode != 0 || out is! List<int> || out.isEmpty) {
        return const ClipboardNoImage();
      }
      return ClipboardImageFound(Uint8List.fromList(out), type);
    } on ProcessException {
      return _missing;
    } on TimeoutException {
      return const ClipboardNoImage();
    }
  }

  /// Null when the tool of this session is installed; else what to install
  /// (the environment check, R2).
  Future<ClipboardToolMissing?> missingTool() async {
    try {
      final r = await run('which', [executable]).timeout(timeout);
      return r.exitCode == 0 ? null : _missing;
    } on ProcessException {
      return _missing;
    } on TimeoutException {
      return null;
    }
  }
}

final clipboardImageReaderProvider = Provider<ClipboardImageReader>(
  (ref) => ClipboardImageReader(run: ref.watch(processRunnerProvider)),
);
