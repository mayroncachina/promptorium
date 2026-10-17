import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart' show PermissionRequest;
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/new_session_dialog.dart';
import '../sessions/session_manager.dart' show PendingApproval, slugify;
import '../sessions/widgets/session_style.dart';
import '../specs/spec_service.dart' show selectedSpecProvider;
import 'conversation_manager.dart';
import 'prompt_actions.dart';

/// "Plano pronto" of the Planejar mode (UX v2, U4; DT-26).
///
/// In `--permission-mode plan` the CLI writes the plan and asks for
/// `ExitPlanMode`; approving it would let the conversation edit files. The
/// app never approves it: the plan is shown as a card and the user decides
/// where to implement it (a session, a spec) or keeps planning. Every choice
/// denies the request with a message the model understands.

/// Plan text of an `ExitPlanMode` request (null for other tools).
String? planOfRequest(PermissionRequest r) {
  if (r.toolName != 'ExitPlanMode') return null;
  final p = r.input['plan'];
  if (p is String && p.trim().isNotEmpty) return p;
  return r.description?.trim().isNotEmpty ?? false ? r.description : '';
}

/// Pending `ExitPlanMode` of [approvals] (null = none).
PendingApproval? planApproval(List<PendingApproval> approvals) {
  for (final a in approvals) {
    if (a.request.toolName == 'ExitPlanMode') return a;
  }
  return null;
}

/// `3 etapas · 4 arquivos` from the markdown (numbered items and `path`
/// mentions), best effort.
String planSummary(String plan) {
  final steps = RegExp(
    r'^\s*(?:\d+[.)]|[-*])\s+\S',
    multiLine: true,
  ).allMatches(plan).length;
  final files = RegExp(r'`([^`\s]+\.[a-z]{1,6})`')
      .allMatches(plan)
      .map((m) => m.group(1))
      .toSet()
      .length;
  return [
    if (steps > 0) steps == 1 ? '1 item' : '$steps itens',
    if (files > 0) files == 1 ? '1 arquivo' : '$files arquivos',
  ].join(' · ');
}

const _denyForSession =
    'Plano aprovado no Promptorium: a implementação será feita numa sessão '
    'própria, não nesta conversa. Não edite arquivos; responda só "ok".';
const _denyForSpec =
    'Plano aprovado no Promptorium e guardado como spec. Não edite arquivos '
    'nesta conversa; responda só "ok".';
const _denyKeepPlanning =
    'Ainda não: continue planejando. Refine o plano com o que eu disser a '
    'seguir e peça para sair do modo plano de novo quando terminar.';

/// Last plan of each conversation, kept after the request is answered so
/// the card stays until the next plan arrives.
class PlanDrafts extends Notifier<Map<int, String>> {
  @override
  Map<int, String> build() => const {};

  void set(int conversationId, String plan) =>
      state = {...state, conversationId: plan};

  void clear(int conversationId) => state = {...state}..remove(conversationId);
}

final planDraftsProvider = NotifierProvider<PlanDrafts, Map<int, String>>(
  PlanDrafts.new,
);

/// Writes the plan to `.promptorium/planos/<date>-<slug>.md` (returns the
/// relative path).
Future<String> savePlanFile(
  String workspacePath,
  String title,
  String plan, {
  DateTime? now,
}) async {
  final t = now ?? DateTime.now();
  final day = t.toIso8601String().substring(0, 10);
  final slug = slugify(title, maxLength: 40);
  final base = '.promptorium/planos/$day-${slug.isEmpty ? 'plano' : slug}';
  final text = '# $title\n\n$plan\n';
  // Another plan of the same day and title gets `-2`, `-3`… (the same plan
  // saved again reuses its file).
  for (var n = 1; ; n++) {
    final rel = n == 1 ? '$base.md' : '$base-$n.md';
    final f = File('$workspacePath/$rel');
    if (await f.exists() && await f.readAsString() != text) continue;
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
    return rel;
  }
}

/// Prompt of the session that implements [plan].
String implementPrompt(String title, String plan) =>
    'Implemente o plano abaixo ("$title"), aprovado no Promptorium. Siga as '
    'etapas na ordem, rode os testes do projeto e faça commit ao terminar.\n\n'
    '$plan';

