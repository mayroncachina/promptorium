import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/gh_cli.dart';
import '../../core/git/gh_issues.dart';
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/app_toast.dart';
import '../sessions/widgets/session_style.dart';
import '../specs/spec_planner.dart';
import '../specs/spec_service.dart';
import '../specs/widgets/spec_header.dart' show SpecAction, SpecActionEmphasis;
import 'issue_availability.dart';
import 'issue_import.dart';
import 'issue_refine.dart';
import 'widgets/issue_badge.dart';

/// The actions of a spec linked to an issue (SPEC-074 R6, R7): refine with
/// the Claude, update with the issue and unlink.

/// The issues client of a workspace, or null without GitHub (R2).
Future<(GhIssues?, IssueAvailability)> issuesClient(
  Ref ref,
  Workspace ws,
) async {
  final a = await ref.read(issueAvailabilityProvider(ws.path).future);
  if (!a.available || a.repo == null) return (null, a);
  return (GhIssues(ref.read(ghCliFactoryProvider)(ws.path), repo: a.repo!), a);
}

/// [issuesClient] for widgets.
Future<(GhIssues?, IssueAvailability)> issuesClientOf(
  WidgetRef ref,
  Workspace ws,
) async {
  final a = await ref.read(issueAvailabilityProvider(ws.path).future);
  if (!a.available || a.repo == null) return (null, a);
  return (GhIssues(ref.read(ghCliFactoryProvider)(ws.path), repo: a.repo!), a);
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showAppToast(
      SnackBar(content: Semantics(liveRegion: true, child: Text(text))),
    );

/// The issue of [spec] now (null without GitHub or on a failure, with the
/// reason in a notice when [context] is given).
Future<GhIssue?> fetchIssueOf(
  WidgetRef ref,
  Spec spec, {
  BuildContext? context,
}) async {
  final n = spec.issueNumber;
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (n == null || ws == null) return null;
  final (client, a) = await issuesClientOf(ref, ws);
  if (client == null) {
    if (context != null && context.mounted) {
      _toast(context, a.reason ?? 'GitHub indisponível.');
    }
    return null;
  }
  try {
    return await client.view(n).timeout(const Duration(seconds: 20));
  } catch (e) {
    if (context != null && context.mounted) {
      _toast(context, 'Não deu para ler a issue #$n: $e');
    }
    return null;
  }
}

/// "Refinar requisitos com o Claude" (R6): opens the Nova spec with the text
/// of the issue in "Conte a ideia" (the Objetivo of the spec when GitHub is
/// not there); saving rewrites the same spec. Nothing is sent by itself.
Future<void> refineFromIssue(
  BuildContext context,
  WidgetRef ref,
  Spec spec,
) async {
  final n = spec.issueNumber;
  if (n == null) return;
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null) return;
  final issue = await fetchIssueOf(ref, spec);
  var text = issue == null ? '' : issueObjective(issue.body).text;
  if (text.isEmpty) {
    final file = await ref.read(specServiceProvider).read(ws, spec);
    text = file == null ? '' : SpecDocument.parse(file).objective?.trim() ?? '';
  }
  final title = issue?.title ?? spec.title;
  ref
      .read(issueRefineProvider.notifier)
      .set(
        ws.id,
        IssueRefineTarget(
          specId: spec.id,
          code: spec.code,
          issue: n,
          text: '$title\n\n$text'.trim(),
        ),
      );
  final flow = ref.read(newSpecFlowProvider.notifier);
  final moved = await ref
      .read(navigationProvider.notifier)
      .request(AppSection.specs);
  if (moved) flow.open();
}

