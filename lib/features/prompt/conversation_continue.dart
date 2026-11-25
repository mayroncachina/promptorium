import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart';
import '../../core/memory/ai_memory_cli.dart';
import '../../core/memory/ai_memory_state.dart';
import '../../core/memory/handoff.dart';
import '../../core/providers/agent_registry.dart';
import '../../core/providers/provider_preferences.dart';
import '../../data/providers.dart';
import '../../ui/providers/provider_logos.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../sessions/handoff/continue_controller.dart' show continueLabel, continueTarget;
import '../sessions/handoff/session_summary.dart' show providerWords;
import '../sessions/timeline.dart';
import '../sessions/widgets/session_style.dart';
import 'conversation_manager.dart';
import 'prompt_actions.dart';

/// Text waiting to fill the message field of the Prompt (SPEC-099 R12):
/// the field takes it and nothing is sent by itself.
class PromptTextDraft extends Notifier<String?> {
  @override
  String? build() => null;

  void put(String text) => state = text;

  String? take() {
    final t = state;
    state = null;
    return t;
  }
}

final promptTextDraftProvider = NotifierProvider<PromptTextDraft, String?>(
  PromptTextDraft.new,
);

/// The Codex runs in the Prompt (SPEC-096): only there the conversation can
/// go to the other provider (R12).
bool promptRunsIn(WidgetRef ref, String provider) =>
    ref.read(providerFlowsProvider).allows(provider, AppFlow.prompt);

/// The message of a new conversation that receives the next handoff of the
/// workspace (R12): null without ai-memory connected or without a handoff.
Future<String?> nextHandoffMessage(WidgetRef ref, String workspacePath) async {
  try {
    final d = await ref.read(aiMemoryDetectionProvider.future);
    if (!d.serverUp) return null;
    final cli = await ref.read(aiMemoryCliProvider.future);
    if (cli == null) return null;
    final list = HandoffList.parse(
      await cli.call('memory_handoff_list', const {}, cwd: workspacePath),
      workspacePath: workspacePath,
    );
    final h = list.nextDelivered;
    if (h == null) return null;
    return handoffConversationMessage(h);
  } on AiMemoryException {
    return null;
  } catch (_) {
    return null;
  }
}

/// "Continue a partir da passagem … do ai-memory" (R12, R4.4).
String handoffConversationMessage(Handoff h) =>
    'Continue a partir da passagem ${h.id} do ai-memory, deixada por '
    '${h.agentName}. Se ela não estiver no seu contexto, aceite-a com '
    'memory_handoff_accept passando handoff_id "${h.id}".';

/// Opens a new conversation of [provider] in the Prompt with [text] in the
/// field (nothing is sent, P1). The mode stays (Perguntar and Planejar are
/// read-only in both providers, decision 3).
void startConversationIn(WidgetRef ref, String provider, String? text) {
  final draft = ref.read(promptDraftProvider);
  ref.read(selectedConversationProvider.notifier).select(null);
  if (draft.providerId != provider) {
    ref
        .read(promptDraftProvider.notifier)
        .set(
          draft.copyWith(
            providerId: provider,
            model: providerModelFrom(
              ref.read(runPrefsProvider),
              ref.read(appSettingsProvider),
              provider,
              RunKind.conversation,
            ),
          ),
        );
  }
  if (text != null) ref.read(promptTextDraftProvider.notifier).put(text);
}

/// "Continuar no Codex" of a conversation (R12): the short dialog — no
/// worktree, the mode of the conversation converted, the app summary or the
/// ai-memory handoff, and the message that goes to the field.
Future<void> showConversationContinueDialog(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
  List<TimelineItem> items,
) async {
  final target = continueTarget(c.provider);
  if (target == null) return;
  final ws = ref.read(activeWorkspaceProvider);
  final handoff = ws == null ? null : await nextHandoffMessage(ref, ws.path);
  if (!context.mounted) return;
  final text = await showAppDialog<String>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => _ConversationContinueDialog(
      conversation: c,
      target: target,
      summary: conversationSummary(c, items, mentionedFiles([
        for (final e in transcriptOf(items)) e.text,
      ])),
      handoff: handoff,
    ),
  );
  if (text == null) return;
  startConversationIn(ref, target, text);
}

class _ConversationContinueDialog extends StatefulWidget {
  const _ConversationContinueDialog({
    required this.conversation,
    required this.target,
    required this.summary,
    this.handoff,
  });

  final Conversation conversation;
  final String target;
  final String summary;
  final String? handoff;

  @override
  State<_ConversationContinueDialog> createState() =>
      _ConversationContinueDialogState();
}

class _ConversationContinueDialogState
    extends State<_ConversationContinueDialog> {
  late bool _useHandoff = widget.handoff != null;
  late final _text = TextEditingController(
    text: widget.handoff ?? widget.summary,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(bool handoff) {
    setState(() => _useHandoff = handoff);
    _text.text = handoff ? widget.handoff! : widget.summary;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final mode = PromptMode.values
        .where((m) => m.name == c.mode)
        .firstOrNull ?? PromptMode.ask;
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    Widget radio(bool value, String title, {String? keyName}) => InkWell(
      key: ValueKey('conversation-continue-${keyName ?? title}'),
      onTap: () => _pick(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _useHandoff == value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 14,
              color: _useHandoff == value
                  ? AppColors.amber
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
    return AlertDialog(
      key: const ValueKey('conversation-continue-dialog'),
      backgroundColor: AppColors.panelSolid,
      title: Text(
        continueLabel(widget.target),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProviderChip(c.provider),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 14),
                ),
                ProviderChip(widget.target),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'conversa nova no Prompt · modo ${mode.label} '
                    '(${mode.access})',
                    key: const ValueKey('conversation-continue-mode'),
                    style: label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            radio(false, 'com o resumo do app', keyName: 'summary'),
            if (widget.handoff != null)
              radio(true, 'com a passagem do ai-memory', keyName: 'handoff'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('conversation-continue-text'),
              controller: _text,
              minLines: 5,
              maxLines: 10,
              style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              'Vai para o campo de mensagem da conversa nova no '
              '${providerWords(widget.target)}; só sai quando você enviar.',
              style: label,
            ),
          ],
        ),
      ),
      actions: [
        SmallButton(
          key: const ValueKey('conversation-continue-cancel'),
          label: 'Cancelar',
          onTap: () => Navigator.pop(context),
        ),
        SmallButton(
          key: const ValueKey('conversation-continue-go'),
          label: continueLabel(widget.target),
          color: AppColors.background,
          background: AppColors.amber,
          border: AppColors.amber,
          onTap: () => Navigator.pop(context, _text.text),
        ),
      ],
    );
  }
}
