import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../prompt/conversation_manager.dart';
import 'session_manager.dart';

/// SPEC-096 R15: switching the active workspace ends the idle Codex
/// processes (sessions and Prompt conversations) of the one left behind.
/// Kept alive by `main.dart`; a turn on its way keeps running.
final codexWorkspaceReleaseProvider = Provider<void>((ref) {
  ref.listen<Workspace?>(activeWorkspaceProvider, (prev, next) {
    final left = prev?.id;
    if (left == null || left == next?.id) return;
    unawaited(
      Future.wait([
        ref.read(sessionManagerProvider.notifier).releaseCodexOf(left),
        ref.read(conversationManagerProvider.notifier).releaseCodexOf(left),
      ]).catchError((Object e) {
        debugPrint('codex: processos do workspace $left não encerrados — $e');
        return const <List<Object>>[];
      }),
    );
  });
});
