import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../activities/activities_screen.dart'
    show activitiesSelectionProvider, activitiesTabProvider;
import '../activities/activity.dart' show ActivityTab;
import '../board/board_screen.dart'
    show boardFocusSpecProvider, boardSelectedSpecProvider;
import '../prompt/conversation_manager.dart';
import '../sessions/session_manager.dart';

/// Where the click on a notification leads (SPEC-086 R7): the workspace,
/// the screen, the session or conversation and the card of the request,
/// with the keyboard focus on its main button.

/// What the agent waits for (R1).
enum AlertKind { approval, question, plan, needsInput, secret }

/// The request behind a notification. Kept in memory while it is open.
@immutable
class AlertTarget {
  const AlertTarget({
    required this.workspaceId,
    required this.kind,
    this.sessionId,
    this.conversationId,
    this.specId,
    this.requestId,
  });

  final int workspaceId;
  final AlertKind kind;
  final String? sessionId;
  final int? conversationId;
  final int? specId;

  /// The `request_id` of the approval (the card's id); the activity id of a
  /// stopped step.
  final String? requestId;

  /// The screen of the request.
  AppSection get section => kind == AlertKind.needsInput
      ? AppSection.tasks
      : conversationId != null
      ? AppSection.prompt
      : AppSection.sessions;

  @override
  bool operator ==(Object other) =>
      other is AlertTarget &&
      other.workspaceId == workspaceId &&
      other.kind == kind &&
      other.sessionId == sessionId &&
      other.conversationId == conversationId &&
      other.specId == specId &&
      other.requestId == requestId;

  @override
  int get hashCode => Object.hash(
    workspaceId,
    kind,
    sessionId,
    conversationId,
    specId,
    requestId,
  );
}

typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// A card to bring into view and focus (R7 step 3 and 4).
@immutable
class AlertFocus {
  const AlertFocus(this.requestId, {this.announce});

  final String requestId;

  /// What the screen reader says: "Ada, SPEC-031: quer executar flutter
  /// test".
  final String? announce;
}

/// The card waiting to be focused. The card takes it when it is built
/// ([AlertSpotlight]); a request nobody takes goes away after 5 s.
class AlertFocusController extends Notifier<AlertFocus?> {
  Timer? _expiry;

  @override
  AlertFocus? build() {
    ref.onDispose(() => _expiry?.cancel());
    return null;
  }

  void request(AlertFocus focus) {
    state = focus;
    _expiry?.cancel();
    _expiry = Timer(const Duration(seconds: 5), clear);
  }

  /// The card took it.
  void take(AlertFocus focus) {
    if (identical(state, focus)) clear();
  }

  void clear() {
    _expiry?.cancel();
    _expiry = null;
    state = null;
  }
}

final alertFocusProvider = NotifierProvider<AlertFocusController, AlertFocus?>(
  AlertFocusController.new,
);

/// A line for the toast of the shell ("Esse pedido já foi respondido").
class AlertNotice extends Notifier<({String text, int serial})?> {
  int _serial = 0;

  @override
  ({String text, int serial})? build() => null;

  void show(String text) => state = (text: text, serial: ++_serial);
}

final alertNoticeProvider =
    NotifierProvider<AlertNotice, ({String text, int serial})?>(
      AlertNotice.new,
    );

/// The toast when the request of a notification is gone.
const alertAnsweredText = 'Esse pedido já foi respondido';

