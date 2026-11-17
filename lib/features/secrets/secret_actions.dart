import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../core/secrets/secret_scanner.dart';
import '../../data/providers.dart';
import '../../data/repos/secret_waivers_repo.dart';
import '../sessions/session_manager.dart';
import '../sessions/timeline.dart';
import '../sessions/widgets/tool_expanded_view.dart' show openInCodeProvider;
import 'secret_blocks.dart';

/// Environment variable suggested to the agent when it takes a secret out
/// of the code (SPEC-085 R9).
String secretEnvName(SecretFinding f) {
  final known = switch (f.ruleId) {
    'stripe' => 'STRIPE_SECRET',
    'aws' => 'AWS_ACCESS_KEY_ID',
    'github' => 'GITHUB_TOKEN',
    'gitlab' => 'GITLAB_TOKEN',
    'slack' => 'SLACK_TOKEN',
    'google' => 'GOOGLE_API_KEY',
    'anthropic' => 'ANTHROPIC_API_KEY',
    'openai' => 'OPENAI_API_KEY',
    'jwt' => 'JWT_TOKEN',
    'url-password' => 'DATABASE_URL',
    'private-key' => 'PRIVATE_KEY',
    _ => null,
  };
  if (known != null) return known;
  final m = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*[:=]')
      .firstMatch(f.maskedLine ?? '');
  final name = m?.group(1);
  if (name == null) return 'SECRET';
  return name
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toUpperCase();
}

/// "Tire o segredo de src/config/pagamento.ts:12 e leia de uma variável de
/// ambiente (`STRIPE_SECRET`); depois repita o commit." (R9).
String secretRemovalMessage(SecretFinding f) =>
    'Tire o segredo de ${f.where} e leia de uma variável de ambiente '
    '(`${secretEnvName(f)}`); depois repita o commit.';

/// Sent when every finding of a block was handled without asking the agent
/// to change code (R9).
const secretsResolvedMessage =
    'Os achados foram resolvidos; pode repetir o commit.';

/// "Ignorado: Stripe live key em pagamento.ts:12 — chave de teste…" (R11).
String secretIgnoredNote(SecretFinding f, String reason) {
  final where = f.line == null ? f.fileName : '${f.fileName}:${f.line}';
  final r = reason.trim();
  final short = r.length > 60 ? '${r.substring(0, 60)}…' : r;
  return 'Ignorado: ${f.ruleName} em $where — $short';
}

/// The actions on findings (R9, R11), shared by the session's card, the
/// window of the app and the Código.
class SecretActions {
  SecretActions(this._ref);

  final Ref _ref;

  /// "Remover" of a sensitive file: out of the index (`git rm --cached`),
  /// into `.gitignore`; the file stays on disk.
  Future<void> untrackFile(String worktree, String path) async {
    final git = _ref.read(gitServiceFactoryProvider)(worktree);
    try {
      await git.git(['rm', '--cached', '-q', '--ignore-unmatch', '--', path]);
    } on GitException catch (e) {
      debugPrint('vigia: $path não saiu do índice — $e');
    }
    final ignore = File('$worktree/.gitignore');
    final entry = '/$path';
    final text = ignore.existsSync() ? ignore.readAsStringSync() : '';
    final lines = text.split('\n').map((l) => l.trim()).toSet();
    if (lines.contains(entry) || lines.contains(path)) return;
    final sep = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    await ignore.writeAsString('$text$sep$entry\n');
  }

  /// "Ignorar com justificativa…" (R11): records the waiver and updates the
  /// hooks of the workspace's live sessions.
  Future<void> waive({
    required int workspaceId,
    required SecretFinding finding,
    required String reason,
    required bool byValue,
    required String origin,
  }) async {
    await _ref
        .read(secretWaiversRepoProvider)
        .add(
          workspaceId: workspaceId,
          rule: finding.ruleId,
          path: finding.path,
          fingerprint: finding.fingerprint,
          scope: byValue ? SecretWaiverScope.value : SecretWaiverScope.file,
          reason: reason,
          origin: origin,
        );
    await _ref
        .read(sessionManagerProvider.notifier)
        .refreshSecrets(workspaceId);
  }

  /// "Abrir o arquivo": the Código screen at the finding's line; returns why
  /// it could not, or null.
  Future<String?> open(String worktree, SecretFinding f) =>
      _ref.read(openInCodeProvider)(worktree, f.path, f.line ?? 1);

  // --- the card of a session ---------------------------------------------

  Future<Session?> _session(String id) =>
      _ref.read(sessionsRepoProvider).getById(id);

  Future<void> _resolve(
    String sessionId,
    SecretBlockItem block,
    SecretFinding f,
    String how, {
    String? text,
  }) async {
    final manager = _ref.read(sessionManagerProvider.notifier);
    await manager.appendSecretEvent(
      sessionId,
      AppEventTypes.secretResolvedEvent(
        block: block.block,
        finding: f.fingerprint,
        path: f.path,
        how: how,
        text: text,
      ),
    );
    // The timeline's item is updated by the reducer; mirror it here so the
    // check below does not depend on the provider's snapshot.
    block.resolved[SecretBlockItem.keyOf(f)] = how;
    if (block.done) await _finish(sessionId, block);
  }

  Future<void> _finish(String sessionId, SecretBlockItem block) async {
    final asks = [
      for (final f in block.findings)
        if (block.resolution(f) == 'pedido') secretRemovalMessage(f),
    ];
    await _ref
        .read(sessionManagerProvider.notifier)
        .notifyAgent(
          sessionId,
          asks.isEmpty ? secretsResolvedMessage : asks.join('\n'),
          resume: true,
        );
    _ref
        .read(secretBlocksProvider.notifier)
        .remove(sessionSecretKey(sessionId));
  }

  /// "Remover" on the card (R9): a sensitive file leaves the index; a
  /// secret in the code is asked to the agent.
  Future<void> removeInSession(
    String sessionId,
    SecretBlockItem block,
    SecretFinding f,
  ) async {
    if (block.resolution(f) != null) return;
    final s = await _session(sessionId);
    if (s == null) return;
    if (f.isFile) {
      await untrackFile(s.worktreePath, f.path);
      await _resolve(
        sessionId,
        block,
        f,
        'removido',
        text:
            'Removido do commit: ${f.path} (no .gitignore, o arquivo ficou no disco)',
      );
    } else {
      await _resolve(
        sessionId,
        block,
        f,
        'pedido',
        text: 'Pedido ao agente: tirar o segredo de ${f.where}',
      );
    }
  }

  /// "Remover todos" on the card.
  Future<void> removeAllInSession(
    String sessionId,
    SecretBlockItem block,
  ) async {
    for (final f in block.open) {
      await removeInSession(sessionId, block, f);
    }
  }

  /// "Ignorar com justificativa…" on the card, once the window confirmed.
  Future<void> ignoreInSession(
    String sessionId,
    SecretBlockItem block,
    SecretFinding f, {
    required String reason,
    required bool byValue,
  }) async {
    if (block.resolution(f) != null) return;
    final s = await _session(sessionId);
    if (s == null) return;
    await waive(
      workspaceId: s.workspaceId,
      finding: f,
      reason: reason,
      byValue: byValue,
      origin: 'sessao:$sessionId',
    );
    await _resolve(
      sessionId,
      block,
      f,
      'ignorado',
      text: secretIgnoredNote(f, reason),
    );
  }
}

final secretActionsProvider = Provider<SecretActions>(SecretActions.new);
