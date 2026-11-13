import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart' show gitServiceFactoryProvider;
import '../../core/providers/agent_provider.dart' show ImagePart;
import '../../data/providers.dart';
import '../project/project_config.dart';
import '../prompt/conversation_manager.dart';
import 'vibe_guard.dart';
import 'vibe_service.dart';

/// Why a request to a VIBE waits for a choice.
enum VibeAsk {
  /// "Isso parece outro assunto" (SPEC-069 R5).
  unrelated,

  /// The VIBE passed its cap (R8).
  cap,
}

/// A request held until the person chooses (R5: it only runs after the
/// choice; R8: the agent stops before going on).
@immutable
class VibePending {
  const VibePending({
    required this.ask,
    this.text = '',
    this.reason = '',
    this.size,
  });

  final VibeAsk ask;

  /// The request held (empty when the cap was reached by an answer).
  final String text;
  final String reason;
  final VibeSize? size;
}

/// The requests of the VIBEs' conversations go through here: the cap and
/// the check of another subject come before the agent (R5, R6, R8).
/// State: the request waiting for a choice, by conversation.
class VibeFlow extends Notifier<Map<int, VibePending>> {
  /// Requests accepted with "Continuar nesta", by VIBE: the check takes
  /// them as part of it and does not ask again about the same subject.
  final Map<int, List<String>> _accepted = {};

  @override
  Map<int, VibePending> build() => const {};

  void _set(int conv, VibePending? p) =>
      state = p == null ? ({...state}..remove(conv)) : {...state, conv: p};

  /// Requests accepted in [specId] after "Continuar nesta".
  List<String> acceptedOf(int specId) =>
      List.unmodifiable(_accepted[specId] ?? const <String>[]);

  /// The cap in effect for [specId]: 1 (100%), plus 0.5 at each "Continuar
  /// como VIBE".
  double threshold(int specId) =>
      double.tryParse(
        ref.read(appSettingsProvider.notifier).get(vibeCapKey(specId)) ?? '',
      ) ??
      1;

  /// Sends [text] to [conversationId], or holds it when the VIBE passed its
  /// cap or the request seems another subject. Returns whether it was sent.
  Future<bool> submit(
    int conversationId,
    String text, {
    List<ImagePart> images = const [],
  }) async {
    final manager = ref.read(conversationManagerProvider.notifier);
    final conv = await ref
        .read(conversationsRepoProvider)
        .getById(conversationId);
    final specId = conv?.specId;
    final spec = specId == null
        ? null
        : await ref.read(specsRepoProvider).getById(specId);
    if (spec == null ||
        spec.kind != SpecKind.vibe ||
        spec.stage == SpecStage.done ||
        spec.worktreePath == null) {
      await manager.send(conversationId, text, images: images);
      return true;
    }
    final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
    final cap = ws == null
        ? const VibeConfig()
        : ProjectConfig.loadSync(ws.path).vibe;
    VibeSize? size;
    try {
      size = await vibeSize(
        ref.read(gitServiceFactoryProvider)(spec.worktreePath!),
        base: spec.baseBranch ?? 'main',
        ownFile: spec.path,
      );
    } catch (e) {
      debugPrint('vibe ${spec.code}: tamanho — $e');
    }
    if (size != null && size.over(cap, threshold: threshold(spec.id))) {
      _set(
        conversationId,
        VibePending(ask: VibeAsk.cap, text: text, size: size),
      );
      return false;
    }
    try {
      final verdict = await ref.read(unrelatedRequestProvider)(
        vibe: spec,
        changed: size?.paths ?? const [],
        accepted: acceptedOf(spec.id),
        request: text,
      );
      if (verdict.ask) {
        _set(
          conversationId,
          VibePending(
            ask: VibeAsk.unrelated,
            text: text,
            reason: verdict.reason,
          ),
        );
        return false;
      }
    } catch (e) {
      // The check is a help: without it the request goes on.
      debugPrint('vibe ${spec.code}: checagem de assunto — $e');
    }
    await manager.send(conversationId, text, images: images);
    return true;
  }

  /// The cap card after an answer took the VIBE past it (no request held).
  void capReached(int conversationId, VibeSize size) {
    if (state[conversationId] != null) return;
    _set(conversationId, VibePending(ask: VibeAsk.cap, size: size));
  }

  /// "Continuar nesta" (R5): runs here and does not ask again about it.
  Future<void> continueHere(int conversationId, int specId) async {
    final p = state[conversationId];
    if (p == null) return;
    _accepted.putIfAbsent(specId, () => []).add(p.text);
    _set(conversationId, null);
    await ref
        .read(conversationManagerProvider.notifier)
        .send(conversationId, p.text);
  }

  /// "Abrir VIBE nova" (R5): the request goes to a new VIBE. Returns its
  /// conversation.
  Future<int?> openNew(int conversationId, Workspace ws) async {
    final p = state[conversationId];
    if (p == null) return null;
    final conv = await ref
        .read(conversationsRepoProvider)
        .getById(conversationId);
    final r = await ref
        .read(vibeServiceProvider)
        .start(ws, p.text, model: conv?.model, providerId: conv?.provider);
    _set(conversationId, null);
    return r.conversationId;
  }

  /// "Continuar como VIBE" (R8): the cap asks again 50% later.
  Future<void> continueAsVibe(int conversationId, int specId) async {
    final p = state[conversationId];
    final size = p?.size;
    final ws = await ref
        .read(workspacesRepoProvider)
        .getById(
          (await ref.read(specsRepoProvider).getById(specId))?.workspaceId ??
              -1,
        );
    final cap = ws == null
        ? const VibeConfig()
        : ProjectConfig.loadSync(ws.path).vibe;
    var next = threshold(specId) + 0.5;
    // Already far past it: the next question is 50% after where it is.
    if (size != null) {
      while (size.over(cap, threshold: next)) {
        next += 0.5;
      }
    }
    await ref
        .read(appSettingsProvider.notifier)
        .set(vibeCapKey(specId), '$next');
    _set(conversationId, null);
    if (p != null && p.text.isNotEmpty) {
      await ref
          .read(conversationManagerProvider.notifier)
          .send(conversationId, p.text);
    }
  }

  /// "Virar spec" (R8): the VIBE becomes a spec in place and the held
  /// request goes on.
  Future<void> promote(int conversationId, int specId) async {
    final p = state[conversationId];
    await ref.read(vibeServiceProvider).promote(specId);
    _set(conversationId, null);
    if (p != null && p.text.isNotEmpty) {
      await ref
          .read(conversationManagerProvider.notifier)
          .send(conversationId, p.text);
    }
  }

  /// Holds [p] in [conversationId] (tests).
  @visibleForTesting
  void hold(int conversationId, VibePending p) => _set(conversationId, p);

  /// The person closed the question without choosing: nothing runs.
  void dismiss(int conversationId) => _set(conversationId, null);
}

final vibeFlowProvider = NotifierProvider<VibeFlow, Map<int, VibePending>>(
  VibeFlow.new,
);