/// "Atualizar com a issue" (R7): in a draft, the Objetivo becomes the new
/// text of the issue, with the before and after, written only on
/// confirmation. An approved spec only gets a notice.
Future<void> updateFromIssue(
  BuildContext context,
  WidgetRef ref,
  Spec spec, {
  GhIssue? issue,
}) async {
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null) return;
  if (!context.mounted) return;
  issue ??= await fetchIssueOf(ref, spec, context: context);
  if (issue == null || !context.mounted) return;
  if (spec.status != SpecStatus.draft) {
    _toast(
      context,
      issueChanged(spec, issue)
          ? 'A issue #${issue.number} mudou depois da importação. '
                '${spec.code} não é mais rascunho: confira o texto e edite a '
                'spec à mão.'
          : '${spec.code} não é mais rascunho: só um rascunho é atualizado '
                'com a issue.',
    );
    return;
  }
  final service = ref.read(specServiceProvider);
  final text = await service.read(ws, spec);
  if (text == null || !context.mounted) return;
  final before = SpecDocument.parse(text).objective?.trim() ?? '';
  final next = withIssueObjective(text, issue);
  final after = SpecDocument.parse(next).objective?.trim() ?? '';
  if (after == before) {
    _toast(context, 'O Objetivo já é o texto da issue #${issue.number}.');
    await ref
        .read(specsRepoProvider)
        .update(
          spec.id,
          SpecsCompanion(issueImportedAt: Value(DateTime.now())),
        );
    return;
  }
  final ok = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('issue-update-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        'Atualizar ${spec.code} com a issue #${issue!.number}?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 640,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Side('Antes', before, textKey: 'issue-update-before'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Side('Depois', after, textKey: 'issue-update-after'),
            ),
          ],
        ),
      ),
      actions: [
        SmallButton(
          key: const ValueKey('issue-update-cancel'),
          label: 'Cancelar',
          height: 34,
          onTap: () => Navigator.of(ctx).pop(false),
        ),
        AmberButton(
          key: const ValueKey('issue-update-confirm'),
          label: 'Trocar o Objetivo',
          height: 34,
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await service.save(ws, spec, next);
  await ref
      .read(specsRepoProvider)
      .update(spec.id, SpecsCompanion(issueImportedAt: Value(DateTime.now())));
  if (context.mounted) {
    _toast(context, 'Objetivo de ${spec.code} atualizado com a issue.');
  }
}

class _Side extends StatelessWidget {
  const _Side(this.label, this.text, {required this.textKey});

  final String label;
  final String text;
  final String textKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: .6,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        constraints: const BoxConstraints(maxHeight: 320),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaisedSolid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? '(vazio)' : text,
            key: ValueKey(textKey),
            style: const TextStyle(fontSize: 12, height: 1.45),
          ),
        ),
      ),
    ],
  );
}

