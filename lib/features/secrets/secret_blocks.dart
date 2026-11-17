import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/secrets/secret_scanner.dart';

/// A request "Segredo encontrado" (SPEC-085 R5, R7): a commit, push or PR
/// stopped by the Vigia de segredos that waits for the person. Shown in
/// Início, in Atividades, on the session and on the card of the Quadro.
@immutable
class PendingSecret {
  const PendingSecret({
    required this.key,
    required this.workspaceId,
    required this.title,
    required this.findings,
    required this.at,
    this.sessionId,
    this.specId,
    this.action = 'commit',
    this.worktree,
  });

  /// `session:<id>`, `app:<worktree>`.
  final String key;
  final int workspaceId;
  final String? sessionId;
  final int? specId;

  /// "SPEC-031 · Pagamento com Stripe", the session's title…
  final String title;
  final List<SecretFinding> findings;
  final DateTime at;

  /// `commit`, `push` or `pr`.
  final String action;

  /// Worktree of a commit / push of the app (null for a session).
  final String? worktree;

  int get count => findings.length;

  /// "commit bloqueado · 2 achados".
  String get detail {
    final what = switch (action) {
      'push' => 'push bloqueado',
      'pr' => 'PR bloqueado',
      _ => 'commit bloqueado',
    };
    return '$what · $count ${count == 1 ? 'achado' : 'achados'}';
  }
}

/// The open requests "Segredo encontrado", by [PendingSecret.key]. Kept for
/// the app session: the card stays in the session's timeline.
class SecretBlocks extends Notifier<Map<String, PendingSecret>> {
  @override
  Map<String, PendingSecret> build() => const {};

  void add(PendingSecret p) => state = {...state, p.key: p};

  void remove(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }

  PendingSecret? ofSession(String id) => state['session:$id'];
}

final secretBlocksProvider =
    NotifierProvider<SecretBlocks, Map<String, PendingSecret>>(
      SecretBlocks.new,
    );

String sessionSecretKey(String sessionId) => 'session:$sessionId';
String appSecretKey(String worktree) => 'app:$worktree';
