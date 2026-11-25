import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../debt_actions.dart';
import '../origin_debts.dart';

/// A message of the agent the person wants to turn into a debt (R9).
@immutable
class MessageDebtRequest {
  const MessageDebtRequest({required this.message, this.selection, this.at});

  /// The whole message (markdown).
  final String message;

  /// The text selected in it, if any.
  final String? selection;
  final DateTime? at;

  /// What fills "O quê": the selection, or the first paragraph.
  String get excerpt => messageDebtExcerpt(message, selection: selection);

  /// The id kept in the link (`originMessageId`): the time of the message.
  String? get messageId => at?.toUtc().toIso8601String();
}

/// Offers "Virar débito" on the messages of the agent below it (SPEC-112
/// R9): a session or a conversation of the Prompt.
class MessageDebtScope extends InheritedWidget {
  const MessageDebtScope({
    super.key,
    required this.onDebt,
    required super.child,
  });

  final void Function(BuildContext context, MessageDebtRequest request) onDebt;

  static MessageDebtScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageDebtScope>();

  @override
  bool updateShouldNotify(MessageDebtScope old) => old.onDebt != onDebt;
}

/// The "Virar débito" button of a message, next to Copiar. It takes no
/// focus on a click, so the selection in the message stays.
class MessageDebtButton extends StatelessWidget {
  const MessageDebtButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Virar débito',
    child: Semantics(
      button: true,
      label: 'Virar débito',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: Icon(
                Icons.pending_actions,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String _norm(String p) => p.endsWith('/') ? p.substring(0, p.length - 1) : p;

/// Opens the form of a message (R9) in [workspaceId]. [writeRoot] is the
/// worktree of the session (null = the main branch: the form asks about
/// the commit).
Future<void> openMessageDebt(
  BuildContext context,
  WidgetRef ref, {
  required int workspaceId,
  required MessageDebtRequest request,
  required String origin,
  required String sessionId,
  String? writeRoot,
}) async {
  final ws = (ref.read(workspacesProvider).value ?? const <Workspace>[])
      .where((w) => w.id == workspaceId)
      .firstOrNull;
  if (ws == null) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showAppToast(const SnackBar(content: Text('Workspace não encontrado.')));
    return;
  }
  await openDebtForm(
    context,
    ref,
    repoRoot: ws.path,
    initial: messageDebtDraft(
      request.message,
      selection: request.selection,
      origin: origin,
    ),
    writeRoot: writeRoot == null || _norm(writeRoot) == _norm(ws.path)
        ? null
        : writeRoot,
    link: DebtLinksCompanion(
      originSessionId: Value(sessionId),
      originMessageId: Value(request.messageId),
    ),
  );
}

final _debtSessionProvider = StreamProvider.autoDispose
    .family<Session?, String>(
      (ref, id) => ref.watch(sessionsRepoProvider).watchById(id),
    );

/// "Virar débito" in the timeline of a session: the row goes to its
/// worktree (R18).
class SessionDebtScope extends ConsumerWidget {
  const SessionDebtScope({
    super.key,
    required this.sessionId,
    required this.child,
  });

  final String sessionId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(_debtSessionProvider(sessionId)).value;
    if (s == null) return child;
    return MessageDebtScope(
      onDebt: (ctx, r) => openMessageDebt(
        ctx,
        ref,
        workspaceId: s.workspaceId,
        request: r,
        origin: 'sessão ${s.title ?? s.branch}',
        sessionId: s.id,
        writeRoot: s.worktreePath,
      ),
      child: child,
    );
  }
}

/// "Virar débito" in a conversation of the Prompt: no worktree, the row
/// goes to the main branch. The link keeps `conversa:<id>` as the session.
class ConversationDebtScope extends ConsumerWidget {
  const ConversationDebtScope({
    super.key,
    required this.conversation,
    required this.child,
  });

  final Conversation conversation;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    return MessageDebtScope(
      onDebt: (ctx, r) => openMessageDebt(
        ctx,
        ref,
        workspaceId: c.workspaceId,
        request: r,
        origin: 'Prompt · ${c.title}',
        sessionId: 'conversa:${c.id}',
      ),
      child: child,
    );
  }
}