/// "Desligar da issue" (R7): asks, then removes `issue:` from the
/// frontmatter. The spec stays where it is.
Future<void> unlinkIssue(BuildContext context, WidgetRef ref, Spec spec) async {
  final n = spec.issueNumber;
  if (n == null) return;
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null || !context.mounted) return;
  final ok = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('issue-unlink-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        'Desligar ${spec.code} da issue #$n?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: const SizedBox(
        width: 400,
        child: Text(
          'O issue: sai do cabeçalho da spec e o selo some. A issue continua '
          'no GitHub, e o PR desta spec não vai mais fechá-la.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
      ),
      actions: [
        SmallButton(
          key: const ValueKey('issue-unlink-cancel'),
          label: 'Cancelar',
          height: 34,
          onTap: () => Navigator.of(ctx).pop(false),
        ),
        AmberButton(
          key: const ValueKey('issue-unlink-confirm'),
          label: 'Desligar',
          height: 34,
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final service = ref.read(specServiceProvider);
  final text = await service.read(ws, spec);
  if (text == null) return;
  await service.save(ws, spec, SpecDocument.parse(text).withIssue(null));
  await ref
      .read(specsRepoProvider)
      .update(spec.id, const SpecsCompanion(issueImportedAt: Value(null)));
  if (context.mounted) _toast(context, '${spec.code} desligada da issue #$n.');
}

/// The items of the menu of a linked spec (R6, R7), for a `PopupMenu`.
/// [changed]: the issue was edited after the import ("texto mudou").
List<PopupMenuEntry<String>> issueMenuItems(Spec spec, {bool changed = false}) {
  final n = spec.issueNumber;
  if (n == null) return const [];
  PopupMenuItem<String> item(
    String value,
    IconData icon,
    String label, {
    String? trailing,
  }) => PopupMenuItem(
    value: value,
    key: ValueKey('issue-menu-$value-${spec.code}'),
    height: 36,
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          Text(
            trailing,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ],
    ),
  );
  return [
    item('open', Icons.open_in_new, 'Abrir a issue #$n', trailing: 'GitHub'),
    item(
      'refine',
      Icons.auto_awesome_outlined,
      'Refinar requisitos com o Claude',
    ),
    item(
      'update',
      Icons.sync,
      'Atualizar com a issue',
      trailing: changed ? 'texto mudou' : null,
    ),
    const PopupMenuDivider(),
    item('unlink', Icons.link_off, 'Desligar da issue'),
  ];
}

/// Runs the [issueMenuItems] item [value].
Future<void> runIssueMenu(
  BuildContext context,
  WidgetRef ref,
  Spec spec,
  String value, {
  GhIssue? issue,
}) async {
  switch (value) {
    case 'open':
      await openIssue(context, ref, spec.workspaceId, spec.issueNumber!);
    case 'refine':
      await refineFromIssue(context, ref, spec);
    case 'update':
      await updateFromIssue(context, ref, spec, issue: issue);
    case 'unlink':
      await unlinkIssue(context, ref, spec);
  }
}

/// The "…" of a linked spec on the Bandeja (R6, R7): before the menu opens,
/// the app asks GitHub whether the issue changed ("texto mudou").
class IssueMenuButton extends ConsumerStatefulWidget {
  const IssueMenuButton({super.key, required this.spec, this.extra = const []});

  final Spec spec;

  /// More items after the issue ones (value → label).
  final List<(String, String, VoidCallback)> extra;

  @override
  ConsumerState<IssueMenuButton> createState() => _IssueMenuButtonState();
}

class _IssueMenuButtonState extends ConsumerState<IssueMenuButton> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    final spec = widget.spec;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    setState(() => _busy = true);
    GhIssue? issue;
    if (spec.issueNumber != null) {
      issue = await fetchIssueOf(
        ref,
        spec,
      ).timeout(const Duration(seconds: 4), onTimeout: () => null);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final value = await showMenu<String>(
      context: context,
      position: position,
      color: AppColors.panelSolid,
      items: [
        ...issueMenuItems(
          spec,
          changed: issue != null && issueChanged(spec, issue),
        ),
        if (widget.extra.isNotEmpty && spec.issueNumber != null)
          const PopupMenuDivider(),
        for (final (v, label, _) in widget.extra)
          PopupMenuItem(
            value: v,
            key: ValueKey('issue-menu-$v-${spec.code}'),
            height: 36,
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
      ],
    );
    if (value == null || !mounted) return;
    for (final (v, _, run) in widget.extra) {
      if (v == value) return run();
    }
    await runIssueMenu(context, ref, spec, value, issue: issue);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 26,
    child: IconButton(
      key: ValueKey('issue-menu-${widget.spec.code}'),
      tooltip: 'Ações da issue',
      padding: EdgeInsets.zero,
      iconSize: 16,
      onPressed: _open,
      icon: _busy
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : const Icon(Icons.more_horiz, color: AppColors.textSecondary),
    ),
  );
}

/// The "Mais ações" items of the Specs header for a linked spec (R6, R7).
List<SpecAction> specIssueActions(
  BuildContext context,
  WidgetRef ref,
  Spec spec,
) {
  final n = spec.issueNumber;
  if (n == null) return const [];
  SpecAction a(String id, String label, IconData icon, String tooltip) =>
      SpecAction(
        id: 'issue-$id',
        keyName: 'spec-issue-$id',
        label: label,
        icon: icon,
        emphasis: SpecActionEmphasis.menu,
        tooltip: tooltip,
        onTap: () => unawaited(runIssueMenu(context, ref, spec, id)),
      );
  return [
    a(
      'open',
      'Abrir a issue #$n',
      Icons.open_in_new,
      'Abre a issue no GitHub.',
    ),
    a(
      'refine',
      'Refinar requisitos com o Claude',
      Icons.auto_awesome_outlined,
      'Abre a Nova spec com o texto da issue; salvar reescreve esta spec.',
    ),
    a(
      'update',
      'Atualizar com a issue',
      Icons.sync,
      'Troca o Objetivo pelo texto atual da issue, mostrando o antes e o '
          'depois (só num rascunho).',
    ),
    a(
      'unlink',
      'Desligar da issue',
      Icons.link_off,
      'Tira o issue: do cabeçalho da spec, com confirmação.',
    ),
  ];
}
