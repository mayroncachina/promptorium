import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/run_prefs.dart';
import '../../../data/providers.dart';
import '../../prompt/conversation_manager.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/timeline_provider.dart';
import '../compaction_controller.dart';
import '../context_panel_state.dart';
import '../context_snapshot.dart';
import '../context_sources.dart';
import 'context_compaction.dart';
import 'context_indicator.dart';
import 'context_panel.dart';

/// Which history a meter / panel reads: a Prompt conversation or a session.
@immutable
sealed class ContextTarget {
  const ContextTarget();

  ContextPlace get place;

  /// Key of [timelineJumpProvider].
  String get jumpKey;

  String get placeLabel;

  TimelineSnapshot watchTimeline(WidgetRef ref);

  bool watchAlive(WidgetRef ref);

  /// A turn (or a compaction) is running.
  bool watchBusy(WidgetRef ref);

  /// The native `/compact` through the history's manager (R9).
  Future<void> compactNow(WidgetRef ref, String command);

  /// Key of the warning dismissal (R10).
  String warningKey(ContextWarning w) =>
      '$jumpKey:${w.turn}:${w.reference}:${w.kind.name}';
}

/// `/compact foco` → `foco` (the managers rebuild the command).
String? _focusOf(String command) {
  final f = command.substring(compactCommandName.length).trim();
  return f.isEmpty ? null : f;
}

class ConversationTarget extends ContextTarget {
  const ConversationTarget(this.id);

  final int id;

  @override
  ContextPlace get place => ContextPlace.prompt;

  @override
  String get jumpKey => 'conv:$id';

  @override
  String get placeLabel => 'Conversa';

  @override
  TimelineSnapshot watchTimeline(WidgetRef ref) =>
      ref.watch(conversationTimelineProvider(id));

  @override
  bool watchAlive(WidgetRef ref) =>
      ref.watch(conversationManagerProvider.select((s) => s.isAlive(id)));

  @override
  bool watchBusy(WidgetRef ref) =>
      ref.watch(conversationManagerProvider.select((s) => s.isBusy(id)));

  @override
  Future<void> compactNow(WidgetRef ref, String command) => ref
      .read(conversationManagerProvider.notifier)
      .compactNow(id, focus: _focusOf(command));

  @override
  bool operator ==(Object other) =>
      other is ConversationTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SessionTarget extends ContextTarget {
  const SessionTarget(this.id);

  final String id;

  @override
  ContextPlace get place => ContextPlace.sessions;

  @override
  String get jumpKey => 'session:$id';

  @override
  String get placeLabel => 'Sessão';

  @override
  TimelineSnapshot watchTimeline(WidgetRef ref) =>
      ref.watch(sessionTimelineProvider(id));

  @override
  bool watchAlive(WidgetRef ref) =>
      ref.watch(sessionManagerProvider.select((s) => s.isAlive(id)));

  @override
  bool watchBusy(WidgetRef ref) => ref.watch(
    sessionManagerProvider.select((s) => s.live[id]?.busy ?? false),
  );

  @override
  Future<void> compactNow(WidgetRef ref, String command) => ref
      .read(sessionManagerProvider.notifier)
      .compactNow(id, focus: _focusOf(command));

  @override
  bool operator ==(Object other) => other is SessionTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The meter above a composer (R2), with the compaction state (R8) and the
/// 85% warning (R10) above it. It reads the history's tracker and opens the
/// panel of its screen.
class ContextBar extends ConsumerWidget {
  const ContextBar({
    super.key,
    required this.target,
    this.attachments = 0,
    this.onReviewAttachments,
  });

  final ContextTarget target;

  /// Pending attachments of the composer (Prompt).
  final int attachments;
  final VoidCallback? onReviewAttachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = target.watchTimeline(ref);
    final s = snap.timeline.context.snapshot;
    final open = ref.watch(contextPanelOpenProvider(target.place));
    final alive = target.watchAlive(ref);
    final w = s.warning;
    final dismissed = ref.watch(dismissedContextWarningsProvider);
    // While the agent compacts, the compaction row says it all.
    final showWarning =
        w != null &&
        s.phase != CompactionPhase.compacting &&
        !dismissed.contains(target.warningKey(w));
    void openPanel([int tab = 0]) {
      ref.read(contextPanelTabProvider(target.place).notifier).set(tab);
      ref.read(contextPanelOpenProvider(target.place).notifier).set(true);
    }

    final status = compactionStatusRow(s, alive: alive);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showWarning) ...[
            ContextWarningBanner(
              snapshot: s,
              onOpenPanel: openPanel,
              onDismiss: () => ref
                  .read(dismissedContextWarningsProvider.notifier)
                  .dismiss(target.warningKey(w)),
              attachments: attachments,
              onReviewAttachments: onReviewAttachments == null
                  ? null
                  : () {
                      openPanel(1);
                      onReviewAttachments!();
                    },
            ),
            const SizedBox(height: 6),
          ],
          if (status != null) ...[status, const SizedBox(height: 6)],
          ContextIndicator(
            snapshot: s,
            alive: alive,
            open: open,
            onOpen: () => ref
                .read(contextPanelOpenProvider(target.place).notifier)
                .toggle(),
          ),
        ],
      ),
    );
  }
}

