import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mcp/app_mcp_tools.dart';
import '../../../core/providers/agent_event.dart' show PermissionRequest;
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../project/project_config.dart';
import '../../prompt/spec_from_answer.dart' show AnswerSpec;
import '../../specs/spec_lint.dart';
import '../../specs/spec_service.dart' show nextSpecCode;
import '../session_manager.dart' show PendingApproval, slugify;
import 'session_style.dart';

/// One spec of a `criar_spec` / `criar_filhas` request, as the approval card
/// shows it (SPEC-052 R4): read with the parser of SPEC-016 and `lintSpec`.
@immutable
class AgentSpecPreview {
  const AgentSpecPreview({
    required this.title,
    required this.requirements,
    required this.criteria,
    required this.dependsOn,
    required this.warnings,
  });

  final String title;
  final int requirements;
  final int criteria;
  final List<String> dependsOn;
  final List<String> warnings;

  /// `<pasta>/SPEC-NNN-<slug>.md`.
  String path(String dir, String code) {
    final slug = slugify(title, maxLength: 40);
    return '$dir/$code${slug.isEmpty ? '' : '-$slug'}.md';
  }
}

/// What a write request of the app's MCP creates.
typedef AgentSpecRequest = ({String? parent, List<AgentSpecPreview> specs});

AgentSpecPreview _preview(Object? raw, List<String> extraDeps) {
  final text = '${raw ?? ''}';
  final spec = AnswerSpec(text, leftover: false);
  final deps = <String>{
    for (final d in [...extraDeps, ...spec.doc.dependsOn]) d.toUpperCase(),
  }.toList();
  return AgentSpecPreview(
    title: (spec.title ?? '').trim().isEmpty ? '(sem título)' : spec.title!,
    requirements: spec.requirements,
    criteria: spec.criteria.length,
    dependsOn: deps,
    warnings: [
      for (final w in lintSpec(text))
        // The app writes id, status and the origin itself.
        if (w.key == null) w.message,
    ],
  );
}

/// The specs [r] would create, or null when it is not `criar_spec` /
/// `criar_filhas` of the Promptorium MCP.
AgentSpecRequest? agentSpecRequest(PermissionRequest r) {
  final input = r.input;
  if (r.toolName == appMcpToolId(AppMcpToolNames.createSpec)) {
    return (
      parent: null,
      specs: [
        _preview(input['texto'], [
          for (final d in input['depende_de'] as List? ?? const []) '$d',
        ]),
      ],
    );
  }
  if (r.toolName == appMcpToolId(AppMcpToolNames.createChildren)) {
    final parent = '${input['pai'] ?? ''}'.toUpperCase();
    return (
      parent: parent,
      specs: [
        for (final f in input['filhas'] as List? ?? const [])
          _preview(f is Map ? f['texto'] : f, [parent]),
      ],
    );
  }
  return null;
}

/// Folder and number of the next spec of the active workspace (the code the
/// first spec of the request will get, if nothing else is created first).
final nextSpecSlotProvider = FutureProvider.autoDispose<({String dir, int n})?>(
  (ref) async {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) return null;
    final code = await nextSpecCode(ref.read(specsRepoProvider), ws);
    return (
      dir: ProjectConfig.loadSync(ws.path).specsDir,
      n: int.parse(code.substring(5)),
    );
  },
);

/// Approval card of `criar_spec` / `criar_filhas` (SPEC-052 R4): title,
/// requirements, criteria, lint warnings and the file of each spec. "Sempre
/// permitir" only goes as far as this session.
class AgentSpecApprovalCard extends ConsumerWidget {
  const AgentSpecApprovalCard({
    super.key,
    required this.approval,
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onDeny,
    this.onOpen,
    this.canAlways = true,
  });

  final PendingApproval approval;
  final AgentSpecRequest request;
  final bool busy;
  final void Function({required bool always}) onApprove;
  final VoidCallback onDeny;
  final VoidCallback? onOpen;

  /// The CLI offered a rule to keep (it becomes "nesta sessão").
  final bool canAlways;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = approval;
    final slot = ref.watch(nextSpecSlotProvider).value;
    final specs = request.specs;
    final parent = request.parent;
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.text,
    );
    const label = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    final title = parent == null
        ? 'O agente quer criar uma spec'
        : specs.length == 1
        ? 'O agente quer criar 1 filha da $parent'
        : 'O agente quer criar ${specs.length} filhas da $parent';
    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
    Widget spec(int i, AgentSpecPreview s) {
      final code = slot == null
          ? 'SPEC-…'
          : 'SPEC-${(slot.n + i).toString().padLeft(3, '0')}';
      return Container(
        key: ValueKey('agent-spec-$i'),
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Título', style: label),
            Text(
              s.title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text('Arquivo', style: label),
            Text(
              s.path(slot?.dir ?? ProjectConfig.defaultSpecsDir, code),
              key: ValueKey('agent-spec-path-$i'),
              style: mono.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${s.requirements} '
                  '${s.requirements == 1 ? 'requisito' : 'requisitos'}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '${s.criteria} ${s.criteria == 1 ? 'critério' : 'critérios'}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (s.dependsOn.isNotEmpty)
                  Text(
                    'depende de ${s.dependsOn.join(', ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                chip('status: rascunho'),
                chip('origem: agente'),
              ],
            ),
            if (s.warnings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                key: ValueKey('agent-spec-lint-$i'),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SessionColors.approvalBorder),
                ),
                child: Text(
                  '${s.warnings.length == 1 ? '1 aviso do lint' : '${s.warnings.length} avisos do lint'}: '
                  '${s.warnings.join('; ')}',
                  style: const TextStyle(fontSize: 12, color: AppColors.amber),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      key: ValueKey('approval-${a.requestId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.approvalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Text(
              a.sessionTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            key: ValueKey('approval-title-${a.requestId}'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          Text(
            a.request.toolName,
            style: mono.copyWith(fontSize: 11, color: AppColors.textSecondary),
          ),
          for (final (i, s) in specs.indexed) spec(i, s),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              SmallButton(
                key: ValueKey('deny-${a.requestId}'),
                label: 'Negar',
                height: 34,
                color: AppColors.red,
                onTap: busy ? null : onDeny,
              ),
              if (canAlways)
                SmallButton(
                  key: ValueKey('always-${a.requestId}'),
                  label: 'Sempre permitir nesta sessão',
                  height: 34,
                  onTap: busy ? null : () => onApprove(always: true),
                ),
              AmberButton(
                key: ValueKey('approve-${a.requestId}'),
                label: 'Aprovar',
                height: 34,
                onTap: busy ? null : () => onApprove(always: false),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Criar spec sempre pede aprovação no projeto.',
            textAlign: TextAlign.end,
            style: label,
          ),
        ],
      ),
    );
  }
}
