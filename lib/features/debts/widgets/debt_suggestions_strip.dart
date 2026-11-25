import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mcp/app_mcp_tools.dart' show DebtSuggestionKeys;
import '../../../data/providers.dart';
import '../../../data/repos/debt_links_repo.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../debt_actions.dart';
import '../debt_board.dart';
import '../debt_files.dart';
import '../debt_service.dart';
import '../debt_table.dart';
import 'debt_form_dialog.dart';

/// "Sugestões do agente" (R7, R11, R13): what the agent (MCP) or the
/// interview proposed. Nothing goes to the file until "Aceitar".
class DebtSuggestionsStrip extends ConsumerWidget {
  const DebtSuggestionsStrip({
    super.key,
    required this.board,
    required this.workspaceId,
  });

  final DebtBoard board;
  final int workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = board.suggestions;
    if (items.isEmpty) return const SizedBox.shrink();
    final specs = ref.watch(specsProvider(workspaceId)).value ?? const [];
    return Container(
      key: const ValueKey('debt-suggestions'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.lilac.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.lilac.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'SUGESTÕES DO AGENTE · ${items.length}',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.lilac,
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'só entram no arquivo quando você aceita',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final l in items)
            _SuggestionRow(
              link: l,
              originSpec: specs
                  .where((s) => s.id == l.originSpecId)
                  .firstOrNull,
            ),
        ],
      ),
    );
  }
}

/// Label of an MCP suggestion: "Codex · MCP", "Claude · MCP" (R11).
String suggestionProviderLabel(String provider) => switch (provider) {
  'codex' => 'Codex · MCP',
  'claude' => 'Claude · MCP',
  _ => 'MCP',
};

class _SuggestionRow extends ConsumerWidget {
  const _SuggestionRow({required this.link, this.originSpec});

  final DebtLink link;
  final Spec? originSpec;

  DebtDraft get _draft => DebtDraft.fromJson(
    DebtLinksRepo.suggestionOf(link),
    kind: DebtKind.fromDb(link.kind),
  );

  Map<String, Object?> get _body => DebtLinksRepo.suggestionOf(link);

  /// "Codex · MCP" / "Claude · MCP" (R11): the provider the MCP saved.
  String get _source => switch (link.suggestionSource) {
    DebtSuggestionSource.mcp => suggestionProviderLabel(
      '${_body[DebtSuggestionKeys.provider] ?? ''}',
    ),
    DebtSuggestionSource.draft => 'Rascunho',
    _ => 'Entrevista',
  };

  /// The worktree of the origin spec, while open (R18).
  String? get _writeRoot {
    final s = originSpec;
    final wt = s?.worktreePath;
    if (s == null || wt == null || s.stage == SpecStage.done) return null;
    return Directory(wt).existsSync() ? wt : null;
  }

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref, {
    DebtDraft? edited,
  }) async {
    final service = ref.read(debtServiceProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final kind = DebtKind.fromDb(link.kind);
    final rel = DebtFiles.relPath(service.configOf(link.repoRoot), kind);
    final writeRoot = _writeRoot;
    var dirty = false;
    if (writeRoot == null) {
      try {
        dirty = await service.isDirty(link.repoRoot, rel);
      } catch (_) {}
    }
    final DebtWritten w;
    try {
      w = await service.accept(link.id, edited: edited, writeRoot: writeRoot);
    } catch (e) {
      messenger?.showAppToast(
        SnackBar(content: Text('Não deu para gravar: $e')),
      );
      return;
    }
    if (writeRoot != null || !context.mounted) {
      messenger?.showAppToast(
        SnackBar(content: Text('${w.code} gravado na worktree da spec.')),
      );
      return;
    }
    await askOwnCommit(
      context,
      ref,
      repoRoot: link.repoRoot,
      written: w,
      title: (edited ?? _draft).title,
      wasDirty: dirty,
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final edited = await showAppDialog<DebtDraft>(
      context: context,
      builder: (_) =>
          DebtFormDialog(initial: _draft, saveLabel: 'Aceitar e gravar'),
    );
    if (edited == null || !context.mounted) return;
    await _accept(context, ref, edited: edited);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = _draft;
    final where = d.where;
    final session = '${_body[DebtSuggestionKeys.sessionTitle] ?? ''}'.trim();
    final origin = [
      if (originSpec != null)
        '${specLabel(originSpec!)}${link.originQuestion == null ? '' : ', ${link.originQuestion}'}',
      if (session.isNotEmpty)
        'sessão “$session”'
      else if (link.originSessionId != null && originSpec == null)
        'sessão',
      if (d.origin.isNotEmpty && originSpec == null) d.origin,
    ].join(' · ');
    return Padding(
      key: ValueKey('debt-suggestion-${link.id}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.lilac.withValues(alpha: .5)),
            ),
            child: Text(
              link.kind == DebtKind.decision.dbName ? '$_source · DP' : _source,
              style: const TextStyle(fontSize: 11, color: AppColors.lilac),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: d.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (where.isNotEmpty)
                    TextSpan(
                      text: '  ·  $where',
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (origin.isNotEmpty)
                    TextSpan(
                      text: '  $origin',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          SmallButton(
            key: ValueKey('debt-suggestion-accept-${link.id}'),
            label: 'Aceitar',
            height: 26,
            color: AppColors.teal,
            border: ReviewColors.acceptBorder,
            background: ReviewColors.acceptBg,
            onTap: () => _accept(context, ref),
          ),
          const SizedBox(width: 6),
          SmallButton(
            key: ValueKey('debt-suggestion-edit-${link.id}'),
            label: 'Editar',
            height: 26,
            onTap: () => _edit(context, ref),
          ),
          const SizedBox(width: 6),
          SmallButton(
            key: ValueKey('debt-suggestion-discard-${link.id}'),
            label: 'Descartar',
            height: 26,
            onTap: () => ref.read(debtServiceProvider).discard(link.id),
          ),
        ],
      ),
    );
  }
}
