import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_registry.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_icon.dart';
import '../../ui/widgets/app_toast.dart';
import '../sessions/session_manager.dart' show PendingApproval;
import '../sessions/timeline.dart';
import '../sessions/widgets/session_style.dart';
import '../sessions/widgets/side_panel.dart' show ApprovalCard;
import '../sessions/widgets/timeline_view.dart';
import 'attachments.dart';
import 'conversation_actions.dart';
import 'conversation_manager.dart';
import 'plan_ready.dart';
import 'prompt_actions.dart';
import 'refine_changes.dart';
import 'refine_origin.dart';
import 'spec_batch.dart';
import 'spec_from_answer.dart';
import 'widgets/answer_spec_bar.dart';
import 'widgets/spec_batch_dialog.dart';
import 'widgets/conversation_list.dart';
import 'widgets/prompt_composer.dart';
import 'widgets/prompt_welcome.dart';
import 'widgets/prompt_dialogs.dart';
import 'widgets/prompt_side_panel.dart';
import 'widgets/title_field.dart';
import '../vibe/vibe_flow.dart' show vibeFlowProvider;
import '../vibe/vibe_service.dart' show vibeSpecProvider;
import '../vibe/widgets/vibe_widgets.dart';

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

  /// Width band of the last layout (below [sidePanelNarrowWidth]) and the
  /// choice of the button in it (SPEC-056 R10).
  bool? _narrow;
  bool? _panelOverride;

  bool get _storedCollapsed =>
      ref.read(appSettingsProvider)[AppSettingKeys.promptPanelCollapsed] == '1';

  bool get _panelCollapsed => sidePanelCollapsed(
    narrow: _narrow ?? false,
    stored: _storedCollapsed,
    override: _panelOverride,
  );

  /// "Recolher painel" / "Mostrar painel" (R8): stored above the narrow
  /// band; below it the choice lasts until the band changes (R10).
  void _togglePanel() {
    final next = !_panelCollapsed;
    if (_narrow ?? false) {
      setState(() => _panelOverride = next);
    } else {
      ref
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.promptPanelCollapsed, next ? '1' : '0');
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(msg)));
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
      } else if (conv.specId != null) {
        // SPEC-069 R5, R8: the cap and the subject come first.
        await ref
            .read(vibeFlowProvider.notifier)
            .submit(conv.id, text, images: prepared.images);
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
    // The stored choice of the panel (R8).
    ref.watch(
      appSettingsProvider.select((m) => m[AppSettingKeys.promptPanelCollapsed]),
    );
    final lists = ws == null
        ? ConversationLists.empty
        : ref.watch(conversationListsProvider(ws.id));
    final selectedId = ref.watch(selectedConversationProvider);
    final conv = lists.byId(selectedId);
    // SPEC-056 R2: another conversation opened; the title being edited in
    // the header was of the previous one.
    ref.listen<int?>(selectedConversationProvider, (_, _) {
      if (ref.read(renamingProvider)?.place == RenamePlace.header) {
        ref.read(renamingProvider.notifier).stop();
      }
    });
    // SPEC-056 R7: the open conversation left the archived ones (a message
    // or "Desarquivar"): the list goes back to the active ones.
    if (ws != null) {
      ref.listen<bool?>(
        conversationListsProvider(ws.id)
            .select((l) => l.byId(selectedId)?.archivedAt != null),
        (was, now) {
          if (was == true && now == false) {
            ref
                .read(conversationTabProvider.notifier)
                .show(ConversationTab.active);
          }
        },
      );
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

    return CallbackShortcuts(
      bindings: {
        // SPEC-056 R8: collapse / show the right panel.
        sidePanelShortcut: _togglePanel,
        // SPEC-056 R2: F2 renames the open conversation.
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (conv != null) {
            ref
                .read(renamingProvider.notifier)
                .start(conv.id, RenamePlace.header);
          }
        },
      },
      // Holds the focus when nothing in the screen has it, so F2 and
      // Ctrl+Alt+B work right after opening the Prompt.
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < sidePanelNarrowWidth;
            // SPEC-056 R10: opening by the button holds until the band
            // changes.
            if (_narrow != narrow) {
              _narrow = narrow;
              _panelOverride = null;
            }
            final collapsed = _panelCollapsed;
            final left = narrow ? 230.0 : 260.0;
            final right = collapsed ? sideStripWidth : (narrow ? 250.0 : 280.0);
            return ColoredBox(
              color: AppColors.background,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: left,
                    child: ConversationListPanel(
                      lists: lists,
                      selectedId: conv?.id,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          conversation: conv,
                          busy: busy,
                          items: items,
                          active: lists.active,
                        ),
                        if (conv != null && conv.archivedAt != null)
                          ArchivedBanner(
                            onUnarchive: () => ref
                                .read(conversationActionsProvider)
                                .unarchive(conv.id),
                          ),
                        Expanded(
                          child: conv == null
                              ? ws == null
                                    ? const _Empty()
                                    // SPEC-055 R7: the three modes, in plain words.
                                    : PromptWelcome(
                                        mode: mode,
                                        onPickMode: (m) => draftCtl.set(
                                          draft.copyWith(mode: m),
                                        ),
                                        onExample: (m, text) {
                                          draftCtl.set(draft.copyWith(mode: m));
                                          // Only fills the field: the person
                                          // sees what goes and can adjust it.
                                          _text.value = TextEditingValue(
                                            text: text,
                                            selection: TextSelection.collapsed(
                                              offset: text.length,
                                            ),
                                          );
                                          _focus.requestFocus();
                                        },
                                      )
                              : _Conversation(
                                  key: ValueKey('conversation-main-${conv.id}'),
                                  conversation: conv,
                                  workspace: ws,
                                  busy: busy,
                                ),
                        ),
                        DropTarget(
                          key: const ValueKey('prompt-drop'),
                          onDragEntered: (_) =>
                              setState(() => _dropping = true),
                          onDragExited: (_) =>
                              setState(() => _dropping = false),
                          onDragDone: (d) {
                            setState(() => _dropping = false);
                            _addFiles(d.files.map((f) => f.path));
                          },
                          child: PromptComposer(
                            controller: _text,
                            focusNode: _focus,
                            workspaceRoot: ws?.path,
                            hintText: conv?.archivedAt != null
                                ? 'Escreva para continuar…  enviar desarquiva a '
                                      'conversa'
                                : null,
                            files: _files,
                            dropping: _dropping,
                            onPickFiles: () => _pickFiles(ws),
                            onRemoveFile: (f) =>
                                setState(() => _files.remove(f)),
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
                            // SPEC-069 R1: "Fazer como tarefa".
                            onVibe: ws == null || conv?.specId != null
                                ? null
                                : () async {
                                    final id = await showVibeStartDialog(
                                      context,
                                      workspace: ws,
                                      initial: _text.text,
                                    );
                                    if (id != null) _text.clear();
                                  },
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
                    child: collapsed
                        ? PromptSideStrip(
                            key: const ValueKey('prompt-side-strip'),
                            workspace: ws,
                            conversation: conv,
                            mode: mode,
                            files: files,
                            onInsert: _insertPrompt,
                            onExpand: _togglePanel,
                          )
                        : PromptSidePanel(
                            key: const ValueKey('prompt-side-panel'),
                            workspace: ws,
                            conversation: conv,
                            mode: mode,
                            files: files,
                            onInsert: _insertPrompt,
                            onCollapse: _togglePanel,
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.conversation,
    required this.busy,
    required this.items,
    required this.active,
  });

  final Conversation? conversation;
  final bool busy;
  final List<TimelineItem> items;

  /// Active conversations, for the selection after archiving (R4).
  final List<Conversation> active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final hasAnswer = lastAnswer(items) != null;
    final origin = c == null ? null : refineOriginOf(c);
    final backLabel = origin == null
        ? null
        : 'Voltar à spec ${origin.specCode}';
    final renaming = ref.watch(renamingProvider);
    const decoration = BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    );
    // SPEC-069 R6, R7: the conversation of a VIBE has its bar.
    if (c?.specId case final id?) {
      final spec = ref.watch(vibeSpecProvider(id)).value;
      final ws = ref.watch(activeWorkspaceProvider);
      if (spec != null) {
        return VibeBar(
          spec: spec,
          busy: busy,
          meter: ws == null || spec.worktreePath == null
              ? null
              : VibeMeter(
                  spec: spec,
                  workspacePath: ws.path,
                  // The meter follows the answers.
                  tick: c!.messageCount + (busy ? 0 : 1),
                  conversationId: c.id,
                ),
        );
      }
    }
    // SPEC-056 R2: the title becomes a field; the actions wait.
    if (c != null &&
        renaming?.id == c.id &&
        renaming?.place == RenamePlace.header) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: decoration,
        child: TitleField(
          key: ValueKey('prompt-title-field-${c.id}'),
          fieldKey: const ValueKey('title-field'),
          initial: c.title,
          onSave: (t) => ref.read(conversationActionsProvider).rename(c.id, t),
          onCancel: ref.read(renamingProvider.notifier).stop,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Flexible(
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
                if (c != null) ...[
                  const SizedBox(width: 4),
                  RowAction(
                    key: const ValueKey('prompt-rename'),
                    icon: Icons.edit_outlined,
                    tooltip: 'Renomear (F2)',
                    onPressed: () => ref
                        .read(renamingProvider.notifier)
                        .start(c.id, RenamePlace.header),
                  ),
                ],
              ],
            ),
          ),
          // SPEC-021 R2 / R6 / R11: only refine conversations with a stored
          // origin; keyboard focusable, with an accessible label.
          if (backLabel != null) ...[
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: SmallButton(
                key: const ValueKey('prompt-back-to-spec'),
                label: backLabel,
                semanticLabel: backLabel,
                focusColor: AppColors.amber.withValues(alpha: 0.25),
                onTap: () => backToSpec(context, ref, c!),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: SmallButton(
              key: const ValueKey('prompt-to-spec'),
              label: 'Transformar em spec',
              onTap: c == null || busy || !hasAnswer
                  ? null
                  : () => conversationToSpec(context, ref, c, items),
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
          // SPEC-056 R1: the same menu as the right click on the row.
          if (c != null) ...[
            const SizedBox(width: 6),
            Builder(
              builder: (context) => RowAction(
                key: const ValueKey('prompt-more'),
                icon: Icons.more_horiz,
                tooltip: 'Mais ações da conversa',
                onPressed: () => showConversationMenu(
                  context,
                  ref,
                  c: c,
                  position: menuPositionBelow(context),
                  active: active,
                  renameIn: RenamePlace.header,
                  items: items,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Prompt without a workspace (with one, [PromptWelcome]).
class _Empty extends StatelessWidget {
  const _Empty();

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
            const Text(
              'Nenhum workspace',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Selecione ou adicione um workspace na barra de título.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
      ..showAppToast(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final snap = ref.watch(conversationTimelineProvider(c.id));
    final approvals = ref.watch(
      conversationManagerProvider.select((s) => s.approvalsOf(c.id)),
    );
    final manager = ref.read(conversationManagerProvider.notifier);
    // SPEC-026: edits of a refine conversation on its spec.
    final progress = ref.watch(refineProgressProvider(c.id));
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

    // SPEC-069 R5, R8: a request of a VIBE waiting for a choice.
    final pending = ref.watch(vibeFlowProvider.select((m) => m[c.id]));
    final vibe = c.specId == null
        ? null
        : ref.watch(vibeSpecProvider(c.specId!)).value;
    final question = pending == null || vibe == null || workspace == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: VibeQuestion(
              key: ValueKey('vibe-question-${c.id}-${pending.ask.name}'),
              conversationId: c.id,
              spec: vibe,
              pending: pending,
              workspace: workspace!,
            ),
          );
    final footer =
        question == null &&
            otherApprovals.isEmpty &&
            planText == null &&
            (busy || !lastIsAnswer)
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (question != null) ...[
                if (pending!.text.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      key: const ValueKey('vibe-held-request'),
                      constraints: const BoxConstraints(maxWidth: 520),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.amberTint,
                        border: Border.all(color: SessionColors.approvalBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        pending.text,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                question,
                const SizedBox(height: 8),
              ],
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
                      edit: progress?.approvalInfo(a.request),
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
              if (!busy &&
                  lastIsAnswer &&
                  progress != null &&
                  appliedInLastTurn(snap.items, progress) > 0) ...[
                RefineSummaryCard(conversation: c, progress: progress),
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
      editInfo: progress == null ? null : (t) => progress.edits[t.id],
      answerFooter: (item) {
        final specs = detectAnswerSpecs(item.text);
        if (specs.isEmpty) return null;
        if (specs.length == 1) {
          return AnswerSpecBar(conversation: c, spec: specs.single);
        }
        final answer = finishedAnswers(snap.items).indexOf(item);
        return AnswerSpecsBar(
          conversation: c,
          items: [
            for (var i = 0; i < specs.length; i++)
              SpecBatchItem.of(i, specs[i]),
          ],
          answer: answer < 0 ? null : answer,
        );
      },
    );
  }
}
