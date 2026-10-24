import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/process/process_runner.dart';

/// Headless browsers tried for the thumbnails (SPEC-022 R4), in order.
const headlessBrowsers = [
  'google-chrome',
  'google-chrome-stable',
  'chromium',
  'chromium-browser',
];

/// Size of the canvas thumbnails (R4).
const thumbnailSize = (width: 1440, height: 900);

/// Narrow window of "Comparar variações" (R8).
const narrowThumbnailSize = (width: 1100, height: 700);

typedef ThumbSize = ({int width, int height});

/// How to install a browser (R5), shown once.
const headlessInstallHint =
    'Sem navegador headless: instale o Google Chrome ou o Chromium '
    '(ex.: sudo apt install chromium) para ver as miniaturas das telas.';

/// Folder of the PNG thumbnails: outside the repository
/// (`$XDG_CACHE_HOME` or `~/.cache`, then `promptorium/mockups`).
final prototypeCacheDirProvider = Provider<String>((ref) {
  final env = Platform.environment;
  final base = env['XDG_CACHE_HOME']?.isNotEmpty == true
      ? env['XDG_CACHE_HOME']!
      : '${env['HOME'] ?? Directory.systemTemp.path}/.cache';
  return '$base/promptorium/mockups';
});

/// Arguments of one screenshot (without the executable).
List<String> headlessArgs({
  required String html,
  required String png,
  required String profileDir,
  ThumbSize size = thumbnailSize,
}) => [
  '--headless=new',
  '--disable-gpu',
  '--hide-scrollbars',
  '--no-first-run',
  '--no-default-browser-check',
  '--user-data-dir=$profileDir',
  '--screenshot=$png',
  '--window-size=${size.width},${size.height}',
  Uri.file(html).toString(),
];

/// PNG thumbnails of the HTML screens through a headless Chrome/Chromium.
class PrototypeThumbnails {
  PrototypeThumbnails({required this.run, required this.cacheDir});

  final ProcessRunner run;
  final String cacheDir;

  Future<String?>? _browser;

  /// First of [headlessBrowsers] found by `which` (looked up once).
  Future<String?> findBrowser() => _browser ??= () async {
    for (final b in headlessBrowsers) {
      try {
        final r = await run('which', [b]);
        final path = '${r.stdout}'.trim().split('\n').first.trim();
        if (r.exitCode == 0 && path.isNotEmpty) return path;
      } catch (_) {
        // `which` missing: try the next name.
      }
    }
    return null;
  }();

  /// Cache file of [html] at [size]: changes with the file's mtime and length.
  Future<String> cachePath(
    String html, {
    ThumbSize size = thumbnailSize,
  }) async {
    final st = await File(html).stat();
    final key =
        '$html|${st.modified.microsecondsSinceEpoch}|${st.size}|'
        '${size.width}x${size.height}';
    final hash = sha1.convert(utf8.encode(key)).toString();
    return '$cacheDir/$hash.png';
  }

  /// Cached PNG of [html], or null when it was not generated yet.
  Future<String?> cached(String html, {ThumbSize size = thumbnailSize}) async {
    if (!await File(html).exists()) return null;
    final png = await cachePath(html, size: size);
    return await File(png).exists() ? png : null;
  }

  /// PNG of [html] (generated when missing). Null when there is no browser
  /// or it failed.
  Future<String?> thumbnail(
    String html, {
    ThumbSize size = thumbnailSize,
  }) async {
    if (!await File(html).exists()) return null;
    final png = await cachePath(html, size: size);
    if (await File(png).exists()) return png;
    final browser = await findBrowser();
    if (browser == null) return null;
    await Directory(cacheDir).create(recursive: true);
    try {
      final r = await run(
        browser,
        headlessArgs(
          html: html,
          png: png,
          profileDir: '$cacheDir/profile',
          size: size,
        ),
      ).timeout(const Duration(seconds: 60));
      if (r.exitCode != 0) debugPrint('headless ${r.exitCode}: ${r.stderr}');
    } catch (e) {
      debugPrint('headless: $e');
      return null;
    }
    return await File(png).exists() ? png : null;
  }
}

final prototypeThumbnailsProvider = Provider<PrototypeThumbnails>(
  (ref) => PrototypeThumbnails(
    run: ref.watch(processRunnerProvider),
    cacheDir: ref.watch(prototypeCacheDirProvider),
  ),
);
