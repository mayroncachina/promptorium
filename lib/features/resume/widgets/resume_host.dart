import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../notifications/agent_alerts.dart' show windowActiveProvider;
import '../activity_journal.dart';
import '../github_catch_up.dart';
import '../presence.dart';
import '../resume_state.dart';
import 'resume_card.dart';

/// Wires "Retomar de onde parei" into the shell (SPEC-080 R1, R2, R7,
/// R10, R11): the window's focus and input feed the [PresenceTracker], the
/// journal starts, the old events go, GitHub is checked and the card shows
/// on opening the app or coming back.
class ResumeHost extends ConsumerStatefulWidget {
  const ResumeHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ResumeHost> createState() => _ResumeHostState();
}

class _ResumeHostState extends ConsumerState<ResumeHost> {
  ActivityJournal? _journal;
  StreamSubscription<AwaySpan>? _returns;
  late final PresenceTracker _presence;

  static bool get _test => Platform.environment['FLUTTER_TEST'] == 'true';

  @override
  void initState() {
    super.initState();
    _presence = ref.read(presenceProvider);
    HardwareKeyboard.instance.addHandler(_onKey);
    _returns = _presence.returns.listen((span) {
      debugPrint('Retomar: voltou depois de ${span.away.inMinutes} min');
      if (!mounted) return;
      ref.read(resumeProvider.notifier).showBack(span);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    // Under tests the journal's drift streams would outlive the tree (it
    // has its own tests).
    if (!_test) _journal = ActivityJournal(container)..start();
    final repo = ref.read(activityEventsRepoProvider);
    try {
      await repo.purgeOlderThan();
    } catch (e) {
      debugPrint('diário: limpeza — $e');
    }
    if (!mounted) return;
    final settings = ref.read(appSettingsProvider);
    final span = _presence.openedAway(
      DateTime.now(),
      openLimit: awayLimitOf(settings) ?? defaultAwayLimit,
    );
    final since = _presence.previousSeenAt;
    if (since != null && !_test) {
      // R7: before the card, what happened on GitHub with the app closed.
      await checkGithub(since);
    }
    if (!mounted || span == null || !resumeOnOpen(settings)) return;
    ref.read(resumeProvider.notifier).showOpen(span);
  }

  /// "Tentar de novo" and the opening (R7).
  Future<void> checkGithub(DateTime since) async {
    final c = ref.read(resumeProvider.notifier)..setGithub(checking: true);
    var ok = false;
    try {
      ok = await runGithubCatchUp(
        ref.read,
        since,
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Retomar: GitHub — $e');
    }
    if (mounted) c.setGithub(checking: false, failed: !ok);
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) _presence.input(DateTime.now());
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_returns?.cancel());
    _journal?.dispose();
    unawaited(_presence.flush());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(windowActiveProvider, (_, active) {
      final now = DateTime.now();
      if (active) {
        _presence.focus(now);
      } else {
        _presence.blur(now);
      }
    });
    ref.listen<Map<String, String>>(appSettingsProvider, (_, s) {
      _presence.limit = awayLimitOf(s);
    });
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _presence.input(DateTime.now()),
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) _presence.input(DateTime.now());
      },
      child: widget.child,
    );
  }
}

/// The card over the content (R10, R11): large at the top center, compact
/// at the top right. Nothing to show hides it (R2: a silent return).
class ResumeOverlay extends ConsumerWidget {
  const ResumeOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(resumeProvider);
    final since = st.since;
    if (st.mode == ResumeMode.hidden || since == null) {
      return const SizedBox.shrink();
    }
    final view = ref.watch(resumeSummaryForProvider(since));
    if (view.loading) return const SizedBox.shrink();
    final s = view.summary;
    final empty = st.mode == ResumeMode.compact ? !s.hasNews : s.isEmpty;
    if (empty && st.origin != ResumeOrigin.manual) {
      debugPrint('Retomar: nada a mostrar (${st.mode.name})');
      // Acting on the last item closes the card (R9).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = ref.read(resumeProvider.notifier);
        if (st.resolved.isEmpty) {
          c.dismiss();
        } else {
          unawaited(c.close());
        }
      });
      return const SizedBox.shrink();
    }
    if (st.mode == ResumeMode.compact) {
      return Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(width: 400, child: ResumeCompact(summary: s)),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ResumeCard(
            summary: s,
            onRetryGithub: () {
              final host = context.findAncestorStateOfType<_ResumeHostState>();
              unawaited(host?.checkGithub(since));
            },
          ),
        ),
      ),
    );
  }
}
