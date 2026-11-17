import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_provider.dart';
import '../../data/providers.dart';
import 'compare/compare_controller.dart';
import 'conversation_manager.dart';

/// A Prompt conversation still answering: the dot and the tooltip of the
/// Prompt item in the sidebar (SPEC-055 R4).
@immutable
class PromptActivity {
  const PromptActivity({
    required this.conversationId,
    required this.title,
    required this.mode,
    this.comparing = false,
  });

  final int conversationId;
  final String title;
  final PromptMode mode;

  /// Its two sides of a comparison run (SPEC-079 R9).
  final bool comparing;

  /// `Respondendo “Como funciona o carrinho?” · Perguntar`.
  String get tooltip => comparing
      ? 'Comparando respostas em “$title”'
      : 'Respondendo “$title” · ${mode.label}';

  @override
  bool operator ==(Object other) =>
      other is PromptActivity &&
      other.conversationId == conversationId &&
      other.title == title &&
      other.mode == mode &&
      other.comparing == comparing;

  @override
  int get hashCode => Object.hash(conversationId, title, mode, comparing);
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
  final comparing = {
    for (final e in ref.watch(compareControllerProvider).entries)
      if (e.value.run.anyLive) e.key,
  };
  busy.addAll(comparing);
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
        comparing: comparing.contains(c.id),
      );
    }
  }
  return null;
});
