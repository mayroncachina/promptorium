import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_registry.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_icon.dart';
import '../sessions/session_manager.dart' show PendingApproval;
import '../sessions/timeline.dart';
import '../sessions/widgets/session_style.dart';
import '../sessions/widgets/side_panel.dart' show ApprovalCard;
import '../sessions/widgets/timeline_view.dart';
import 'attachments.dart';
import 'conversation_manager.dart';
import 'plan_ready.dart';
import 'prompt_actions.dart';
import 'spec_from_answer.dart';
import 'widgets/answer_spec_bar.dart';
import 'widgets/conversation_list.dart';
import 'widgets/prompt_composer.dart';
import 'widgets/prompt_dialogs.dart';
import 'widgets/prompt_side_panel.dart';

/// Prompt screen (docs/mockups/Prompt.dc.html): conversation history ·
/// conversation + composer · context and saved prompts. Conversations run in
/// the workspace root, without a worktree (plano, Fase 6).
class PromptScreen extends ConsumerStatefulWidget {
  const PromptScreen({super.key});

  @override
  ConsumerState<PromptScreen> createState() => _PromptScreenState();
}

class _PromptScreenState extends ConsumerState<PromptScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  /// `@files` attached to the message being written.
  final List<String> _attached = [];

  /// Files picked or dropped (absolute paths) for the message.
  final List<String> _files = [];
  bool _dropping = false;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addFiles(Iterable<String> paths) {
    setState(() {
      for (final p in paths) {
        if (!_files.contains(p)) _files.add(p);
      }
    });
  }

  Future<void> _pickFiles(Workspace? ws) async {
    final picked = await ref.read(filePickerProvider)(
      initialDirectory: ws?.path,
    );
    if (picked.isNotEmpty && mounted) _addFiles(picked);
  }

  Future<void> _send(Workspace? ws, Conversation? conv) async {
    final msg = _text.text.trim();
    if (msg.isEmpty || _sending) return;
    if (ws == null) {
      _snack('Selecione um workspace na barra de título.');
      return;
    }
    final manager = ref.read(conversationManagerProvider.notifier);
    setState(() => _sending = true);
    _text.clear();
    final attached = List.of(_attached);
    _attached.clear();
    final files = List.of(_files);
    _files.clear();
    try {
      final prepared = await prepareAttachments(ws.path, files);
      final text = prepared.applyTo(msg);
      if (conv == null) {
        final d = ref.read(promptDraftProvider);
        final id = await manager.create(
          workspace: ws,
          text: text,
          mode: d.mode,
          model: d.model,
          providerId: d.providerId,
          images: prepared.images,
        );
        ref.read(selectedConversationProvider.notifier).select(id);
      } else {
        await manager.send(conv.id, text, images: prepared.images);
      }
    } catch (e) {
      if (_text.text.isEmpty) {
        _text.text = msg;
        _attached.addAll(attached);
        _files.addAll(files);
      }
      _snack('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _insertPrompt(SavedPrompt p) async {
    await insertSavedPrompt(ref, _text, p);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    final list = ws == null
        ? const <Conversation>[]
        : ref.watch(conversationsProvider(ws.id)).value ??
              const <Conversation>[];
    final selectedId = ref.watch(selectedConversationProvider);
    Conversation? conv;
    for (final c in list) {
      if (c.id == selectedId) conv = c;
    }
    final draft = ref.watch(promptDraftProvider);
    final providerId = conv?.provider ?? draft.providerId;
    final provider = ref.watch(agentProviderByIdProvider(providerId));
    final mode = conv == null ? draft.mode : PromptMode.fromName(conv.mode);
    final model = conv?.model ?? draft.model;
    final live = ref.watch(conversationManagerProvider);
    final busy = _sending || (conv != null && live.isBusy(conv.id));
    final items = conv == null
        ? const <TimelineItem>[]
        : ref.watch(conversationTimelineProvider(conv.id)).items;
    final files = mentionedFiles([
      for (final i in items)
        if (i is UserItem) i.text,
    ]);
    for (final a in _attached) {
      if (!files.contains(a)) files.add(a);
    }
    final manager = ref.read(conversationManagerProvider.notifier);
    final draftCtl = ref.read(promptDraftProvider.notifier);

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 1100;
        final left = narrow ? 230.0 : 260.0;
        final right = narrow ? 250.0 : 280.0;
        return ColoredBox(
          color: AppColors.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: left,
                child: ConversationListPanel(
                  conversations: list,
                  selectedId: conv?.id,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(conversation: conv, busy: busy, items: items),
                    Expanded(
                      child: conv == null
                          ? _Empty(hasWorkspace: ws != null)
                          : _Conversation(
                              key: ValueKey('conversation-main-${conv.id}'),
                              conversation: conv,
                              workspace: ws,
                              busy: busy,
                            ),
                    ),
                    DropTarget(
                      key: const ValueKey('prompt-drop'),
                      onDragEntered: (_) => setState(() => _dropping = true),
                      onDragExited: (_) => setState(() => _dropping = false),
                      onDragDone: (d) {
                        setState(() => _dropping = false);
                        _addFiles(d.files.map((f) => f.path));
                      },
                      child: PromptComposer(
                        controller: _text,
                        focusNode: _focus,
                        workspaceRoot: ws?.path,
                        files: _files,
                        dropping: _dropping,
                        onPickFiles: () => _pickFiles(ws),
                        onRemoveFile: (f) => setState(() => _files.remove(f)),
                        attachments: _attached,
                        onAttach: (p) => setState(() {
                          if (!_attached.contains(p)) _attached.add(p);
                        }),
                        onRemoveAttachment: (p) => setState(() {
                          _attached.remove(p);
                          _text.text = _text.text
                              .replaceAll('@$p ', '')
                              .replaceAll('@$p', '');
                        }),
                        provider: provider,
                        model: model,
                        mode: mode,
                        onProvider: (p) {
                          if (!p.enabled) return;
                          if (conv == null) {
                            draftCtl.set(
                              draft.copyWith(
                                providerId: p.id,
                                model: p.models.first,
                              ),
                            );
                          }
                        },
                        onModel: (m) => conv == null
                            ? draftCtl.set(draft.copyWith(model: m))
                            : manager.setModel(conv.id, m),
                        onMode: (m) => conv == null
                            ? draftCtl.set(draft.copyWith(mode: m))
                            : manager.setMode(conv.id, m),
                        busy: busy,
                        onSend: () => _send(ws, conv),
                        onStop: () {
                          if (conv != null) manager.stop(conv.id);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: right,
                child: PromptSidePanel(
                  workspace: ws,
                  conversation: conv,
                  mode: mode,
                  files: files,
                  onInsert: _insertPrompt,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.conversation,
    required this.busy,
    required this.items,
  });

  final Conversation? conversation;
  final bool busy;
  final List<TimelineItem> items;

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toSpec(BuildContext context, WidgetRef ref) async {
    final c = conversation!;
    // SPEC-016 R5: a spec written by the agent wins over the transcript.
    final written = lastAnswerSpec(items);
    if (written != null) {
      await primaryAnswerSpec(context, ref, c, written);
      return;
    }
    try {
      final ws = await ref.read(workspacesRepoProvider).getById(c.workspaceId);
      if (ws == null) throw StateError('Workspace não encontrado.');
      final spec = await createSpecFromConversation(
        ref.read(specsRepoProvider),
        workspace: ws,
        title: c.title,
        transcript: transcriptOf(items),
      );
      if (context.mounted) {
        _snack(context, '${spec.code} criada em ${spec.path} (rascunho)');
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Falha ao criar a spec: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final hasAnswer = lastAnswer(items) != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              c?.title ?? 'Nova conversa',
              key: const ValueKey('prompt-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: SmallButton(
              key: const ValueKey('prompt-to-spec'),
              label: 'Transformar em spec',
              onTap: c == null || busy || !hasAnswer
                  ? null
                  : () => _toSpec(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: SmallButton(
              key: const ValueKey('prompt-continue-session'),
              label: 'Continuar como sessão',
              onTap: c == null || busy || c.claudeSessionId == null
                  ? null
                  : () => showContinueSessionDialog(context, c),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasWorkspace});

  final bool hasWorkspace;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.prompt, size: 28, color: AppColors.amber),
            const SizedBox(height: 10),
            Text(
              hasWorkspace ? 'Nova conversa' : 'Nenhum workspace',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasWorkspace
                  ? 'Pergunte sobre o código do workspace. Roda na raiz do '
                        'repositório, sem worktree; "Perguntar" não altera '
                        'arquivos.'
                  : 'Selecione ou adicione um workspace na barra de título.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Timeline of the selected conversation, with inline approvals and the
/// actions under the last answer.
class _Conversation extends ConsumerWidget {
  const _Conversation({
    super.key,
    required this.conversation,
    required this.workspace,
    required this.busy,
  });

  final Conversation conversation;
  final Workspace? workspace;
  final bool busy;

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final snap = ref.watch(conversationTimelineProvider(c.id));
    final approvals = ref.watch(
      conversationManagerProvider.select((s) => s.approvalsOf(c.id)),
    );
    final manager = ref.read(conversationManagerProvider.notifier);
    final answer = lastAnswer(snap.items);
    final lastIsAnswer =
        snap.items.isNotEmpty && snap.items.last is! UserItem && answer != null;

    // "Plano pronto" (U4): the ExitPlanMode request becomes a card; the
    // plan is kept after it is answered.
    final planReq = planApproval(approvals);
    final drafts = ref.watch(planDraftsProvider);
    final planText = planReq == null
        ? drafts[c.id]
        : planOfRequest(planReq.request);
    if (planReq != null && planText != null && drafts[c.id] != planText) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(planDraftsProvider.notifier).set(c.id, planText),
      );
    }
    final otherApprovals = [
      for (final a in approvals)
        if (a != planReq) a,
    ];

    final footer =
        otherApprovals.isEmpty && planText == null && (busy || !lastIsAnswer)
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (planText != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: PlanReadyCard(
                      conversation: c,
                      plan: planText,
                      approval: planReq,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final PendingApproval a in otherApprovals) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ApprovalCard(
                      approval: a,
                      onOpen: () {},
                      onApprove: ({required bool always, input}) =>
                          manager.approve(
                            c.id,
                            a.requestId,
                            always: always,
                            updatedInput: input,
                          ),
                      onDeny: () => manager.deny(c.id, a.requestId),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (!busy && lastIsAnswer)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    SmallButton(
                      key: const ValueKey('answer-copy'),
                      label: 'Copiar',
                      height: 28,
                      color: AppColors.textSecondary,
                      background: Colors.transparent,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: answer));
                        if (context.mounted) {
                          _snack(context, 'Resposta copiada');
                        }
                      },
                    ),
                    SmallButton(
                      key: const ValueKey('answer-save-prompt'),
                      label: 'Salvar como prompt',
                      height: 28,
                      color: AppColors.textSecondary,
                      background: Colors.transparent,
                      onTap: () async {
                        final p = await showSavePromptDialog(
                          context,
                          body: lastUserMessage(snap.items) ?? '',
                        );
                        if (p != null && context.mounted) {
                          _snack(context, 'Prompt /${p.command} salvo');
                        }
                      },
                    ),
                  ],
                ),
            ],
          );

    return TimelineListView(
      key: ValueKey('conversation-timeline-${c.id}'),
      items: snap.items,
      loading: snap.loading,
      root: workspace?.path,
      waitingTools: {for (final a in approvals) ?a.request.toolUseId},
      footer: footer,
      maxWidth: 760,
      assistantName: 'Claude Code · ${modelLabel(c.model)}',
      emptyText: 'Sem mensagens ainda.',
      answerFooter: (item) {
        final spec = detectAnswerSpec(item.text);
        return spec == null ? null : AnswerSpecBar(conversation: c, spec: spec);
      },
    );
  }
}