/// The card: the plan, its summary and the three ways out.
class PlanReadyCard extends ConsumerStatefulWidget {
  const PlanReadyCard({
    super.key,
    required this.conversation,
    required this.plan,
    this.approval,
  });

  final Conversation conversation;
  final String plan;

  /// Pending `ExitPlanMode` (null = already answered; the card only shows
  /// the plan and lets the user reuse it).
  final PendingApproval? approval;

  @override
  ConsumerState<PlanReadyCard> createState() => _PlanReadyCardState();
}

class _PlanReadyCardState extends ConsumerState<PlanReadyCard> {
  bool _busy = false;
  bool _open = false;

  void _snack(String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deny(String message) async {
    final a = widget.approval;
    if (a == null) return;
    await ref
        .read(conversationManagerProvider.notifier)
        .deny(widget.conversation.id, a.requestId, message: message);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Workspace> _workspace() async {
    final ws = await ref
        .read(workspacesRepoProvider)
        .getById(widget.conversation.workspaceId);
    if (ws == null) throw StateError('Workspace não encontrado.');
    return ws;
  }

  Future<void> _asSession() => _run(() async {
    final c = widget.conversation;
    final ws = await _workspace();
    await savePlanFile(ws.path, c.title, widget.plan);
    if (!mounted) return;
    // Read before the dialog: the card may be gone when it closes.
    final conversations = ref.read(conversationManagerProvider.notifier);
    final navigation = ref.read(navigationProvider.notifier);
    final a = widget.approval;
    final id = await showNewSessionDialog(
      context,
      title: c.title,
      prompt: implementPrompt(c.title, widget.plan),
    );
    // Cancelled: the plan stays pending (nothing told to the model yet).
    if (id == null) return;
    if (a != null) {
      await conversations.deny(c.id, a.requestId, message: _denyForSession);
    }
    navigation.go(AppSection.sessions);
  });

  Future<void> _asSpec() => _run(() async {
    final c = widget.conversation;
    final ws = await _workspace();
    await savePlanFile(ws.path, c.title, widget.plan);
    final spec = await createSpecFromConversation(
      ref.read(specsRepoProvider),
      workspace: ws,
      title: c.title,
      transcript: [(user: false, text: widget.plan)],
    );
    await _deny(_denyForSpec);
    if (!mounted) return;
    ref.read(selectedSpecProvider.notifier).select(spec.id);
    ref.read(navigationProvider.notifier).go(AppSection.specs);
    _snack('${spec.code} criada em ${spec.path} (rascunho)');
  });

  Future<void> _keepPlanning() => _run(() async {
    await _deny(_denyKeepPlanning);
    ref.read(planDraftsProvider.notifier).clear(widget.conversation.id);
  });

  @override
  Widget build(BuildContext context) {
    final pending = widget.approval != null;
    final summary = planSummary(widget.plan);
    return Container(
      key: const ValueKey('plan-ready'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SessionColors.approvalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('plan-ready-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Dot(pending ? AppColors.amber : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    pending ? 'Plano pronto' : 'Último plano',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '· $summary',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          Container(
            constraints: BoxConstraints(maxHeight: _open ? 480 : 160),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SingleChildScrollView(
              child: MarkdownBody(
                data: widget.plan,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 12, color: AppColors.text),
                  listBullet: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text,
                  ),
                  code: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.amber,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: SessionColors.approvalBorder),
              ),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AmberButton(
                  key: const ValueKey('plan-as-session'),
                  label: 'Implementar como sessão',
                  onTap: _busy ? null : _asSession,
                ),
                SmallButton(
                  key: const ValueKey('plan-as-spec'),
                  label: 'Transformar em spec',
                  color: AppColors.amber,
                  border: SessionColors.approvalBorder,
                  background: Colors.transparent,
                  onTap: _busy ? null : _asSpec,
                ),
                if (pending)
                  SmallButton(
                    key: const ValueKey('plan-keep-planning'),
                    label: 'Continuar planejando',
                    background: Colors.transparent,
                    onTap: _busy ? null : _keepPlanning,
                  ),
                const Text(
                  'A conversa não vira Editar: o plano fica em '
                  '.promptorium/planos/',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