/// The Contexto panel of [target] (R2–R10) with the compaction controls.
/// The Prompt passes its composer attachments and the new conversation.
class ContextPanelHost extends ConsumerWidget {
  const ContextPanelHost({
    super.key,
    required this.target,
    required this.provider,
    this.title,
    this.pendingAttachments = const [],
    this.onRemoveAttachment,
    this.onNewConversation,
    this.summary,
    this.providers = const [],
    this.onProvider,
    this.handoff,
  });

  final ContextTarget target;

  /// Agent of the history (`claude`, `codex`…): "Compactar agora" needs a
  /// proven native command.
  final String provider;
  final String? title;
  final List<String> pendingAttachments;
  final ValueChanged<String>? onRemoveAttachment;
  final void Function(String? summary)? onNewConversation;
  final String Function()? summary;

  /// SPEC-099 R12: see [ContextActions].
  final List<String> providers;
  final ValueChanged<String>? onProvider;
  final Future<String?> Function()? handoff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = target.watchTimeline(ref);
    final tracker = snap.timeline.context;
    final s = tracker.snapshot;
    final busy = target.watchBusy(ref);
    final tab = ref.watch(contextPanelTabProvider(target.place));
    void jump(int index) =>
        ref.read(timelineJumpProvider(target.jumpKey).notifier).jump(index);
    void setTab(ContextTab t) => ref
        .read(contextPanelTabProvider(target.place).notifier)
        .set(t == ContextTab.usage ? 0 : 1);
    final availability = compactAvailability(
      provider: provider,
      busy: busy,
      snapshot: s,
    );
    final controller = ref.read(compactionControllerProvider);
    return ContextPanel(
      key: ValueKey('context-panel-${target.jumpKey}'),
      snapshot: s,
      sources: tracker.sources,
      place: target.placeLabel,
      title: title,
      alive: target.watchAlive(ref),
      tab: tab == 0 ? ContextTab.usage : ContextTab.sources,
      onTab: setTab,
      onClose: () =>
          ref.read(contextPanelOpenProvider(target.place).notifier).set(false),
      // The item after the reading (its answer) is the one to show.
      onJump: (ContextReading r) => jump(r.itemIndex - 1),
      // R5: a source opens the event that originated it.
      onOpenSource: (ContextSource src) => jump(src.itemIndex - 1),
      autocompact: AutocompactControl(snapshot: s),
      actions: ContextActions(
        snapshot: s,
        availability: availability,
        onCompact: (focus) async {
          await controller.request(
            target.jumpKey,
            availability,
            (command) => target.compactNow(ref, command),
            focus: focus,
          );
        },
        onAdjust: () => _pickAutocompact(context, ref),
        attachments: pendingAttachments.length,
        onReviewAttachments: onRemoveAttachment == null
            ? null
            : () => setTab(ContextTab.sources),
        onNewConversation: onNewConversation,
        summary: summary,
        providers: providers,
        provider: provider,
        onProvider: onProvider,
        handoff: handoff,
      ),
      nextSend: onRemoveAttachment == null
          ? null
          : NextSendSection(
              paths: pendingAttachments,
              onRemove: onRemoveAttachment!,
            ),
    );
  }

  /// "Ajustar compactação automática": the same global choice as
  /// Configurações (R7).
  Future<void> _pickAutocompact(BuildContext context, WidgetRef ref) async {
    final current = ref.read(runPrefsProvider).autocompact;
    final v = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Compactação automática'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Vale para as próximas execuções. A execução atual mantém o '
              'valor com que começou.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final c in autocompactChoices)
            SimpleDialogOption(
              key: ValueKey('context-adjust-$c'),
              onPressed: () => Navigator.pop(context, c),
              child: Text(
                '${c == current ? '● ' : ''}${autocompactChoiceLabel(c)}',
              ),
            ),
        ],
      ),
    );
    if (v != null) {
      await ref
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.autocompact, v);
    }
  }
}
