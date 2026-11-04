import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text waiting to fill the message field of a session, by session id
/// (SPEC-033 R12). The field takes it and nothing is sent by itself.
class SessionComposerDrafts extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void put(String sessionId, String text) =>
      state = {...state, sessionId: text};

  /// The draft of [sessionId], which leaves the provider.
  String? take(String sessionId) {
    final text = state[sessionId];
    if (text != null) state = {...state}..remove(sessionId);
    return text;
  }
}

final sessionComposerDraftProvider =
    NotifierProvider<SessionComposerDrafts, Map<String, String>>(
      SessionComposerDrafts.new,
    );
