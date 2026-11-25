import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/codex/codex_cli.dart';
import '../../core/codex/codex_thread_ops.dart';
import '../../core/providers/agent_provider.dart' show AgentUnavailable;
import '../../core/update/update_check.dart' show appVersionProvider;
import '../../data/providers.dart';
import 'session_manager.dart';

/// Limit of each App Server request of a thread operation (SPEC-110).
final codexThreadTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 10),
);

/// The Codex conversation of a session without a turn (SPEC-110): through
/// the live process of the session (only it may write its thread) or a
/// short-lived App Server. Nothing here calls the model nor touches
/// `~/.codex/sessions`.
class CodexConversations {
  CodexConversations(this._ref);

  final Ref _ref;

  /// Runs [job] over the connection of the live process of [s], or a
  /// short-lived one. [live] tells which. [loadsThread] = the job resumes
  /// or forks the thread.
  Future<T> run<T>(
    Session s,
    Future<T> Function(CodexThreadOps ops, {required bool live}) job, {
    bool loadsThread = false,
  }) {
    final timeout = _ref.read(codexThreadTimeoutProvider);
    final rpc = _ref.read(sessionManagerProvider.notifier).codexRpc(s.id);
    if (rpc != null) {
      return job(CodexThreadOps.of(rpc, timeout: timeout), live: true);
    }
    return runShort(
      (ops) => job(ops, live: false),
      cwd: s.worktreePath,
      loadsThread: loadsThread,
    );
  }

  /// [run] always over a short-lived App Server.
  Future<T> runShort<T>(
    Future<T> Function(CodexThreadOps ops) job, {
    String? cwd,
    bool loadsThread = false,
  }) async {
    final starter = _ref.read(codexProcessStarterProvider);
    // The tests never start the real App Server.
    if (starter == null && Platform.environment['FLUTTER_TEST'] == 'true') {
      throw const AgentUnavailable('Codex CLI não encontrado');
    }
    return withCodexThreadOps(
      job,
      executable: _ref.read(codexExecutableProvider),
      starter: starter,
      cwd: cwd,
      clientVersion: _ref.read(appVersionProvider).value ?? '0.0.0',
      loadsThread: loadsThread,
      timeout: _ref.read(codexThreadTimeoutProvider),
    );
  }

  /// "Buscar a saída completa" (R4): the saved output of [itemId], from the
  /// session's thread or, when the turn left it, from one of its [copies].
  /// Throws a message in words when nothing has it.
  Future<String> itemOutput(
    Session s, {
    required String turnId,
    required String itemId,
    List<String> copies = const [],
  }) async {
    final threads = [
      ?s.externalId,
      for (final c in copies)
        if (c != s.externalId) c,
    ];
    if (threads.isEmpty) {
      throw const AgentUnavailable('A sessão não tem uma conversa do Codex.');
    }
    Object? failure;
    final out = await run(s, (ops, {required live}) async {
      for (final t in threads) {
        try {
          final text = await ops.itemOutput(t, turnId, itemId);
          if (text != null) return text;
        } catch (e) {
          failure ??= e;
        }
      }
      return null;
    });
    if (out != null) return out;
    if (failure != null) throw AgentUnavailable(codexThreadFailure(failure!));
    throw const AgentUnavailable('O Codex não guardou a saída deste comando.');
  }
}

final codexConversationsProvider = Provider<CodexConversations>(
  CodexConversations.new,
);
