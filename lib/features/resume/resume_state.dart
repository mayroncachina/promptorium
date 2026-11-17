import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../activities/activities_state.dart';
import '../home/home_inbox.dart';
import '../home/tray_radar.dart' show radarInbox;
import '../review/ci_fixer.dart';
import 'activity_journal.dart';
import 'presence.dart';
import 'resume_summary.dart';

/// Where the card is (SPEC-080 R10–R13).
enum ResumeMode { hidden, large, compact }

/// Why it opened: the app opened, the person came back, or "O que
/// aconteceu" / the palette (the last 24 h).
enum ResumeOrigin { open, back, manual }

@immutable
class ResumeState {
  const ResumeState({
    this.mode = ResumeMode.hidden,
    this.origin = ResumeOrigin.open,
    this.since,
    this.away,
    this.resolved = const {},
    this.githubFailed = false,
    this.checkingGithub = false,
  });

  final ResumeMode mode;
  final ResumeOrigin origin;

  /// The start of the window ("desde ontem 19:42").
  final DateTime? since;

  /// How long away ("13 h", "47 min").
  final Duration? away;

  /// Items acted on: they leave the card (R9).
  final Set<String> resolved;

  /// "Não deu para conferir o GitHub agora." (R7).
  final bool githubFailed;
  final bool checkingGithub;

  ResumeState copyWith({
    ResumeMode? mode,
    ResumeOrigin? origin,
    DateTime? since,
    Duration? away,
    Set<String>? resolved,
    bool? githubFailed,
    bool? checkingGithub,
  }) => ResumeState(
    mode: mode ?? this.mode,
    origin: origin ?? this.origin,
    since: since ?? this.since,
    away: away ?? this.away,
    resolved: resolved ?? this.resolved,
    githubFailed: githubFailed ?? this.githubFailed,
    checkingGithub: checkingGithub ?? this.checkingGithub,
  );
}

/// "Mostrar ao abrir o app" (R14).
bool resumeOnOpen(Map<String, String> settings) =>
    settings[AppSettingKeys.resumeOnOpen] != '0';

class ResumeController extends Notifier<ResumeState> {
  @override
  ResumeState build() => const ResumeState();

  AppSettingsController get _settings => ref.read(appSettingsProvider.notifier);

  /// The window starts after the last "Tudo visto" (R12).
  DateTime _from(DateTime since) {
    final seen = DateTime.tryParse(
      _settings.get(AppSettingKeys.resumeSeenUntil) ?? '',
    );
    return seen != null && seen.isAfter(since) ? seen : since;
  }

  /// The app opened after being away: the large card (R10).
  void showOpen(AwaySpan span) => state = ResumeState(
    mode: ResumeMode.large,
    origin: ResumeOrigin.open,
    since: _from(span.since),
    away: span.away,
    githubFailed: state.githubFailed,
    checkingGithub: state.checkingGithub,
  );

  /// Back with the app open: the compact card, and the band of the Início
  /// gives way to it (R11, R12).
  void showBack(AwaySpan span) {
    if (state.mode == ResumeMode.large) return;
    state = ResumeState(
      mode: ResumeMode.compact,
      origin: ResumeOrigin.back,
      since: _from(span.since),
      away: span.away,
    );
  }

  /// "O que aconteceu" and the palette: the journal of the last 24 h, even
  /// without being away (R13).
  void showManual({DateTime? now}) {
    final t = now ?? DateTime.now();
    state = ResumeState(
      mode: ResumeMode.large,
      origin: ResumeOrigin.manual,
      since: t.subtract(const Duration(hours: 24)),
      away: const Duration(hours: 24),
      githubFailed: state.githubFailed,
    );
  }

  /// "Ver" of the compact card.
  void expand() {
    if (state.mode == ResumeMode.hidden) return;
    state = state.copyWith(mode: ResumeMode.large);
  }

