import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dev/preview_browser.dart';
import 'session_manager.dart';

/// Marks the preview page: any change of its DOM (a hot reload) sets the
/// flag. A full reload clears the mark.
const previewWatchScript =
    '(function(){var w={changed:false};window.__promptoriumWatch=w;'
    'new MutationObserver(function(){w.changed=true}).observe('
    'document.documentElement,{subtree:true,childList:true,attributes:true,'
    'characterData:true});return true})()';

/// `true` when the page changed (or reloaded) since [previewWatchScript].
const previewChangedScript =
    'window.__promptoriumWatch ? window.__promptoriumWatch.changed : true';

/// R11: after the session answers a request with pointed elements, the
/// preview reloads by itself when a file changed and the page did not (a
/// server without hot reload) within [settle].
class PreviewReloader {
  PreviewReloader({
    required this.isOpen,
    required this.evaluate,
    required this.reload,
    required this.snapshot,
    required this.busy,
    this.settle = const Duration(seconds: 3),
    this.poll = const Duration(seconds: 1),
    this.maxWait = const Duration(minutes: 30),
  });

  final bool Function() isOpen;
  final Future<Object?> Function(String expression) evaluate;
  final Future<void> Function() reload;

  /// State of the worktree's files (`git status` + HEAD).
  final Future<String> Function() snapshot;

  /// The session's turn is running.
  final bool Function() busy;
  final Duration settle, poll, maxWait;

  /// Watches one turn. Returns true when it reloaded the page.
  Future<bool> run() async {
    if (!isOpen()) return false;
    try {
      final before = await snapshot();
      await evaluate(previewWatchScript);
      final end = DateTime.now().add(maxWait);
      // The turn may take a moment to start after the send.
      await Future<void>.delayed(poll);
      while (busy()) {
        if (DateTime.now().isAfter(end) || !isOpen()) return false;
        await Future<void>.delayed(poll);
      }
      if (await snapshot() == before) return false;
      await Future<void>.delayed(settle);
      if (!isOpen()) return false;
      if (await evaluate(previewChangedScript) == true) return false;
      await reload();
      return true;
    } catch (e) {
      debugPrint('preview: recarregar — $e');
      return false;
    }
  }
}

/// `git status --porcelain` and HEAD of [worktree].
Future<String> worktreeSnapshot(String worktree) async {
  final status = await Process.run('git', [
    '-C',
    worktree,
    'status',
    '--porcelain',
  ]);
  final head = await Process.run('git', ['-C', worktree, 'rev-parse', 'HEAD']);
  return '${head.stdout}\n${status.stdout}';
}

/// Starts [PreviewReloader] for the session [sessionId] in [worktree].
void watchPreviewReload(
  ProviderContainer container,
  String sessionId,
  String worktree,
) {
  final browser = container.read(previewBrowserProvider);
  unawaited(
    PreviewReloader(
      isOpen: () => browser.isOpen(worktree),
      evaluate: (e) => browser.evaluate(worktree, e),
      reload: () => browser.reload(worktree),
      snapshot: () => worktreeSnapshot(worktree),
      busy: () =>
          container.read(sessionManagerProvider).live[sessionId]?.busy ?? false,
    ).run(),
  );
}
