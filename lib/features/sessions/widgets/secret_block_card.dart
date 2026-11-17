import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/secrets/secret_scanner.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../../ui/widgets/secret_findings_dialog.dart';
import '../../secrets/secret_actions.dart';
import '../timeline.dart';

/// The amber card of a commit, push or PR blocked by the Vigia de segredos
/// (SPEC-085 R7, R9, R10): the masked findings and their three actions.
class SecretBlockCard extends ConsumerStatefulWidget {
  const SecretBlockCard({
    super.key,
    required this.item,
    required this.sessionId,
  });

  final SecretBlockItem item;
  final String sessionId;

  @override
  ConsumerState<SecretBlockCard> createState() => _SecretBlockCardState();
}

class _SecretBlockCardState extends ConsumerState<SecretBlockCard> {
  bool _busy = false;

  SecretActions get _actions => ref.read(secretActionsProvider);

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showAppToast(SnackBar(content: Text('Não deu certo: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ignore(SecretFinding f) async {
    final s = await ref.read(sessionsRepoProvider).getById(widget.sessionId);
    if (s == null || !mounted) return;
    final ws = await ref.read(workspacesRepoProvider).getById(s.workspaceId);
    if (!mounted) return;
    final choice = await showSecretWaiverDialog(
      context,
      finding: f,
      workspaceName: ws?.name ?? 'este workspace',
    );
    if (choice == null) return;
    await _run(
      () => _actions.ignoreInSession(
        widget.sessionId,
        widget.item,
        f,
        reason: choice.reason,
        byValue: choice.byValue,
      ),
    );
  }

  Future<void> _open(SecretFinding f) async {
    final s = await ref.read(sessionsRepoProvider).getById(widget.sessionId);
    if (s == null) return;
    final why = await _actions.open(s.worktreePath, f);
    if (why != null && mounted) {
      ScaffoldMessenger.of(context).showAppToast(SnackBar(content: Text(why)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final open = item.open;
    final what = switch (item.action) {
      'push' => 'o push',
      'pr' => 'o PR',
      _ => 'o commit',
    };
    return Semantics(
      container: true,
      label:
          'Vigia de segredos bloqueou $what, ${item.findings.length} '
          '${item.findings.length == 1 ? 'achado' : 'achados'}',
      child: FocusTraversalGroup(
        child: Container(
          key: ValueKey('secret-block-${item.block}'),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SessionColors.approvalBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: item.done
                  ? AppColors.border
                  : AppColors.amber.withValues(alpha: .8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    item.done
                        ? Icons.verified_user_outlined
                        : Icons.shield_outlined,
                    size: 16,
                    color: item.done ? AppColors.teal : AppColors.amber,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Vigia de segredos bloqueou $what',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' · ${item.findings.length} '
                                '${item.findings.length == 1 ? 'achado' : 'achados'}'
                                '${item.done ? ' · resolvido' : ''}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  const Spacer(),
                  if (open.length > 1)
                    SecretActionButton(
                      key: ValueKey('secret-remove-all-${item.block}'),
                      label: 'Remover todos',
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => _actions.removeAllInSession(
                                widget.sessionId,
                                item,
                              ),
                            ),
                    ),
                ],
              ),
              if (item.command != null) ...[
                const SizedBox(height: 8),
                Text(
                  item.command!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (item.partial)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Diff acima de 5 MB: só os nomes dos arquivos e as chaves '
                    'privadas foram conferidos.',
                    style: TextStyle(fontSize: 12, color: AppColors.amber),
                  ),
                ),
              for (final f in item.findings)
                SecretFindingTile(
                  key: ValueKey('secret-finding-${f.path}-${f.line}'),
                  finding: f,
                  resolution: item.resolution(f),
                  onRemove: _busy
                      ? null
                      : () => _run(
                          () => _actions.removeInSession(
                            widget.sessionId,
                            item,
                            f,
                          ),
                        ),
                  onIgnore: _busy ? null : () => _ignore(f),
                  onOpen: () => _open(f),
                ),
              const SizedBox(height: 10),
              Text(
                item.done
                    ? 'Os achados foram resolvidos.'
                    : 'Os valores nunca aparecem inteiros. O agente espera a '
                          'sua decisão. Se o segredo já foi enviado, troque-o '
                          'no provedor.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The session whose timeline is shown (the card's actions need it).
class SecretSessionScope extends InheritedWidget {
  const SecretSessionScope({
    super.key,
    required this.sessionId,
    required super.child,
  });

  final String sessionId;

  static String? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SecretSessionScope>()
      ?.sessionId;

  @override
  bool updateShouldNotify(SecretSessionScope old) => old.sessionId != sessionId;
}
