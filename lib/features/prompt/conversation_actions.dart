import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_toast.dart';
import '../sessions/timeline.dart';
import 'conversation_manager.dart';
import 'prompt_actions.dart';
import 'spec_batch.dart';
import 'spec_from_answer.dart';
import 'widgets/answer_spec_bar.dart';
import 'widgets/prompt_dialogs.dart';
import 'widgets/spec_batch_dialog.dart';
import 'widgets/split_specs_dialog.dart';
import 'widgets/title_field.dart';

/// Organizing the conversations of the Prompt (SPEC-056): archive with
/// "Desfazer", unarchive, the tab of the list. Used by the list, the header
/// and the conversation.

/// How long "Desfazer" stays offered after archiving (R5).
const archiveUndoWindow = Duration(seconds: 6);

/// `“Plano: cupom” arquivada` (R5).
String archivedMessage(String title) => '“$title” arquivada';

/// Tab of the conversation list (R6).
enum ConversationTab { active, archived }

class ConversationTabController extends Notifier<ConversationTab> {
  @override
  ConversationTab build() => ConversationTab.active;

  void show(ConversationTab tab) {
    if (state != tab) state = tab;
  }
}

final conversationTabProvider =
    NotifierProvider<ConversationTabController, ConversationTab>(
      ConversationTabController.new,
    );

/// Where a title is being edited (R2): next to the title of the open
/// conversation or in its row of the list.
enum RenamePlace { header, list }

typedef RenameTarget = ({int id, RenamePlace place});

class RenamingController extends Notifier<RenameTarget?> {
  @override
  RenameTarget? build() => null;

  void start(int id, RenamePlace place) => state = (id: id, place: place);

  void stop() {
    if (state != null) state = null;
  }
}

final renamingProvider = NotifierProvider<RenamingController, RenameTarget?>(
  RenamingController.new,
);

/// An archive that "Desfazer" can still take back (R5).
@immutable
class ArchiveUndo {
  const ArchiveUndo({
    required this.conversationId,
    required this.title,
    required this.wasSelected,
  });

  final int conversationId;
  final String title;

  /// It was open: "Desfazer" opens it again.
  final bool wasSelected;
}

/// The last archive, offered while its notice is on screen. Ctrl+Z undoes
/// it from anywhere while offered (R5).
class ArchiveUndoController extends Notifier<ArchiveUndo?> {
  Timer? _timer;
  bool _listening = false;

  @override
  ArchiveUndo? build() {
    ref.onDispose(_stop);
    return null;
  }

  void offer(ArchiveUndo undo) {
    _timer?.cancel();
    _onUndone = null;
    state = undo;
    _timer = Timer(archiveUndoWindow, dismiss);
    if (!_listening) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _listening = true;
    }
  }

  /// The notice left: Ctrl+Z goes back to whoever had it.
  void dismiss() {
    _stop();
    if (ref.mounted && state != null) state = null;
  }

  /// Drops the offer only when it is still [undo] (a newer archive keeps
  /// its own).
  void dismissIf(ArchiveUndo undo) {
    if (identical(state, undo)) dismiss();
  }

  void _stop() {
    _onUndone = null;
    _timer?.cancel();
    _timer = null;
    if (_listening) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      _listening = false;
    }
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyZ) {
      return false;
    }
    final k = HardwareKeyboard.instance;
    if (!k.isControlPressed || k.isShiftPressed || k.isAltPressed) {
      return false;
    }
    if (state == null) return false;
    unawaited(undo());
    return true;
  }

  /// "Desfazer": the conversation goes back to the active list (and is
  /// opened again when it was open).
  Future<void> undo() async {
    final u = state;
    if (u == null) return;
    final hideNotice = _onUndone;
    dismiss();
    hideNotice?.call();
    await ref.read(conversationsRepoProvider).unarchive(u.conversationId);
    if (u.wasSelected) {
      ref.read(selectedConversationProvider.notifier).select(u.conversationId);
      ref.read(conversationTabProvider.notifier).show(ConversationTab.active);
    }
  }

  /// Hides the notice when undone by Ctrl+Z.
  VoidCallback? _onUndone;
}

final archiveUndoProvider =
    NotifierProvider<ArchiveUndoController, ArchiveUndo?>(
      ArchiveUndoController.new,
    );