  /// Esc / "Fechar": what was not resolved stays on the Início (R12).
  Future<void> close() async {
    final since = state.since;
    final keepBand = state.origin != ResumeOrigin.manual && since != null;
    state = state.copyWith(mode: ResumeMode.hidden);
    if (keepBand) {
      await _settings.set(
        AppSettingKeys.resumeBandSince,
        since.toIso8601String(),
      );
    }
  }

  /// Nothing to say: hides without leaving a band (R2: a silent return).
  void dismiss() => state = state.copyWith(mode: ResumeMode.hidden);

  /// "Tudo visto": empties the band and marks the journal seen until now
  /// (R12).
  Future<void> allSeen({DateTime? now}) async {
    state = state.copyWith(mode: ResumeMode.hidden, resolved: const {});
    await _settings.remove(AppSettingKeys.resumeBandSince);
    await _settings.set(
      AppSettingKeys.resumeSeenUntil,
      (now ?? DateTime.now()).toIso8601String(),
    );
  }

  /// An item was acted on (R9): it leaves the card and the band.
  void resolve(String key) =>
      state = state.copyWith(resolved: {...state.resolved, key});

  void setGithub({required bool checking, bool? failed}) =>
      state = state.copyWith(checkingGithub: checking, githubFailed: failed);
}

final resumeProvider = NotifierProvider<ResumeController, ResumeState>(
  ResumeController.new,
);

/// The journal after a time, live.
final journalSinceProvider = StreamProvider.autoDispose
    .family<List<JournalEntry>, DateTime>(
      (ref, since) => ref
          .watch(activityEventsRepoProvider)
          .watchSince(since)
          .map((rows) => [for (final r in rows) JournalEntry.fromRow(r)]),
    );

/// The requests of the Início of every workspace (each PR in its own
/// workspace, as the tray radar).
final resumeRequestsProvider = Provider.autoDispose<List<ResumeRequests>>((
  ref,
) {
  final workspaces = ref.watch(workspacesProvider).value ?? const [];
  return [
    for (final ws in workspaces)
      (
        workspaceId: ws.id,
        groups: radarInbox(ref.watch(workspaceInboxProvider(ws.id)), {
          for (final s in ref.watch(sessionsProvider(ws.id)).value ?? const [])
            s.id,
        }),
      ),
  ];
});

/// The summary of the window that starts at [since] (null = nothing).
/// `loading` until the journal is read: the card waits to decide.
typedef ResumeView = ({ResumeSummary summary, bool loading});

final resumeSummaryForProvider = Provider.autoDispose
    .family<ResumeView, DateTime>((ref, since) {
      final events = ref.watch(journalSinceProvider(since));
      final settings = ref.watch(appSettingsProvider);
      final workspaces = ref.watch(workspacesProvider).value ?? const [];
      final ci = ref.watch(ciFixerProvider);
      final resolved = ref.watch(resumeProvider.select((s) => s.resolved));
      return (
        loading: !events.hasValue,
        summary: buildResumeSummary(
          activities: ref.watch(activitiesProvider),
          requests: ref.watch(resumeRequestsProvider),
          events: events.value ?? const [],
          workspaces: {for (final w in workspaces) w.id: w.name},
          now: DateTime.now(),
          hidden: ResumeKindGroup.decode(
            settings[AppSettingKeys.resumeHiddenKinds],
          ),
          resolved: resolved,
          ciFixing: {
            for (final e in ci.entries)
              if (e.value.inFlight || e.value.phase == CiFixPhase.running)
                e.key,
          },
        ),
      );
    });

/// "Desde a sua última visita" (R12): the start of the band (null = none).
final resumeBandSinceProvider = Provider.autoDispose<DateTime?>((ref) {
  final v = ref.watch(
    appSettingsProvider.select((s) => s[AppSettingKeys.resumeBandSince]),
  );
  final showing =
      ref.watch(resumeProvider.select((s) => s.mode)) != ResumeMode.hidden;
  // The card in front takes the band's place.
  return showing ? null : DateTime.tryParse(v ?? '');
});
