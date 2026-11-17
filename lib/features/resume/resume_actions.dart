import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/widgets/app_toast.dart';
import '../activities/activities_screen.dart' show openActivities;
import '../activities/activity.dart' show ActivityAction;
import '../activities/activity_actions.dart';
import '../board/board_screen.dart'
    show boardFocusSpecProvider, boardSelectedSpecProvider, openSession;
import '../prompt/conversation_manager.dart';
import '../repository/repository_screen.dart' show repositoryTabProvider;
import '../review/ci_fixer.dart';
import '../review/review_service.dart'
    show reviewServiceProvider, selectedReviewProvider;
import '../sessions/session_manager.dart';
import 'resume_state.dart';
import 'resume_summary.dart';

/// What the button of an item does (SPEC-080 R9): it goes to the item's
/// workspace and to the right screen. The item leaves the card; the card
/// stays open unless it is empty.

Future<void> _enter(WidgetRef ref, int workspaceId) async {
  if (ref.read(activeWorkspaceProvider)?.id != workspaceId) {
    await ref.read(workspaceActionsProvider).select(workspaceId);
  }
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showAppToast(SnackBar(content: Text(text)));
}

Future<void> _board(WidgetRef ref, int specId) async {
  ref.read(boardSelectedSpecProvider.notifier).select(specId);
  ref.read(boardFocusSpecProvider.notifier).select(specId);
  ref.read(navigationProvider.notifier).go(AppSection.tasks);
}

void _review(WidgetRef ref, String? sessionId) {
  ref.read(selectedReviewProvider.notifier).select(sessionId);
  ref.read(navigationProvider.notifier).go(AppSection.review);
}

void _open(WidgetRef ref, ResumeItem i) {
  final nav = ref.read(navigationProvider.notifier);
  if (i.conversationId case final c?) {
    ref.read(selectedConversationProvider.notifier).select(c);
    nav.go(AppSection.prompt);
  } else if (i.sessionId case final s?) {
    openSession(ref, s);
  } else if (i.specId case final s?) {
    _board(ref, s);
  } else {
    nav.go(AppSection.activities);
  }
}

Future<void> _openPr(WidgetRef ref, ResumeItem i) async {
  final s = i.sessionId == null
      ? null
      : await ref.read(sessionsRepoProvider).getById(i.sessionId!);
  final url = s?.prUrl;
  if (url != null) {
    await ref.read(reviewServiceProvider).openUrl(url);
  } else {
    _review(ref, i.sessionId);
  }
}

/// Runs the action of [i] (R9) and marks it resolved.
Future<void> runResumeAction(
  BuildContext context,
  WidgetRef ref,
  ResumeItem i,
) async {
  ref.read(resumeProvider.notifier).resolve(i.key);
  try {
    final a = i.activity;
    // A live item: the Atividades' own actions.
    if (a != null) {
      if (i.action == ResumeAction.open) {
        await _enter(ref, i.workspaceId);
        openActivities(ref, a.id);
        return;
      }
      if (!context.mounted) return;
      await runActivityAction(context, ref, a, switch (i.action) {
        ResumeAction.resume => ActivityAction.resume,
        ResumeAction.viewPlan => ActivityAction.viewPlan,
        _ => ActivityAction.respond,
      });
      return;
    }
    await _enter(ref, i.workspaceId);
    final nav = ref.read(navigationProvider.notifier);
    switch (i.action) {
      case ResumeAction.respond ||
          ResumeAction.viewPlan ||
          ResumeAction.viewError ||
          ResumeAction.open:
        _open(ref, i);
      case ResumeAction.resume:
        final s = i.sessionId;
        if (s == null) {
          _open(ref, i);
        } else {
          await ref.read(sessionManagerProvider.notifier).continueSession(s);
          if (context.mounted) _toast(context, 'Retomando ${i.title}');
        }
      case ResumeAction.review:
        if (i.sessionId == null && i.specId != null) {
          await _board(ref, i.specId!);
        } else {
          _review(ref, i.sessionId);
        }
      case ResumeAction.viewGate || ResumeAction.viewInBoard:
        if (i.specId case final s?) {
          await _board(ref, s);
        } else {
          _open(ref, i);
        }
      case ResumeAction.fixCi:
        final s = i.sessionId;
        if (s != null && await ref.read(ciFixerProvider.notifier).fix(s)) {
          if (context.mounted) _toast(context, 'Corrigindo o CI de ${i.title}');
        }
        _review(ref, s);
      case ResumeAction.viewCi:
        _review(ref, i.sessionId);
      case ResumeAction.openPr:
        await _openPr(ref, i);
      case ResumeAction.viewRelease || ResumeAction.viewLog:
        ref.read(repositoryTabProvider.notifier).select('releases');
        nav.go(AppSection.repository);
    }
  } on Exception catch (e) {
    if (context.mounted) _toast(context, '$e');
  }
}