/// Opens [target] (R7): its workspace, its screen, the session or the
/// conversation selected, and the card of the request in view with the
/// focus on its main button. When the request is gone ([pending] false),
/// opens the session and says so.
Future<void> openAlertTarget(
  Reader read,
  AlertTarget target, {
  required bool pending,
  String? announce,
}) async {
  final active = read(activeWorkspaceProvider);
  if (active?.id != target.workspaceId) {
    await read(workspaceActionsProvider).select(target.workspaceId);
  }
  final nav = read(navigationProvider.notifier);
  switch (target.section) {
    case AppSection.prompt:
      read(selectedConversationProvider.notifier).select(target.conversationId);
    case AppSection.tasks:
      if (target.specId case final spec?) {
        read(boardSelectedSpecProvider.notifier).select(spec);
        read(boardFocusSpecProvider.notifier).select(spec);
      }
    default:
      read(selectedSessionProvider.notifier).select(target.sessionId);
  }
  nav.go(target.section);
  final request = target.requestId;
  if (!pending) {
    read(alertNoticeProvider.notifier).show(alertAnsweredText);
  } else if (request != null) {
    read(alertFocusProvider.notifier)
        .request(AlertFocus(request, announce: announce));
  }
}

/// The click on the summary (R10): the Atividades, tab "Precisa de você".
void openNeedsYou(Reader read) {
  read(activitiesSelectionProvider.notifier).select(null);
  read(activitiesTabProvider.notifier).select(ActivityTab.needsYou);
  read(navigationProvider.notifier).go(AppSection.activities);
}

/// How long the amber ring stays around the card (R7 step 4).
const alertRingFor = Duration(milliseconds: 1500);

/// Wraps the card of the request [requestId]: when a notification asks for
/// it, brings it into view, puts the focus on [primary] (or the first
/// focusable inside), rings it in amber for [alertRingFor] and lets the
/// screen reader announce it.
class AlertSpotlight extends ConsumerStatefulWidget {
  const AlertSpotlight({
    super.key,
    required this.requestId,
    required this.child,
    this.primary,
    this.within,
    this.radius = 8,
  });

  final String requestId;
  final Widget child;
  final FocusNode? primary;

  /// Without [primary]: the first focusable inside this node (the answers
  /// of a question), else inside the card.
  final FocusNode? within;
  final double radius;

  @override
  ConsumerState<AlertSpotlight> createState() => _AlertSpotlightState();
}

class _AlertSpotlightState extends ConsumerState<AlertSpotlight> {
  final _scope = FocusNode(
    debugLabel: 'alert-spotlight',
    canRequestFocus: false,
    skipTraversal: true,
  );
  Timer? _ring;

  @override
  void initState() {
    super.initState();
    // The usual case: the screen is built after the request.
    _maybe(ref.read(alertFocusProvider));
  }

  void _maybe(AlertFocus? f) {
    if (f == null || f.requestId != widget.requestId) return;
    // After the frame: the click navigates in the same step it asks for the
    // focus, so a card about to go away (the floating one of
    // GlobalApprovals, over the screen being left) leaves the request to
    // the card of the new screen.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || !identical(ref.read(alertFocusProvider), f)) return;
        ref.read(alertFocusProvider.notifier).take(f);
        unawaited(_spot(f));
      })
      ..ensureVisualUpdate();
  }

  Future<void> _spot(AlertFocus f) async {
    setState(() {
      _ring?.cancel();
      _ring = Timer(alertRingFor, () {
        if (mounted) setState(() => _ring = null);
      });
    });
    try {
      await Scrollable.ensureVisible(
        context,
        alignment: .5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
    } catch (_) {}
    if (!mounted) return;
    final node =
        widget.primary ??
        (widget.within ?? _scope).traversalDescendants
            .where((n) => n.canRequestFocus)
            .firstOrNull;
    node?.requestFocus();
    final text = f.announce;
    if (text != null && text.isNotEmpty) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          text,
          Directionality.of(context),
          assertiveness: Assertiveness.assertive,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ring?.cancel();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(alertFocusProvider, (_, f) => _maybe(f));
    final ringing = _ring != null;
    return Focus(
      focusNode: _scope,
      child: AnimatedContainer(
        key: ValueKey('alert-spotlight-${widget.requestId}'),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: ringing ? AppColors.amber : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }

  /// Whether the ring is on (tests).
  @visibleForTesting
  bool get ringing => _ring != null;
}
