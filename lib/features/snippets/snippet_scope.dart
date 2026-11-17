import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/widgets/markdown/code_block.dart';
import 'widgets/save_snippet_dialog.dart';

/// The workspace and origin of code offered by a conversation or session.
/// This scope is deliberately absent from document previews.
class SnippetOrigin {
  const SnippetOrigin({
    required this.workspaceId,
    required this.label,
    this.conversationId,
    this.sessionId,
    this.at,
  });

  factory SnippetOrigin.conversation(Conversation c) => SnippetOrigin(
    workspaceId: c.workspaceId,
    label: c.title,
    conversationId: c.id,
    at: c.createdAt,
  );

  final int workspaceId;
  final String label;
  final int? conversationId;
  final String? sessionId;
  final DateTime? at;
}

class SnippetScope extends StatelessWidget {
  const SnippetScope({super.key, required this.origin, required this.child});

  final SnippetOrigin origin;
  final Widget child;

  @override
  Widget build(BuildContext context) => CodeBlockActions(
    builder: (_, code, language) =>
        SaveSnippetButton(origin: origin, code: code, language: language),
    child: child,
  );
}

final _snippetSessionProvider = StreamProvider.autoDispose
    .family<Session?, String>(
      (ref, id) => ref.watch(sessionsRepoProvider).watchById(id),
    );

class SessionSnippetScope extends ConsumerWidget {
  const SessionSnippetScope({
    super.key,
    required this.sessionId,
    required this.child,
  });

  final String sessionId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(_snippetSessionProvider(sessionId)).value;
    if (s == null) return child;
    return SnippetScope(
      origin: SnippetOrigin(
        workspaceId: s.workspaceId,
        sessionId: s.id,
        label: s.title ?? s.branch,
        at: s.startedAt,
      ),
      child: child,
    );
  }
}
