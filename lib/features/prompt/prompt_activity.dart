import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_provider.dart';
import '../../data/providers.dart';
import 'conversation_manager.dart';

/// A Prompt conversation still answering: the dot and the tooltip of the
/// Prompt item in the sidebar (SPEC-055 R4).
@immutable
class PromptActivity {
  const PromptActivity({
    required this.conversationId,
    required this.title,
    required this.mode,
  });

  final int conversationId;
  final String title;
  final PromptMode mode;

  /// `Respondendo “Como funciona o carrinho?” · Perguntar`.
  String get tooltip => 'Respondendo “$title” · ${mode.label}';

  @override
  bool operator ==(Object other) =>
      other is PromptActivity &&
      other.conversationId == conversationId &&
      other.title == title &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(conversationId, title, mode);
}

/// The most recent conversation of the active workspace that is `busy` (a
/// message sent, its result not in yet), or null.
final promptActivityProvider = Provider.autoDispose<PromptActivity?>((ref) {
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null) return null;
  final busy = {
    for (final e in ref.watch(conversationManagerProvider).live.entries)
      if (e.value.busy) e.key,
  };
  if (busy.isEmpty) return null;
  // Newest first, as the list of the Prompt screen.
  final conversations =
      ref.watch(conversationsProvider(ws.id)).value ?? const [];
  for (final c in conversations) {
    if (busy.contains(c.id)) {
      return PromptActivity(
        conversationId: c.id,
        title: c.title,
        mode: PromptMode.fromName(c.mode),
      );
    }
  }
  return null;
});