/// The conversation that takes the selection when [id] leaves [list]: the
/// one above, else the one below (R4); null when it was the only one.
int? neighbourOf(List<Conversation> list, int id) {
  final i = list.indexWhere((c) => c.id == id);
  if (i < 0) return null;
  if (i > 0) return list[i - 1].id;
  if (i + 1 < list.length) return list[i + 1].id;
  return null;
}

/// `hoje` / `ontem` / `3 nov` / `12 out 2025`.
String archivedWhen(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final t = at.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'hoje';
  if (days == 1) return 'ontem';
  const months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  final m = months[t.month - 1];
  return t.year == n.year ? '${t.day} $m' : '${t.day} $m ${t.year}';
}

/// Archive and unarchive (R4–R7). Nothing stops the process of a
/// conversation that is answering: only its row changes.
class ConversationActions {
  ConversationActions(this._ref);

  final Ref _ref;

  /// Archives [c] and offers "Desfazer" for [archiveUndoWindow]. When [c] is
  /// open the selection goes to its neighbour in [active] (R4).
  Future<void> archive(
    BuildContext context,
    Conversation c, {
    required List<Conversation> active,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final selected = _ref.read(selectedConversationProvider) == c.id;
    if (selected) {
      _ref
          .read(selectedConversationProvider.notifier)
          .select(neighbourOf(active, c.id));
    }
    await _ref.read(conversationsRepoProvider).archive(c.id);
    final undo = ArchiveUndo(
      conversationId: c.id,
      title: c.title,
      wasSelected: selected,
    );
    final undoCtl = _ref.read(archiveUndoProvider.notifier);
    undoCtl.offer(undo);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    var open = true;
    final toast = messenger.showAppToast(
      SnackBar(
        key: const ValueKey('archive-toast'),
        duration: archiveUndoWindow,
        persist: false,
        content: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const Icon(
                Icons.archive_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  archivedMessage(c.title),
                  key: const ValueKey('archive-toast-text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 13,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
        action: SnackBarAction(
          key: const ValueKey('archive-undo'),
          label: 'Desfazer',
          onPressed: () {
            // The action hides the notice itself.
            open = false;
            unawaited(undoCtl.undo());
          },
        ),
      ),
    );
    // Ctrl+Z: the notice leaves with the archive it offered.
    undoCtl._onUndone = () {
      if (open) toast.close();
    };
    unawaited(
      toast.closed.then((_) {
        open = false;
        undoCtl.dismissIf(undo);
      }),
    );
  }

  /// New title of [id] (R2, R3): trimmed, at most [maxTitleLength]
  /// characters; an empty one is not saved.
  Future<void> rename(int id, String title) async {
    _ref.read(renamingProvider.notifier).stop();
    final t = normalizeTitle(title);
    if (t == null) return;
    await _ref.read(conversationsRepoProvider).rename(id, t);
  }

  /// Back to the active list (R6, R7).
  Future<void> unarchive(int id) async {
    final undo = _ref.read(archiveUndoProvider);
    if (undo?.conversationId == id) {
      _ref.read(archiveUndoProvider.notifier).dismiss();
    }
    await _ref.read(conversationsRepoProvider).unarchive(id);
  }
}

final conversationActionsProvider = Provider(ConversationActions.new);

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showAppToast(SnackBar(content: Text(msg)));
}

/// "Transformar em spec": a spec written by the agent wins over the
/// transcript (SPEC-016 R5).
Future<void> conversationToSpec(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
  List<TimelineItem> items,
) async {
  final written = lastAnswerSpecs(items);
  if (written != null && written.specs.length > 1) {
    // SPEC-068 R3: two or more go through the review list.
    await showSpecBatch(context, ref, c, [
      for (var i = 0; i < written.specs.length; i++)
        SpecBatchItem.of(i, written.specs[i]),
    ], answer: written.answer);
    return;
  }
  if (written != null) {
    await primaryAnswerSpec(context, ref, c, written.specs.single);
    return;
  }
  if (lastAnswer(items) == null) {
    _snack(context, 'A conversa ainda não tem resposta.');
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

/// Timeline items of [id], once its stored events are loaded.
Future<List<TimelineItem>> _loadedItems(WidgetRef ref, int id) async {
  final now = ref.read(conversationTimelineProvider(id));
  if (!now.loading) return now.items;
  final done = Completer<List<TimelineItem>>();
  final sub = ref.listenManual(conversationTimelineProvider(id), (_, s) {
    if (!s.loading && !done.isCompleted) done.complete(s.items);
  });
  try {
    return await done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => ref.read(conversationTimelineProvider(id)).items,
    );
  } finally {
    sub.close();
  }
}

/// Entries of the menu of a conversation (R1).
enum ConversationMenuAction {
  rename,
  archive,
  unarchive,
  toSpec,
  split,
  continueSession,
}

/// The menu of [c] (right click on the row, ⋯ of the row or of the header):
/// Renomear (F2), Arquivar (or Desarquivar), a separator, Transformar em
/// spec, Dividir em specs (SPEC-068 R2) and Continuar como sessão (R1). [items] = its loaded timeline, when
/// known; [renameIn] = where Renomear edits the title.
Future<void> showConversationMenu(
  BuildContext context,
  WidgetRef ref, {
  required Conversation c,
  required RelativeRect position,
  required List<Conversation> active,
  required RenamePlace renameIn,
  List<TimelineItem>? items,
}) async {
  final busy = ref.read(conversationManagerProvider).isBusy(c.id);
  final hasAnswer = items == null
      ? c.messageCount > 1
      : lastAnswer(items) != null;
  final archived = c.archivedAt != null;
  PopupMenuItem<ConversationMenuAction> entry(
    ConversationMenuAction value,
    IconData icon,
    String label, {
    bool enabled = true,
    String? shortcut,
  }) => PopupMenuItem(
    key: ValueKey('conversation-menu-${value.name}'),
    value: value,
    enabled: enabled,
    height: 36,
    child: Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.textSecondary : AppColors.textDisabled,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: enabled ? AppColors.text : AppColors.textDisabled,
          ),
        ),
        if (shortcut != null) ...[
          const Spacer(),
          Text(
            shortcut,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    ),
  );
  final choice = await showMenu<ConversationMenuAction>(
    context: context,
    color: AppColors.panelSolid,
    position: position,
    constraints: const BoxConstraints(minWidth: 240),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: AppColors.border),
    ),
    items: [
      entry(
        ConversationMenuAction.rename,
        Icons.edit_outlined,
        'Renomear',
        shortcut: 'F2',
      ),
      archived
          ? entry(
              ConversationMenuAction.unarchive,
              Icons.unarchive_outlined,
              'Desarquivar',
            )
          : entry(
              ConversationMenuAction.archive,
              Icons.archive_outlined,
              'Arquivar',
            ),
      const PopupMenuDivider(height: 9),
      entry(
        ConversationMenuAction.toSpec,
        Icons.description_outlined,
        'Transformar em spec',
        enabled: !busy && hasAnswer,
      ),
      entry(
        ConversationMenuAction.split,
        Icons.call_split,
        'Dividir em specs',
        enabled: !busy && hasAnswer,
        shortcut: 'novo',
      ),
      entry(
        ConversationMenuAction.continueSession,
        Icons.terminal,
        'Continuar como sessão',
        enabled: !busy && c.claudeSessionId != null,
      ),
    ],
  );
  if (choice == null || !context.mounted) return;
  final actions = ref.read(conversationActionsProvider);
  switch (choice) {
    case ConversationMenuAction.rename:
      ref.read(renamingProvider.notifier).start(c.id, renameIn);
    case ConversationMenuAction.archive:
      await actions.archive(context, c, active: active);
    case ConversationMenuAction.unarchive:
      await actions.unarchive(c.id);
    case ConversationMenuAction.toSpec:
      final loaded = items ?? await _loadedItems(ref, c.id);
      if (context.mounted) await conversationToSpec(context, ref, c, loaded);
    case ConversationMenuAction.split:
      final loaded = items ?? await _loadedItems(ref, c.id);
      if (context.mounted) {
        await splitIntoSpecs(context, ref, c, transcriptOf(loaded));
      }
    case ConversationMenuAction.continueSession:
      await showContinueSessionDialog(context, c);
  }
}

/// [RelativeRect] under the widget of [context] (the ⋯ buttons), aligned
/// to its right edge.
RelativeRect menuPositionBelow(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  return RelativeRect.fromRect(
    rect.translate(0, 4),
    Offset.zero & overlay.size,
  );
}

/// [RelativeRect] at a pointer position (right click).
RelativeRect menuPositionAt(BuildContext context, Offset global) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(
    overlay.globalToLocal(global) & const Size(1, 1),
    Offset.zero & overlay.size,
  );
}
