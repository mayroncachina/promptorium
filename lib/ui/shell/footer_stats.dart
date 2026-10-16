import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/usage_tracker.dart';
import '../../data/providers.dart';
import '../../features/mcp/mcp_state.dart';
import '../../features/sessions/session_manager.dart';

enum CliStatus { unknown, connected, notFound }

/// Data shown in the fixed footer. `null` = not known yet (rendered as "—").
///
/// Built by [FooterStatsController] from the live providers.
@immutable
class FooterStats {
  const FooterStats({
    this.cliStatus = CliStatus.unknown,
    this.claudeVersion,
    this.sessionsActive,
    this.sessionsTotal,
    this.sessionsWaiting,
    this.subagentsRunning,
    this.mcpConnected,
    this.mcpTotal,
    this.mcpFailed,
    this.usage5h,
    this.usage5hResetsAt,
    this.usageWeek,
    this.usageWeekResetsAt,
    this.limitRejected = false,
    this.limitResetsAt,
    this.limitType,
  });

  final CliStatus cliStatus;
  final String? claudeVersion;
  final int? sessionsActive;
  final int? sessionsTotal;
  final int? sessionsWaiting;
  final int? subagentsRunning;
  final int? mcpConnected;
  final int? mcpTotal;
  final int? mcpFailed;

  /// 0–1+ (`rate_limit_info.unifiedWindows.five_hour.utilization`; above 1
  /// when the limit was passed). Null = unknown. Stored values outlive the
  /// window: the footer ignores them after the reset ([planWindowExpired]).
  final double? usage5h;
  final DateTime? usage5hResetsAt;

  /// 0–1+ (`…seven_day.utilization`).
  final double? usageWeek;
  final DateTime? usageWeekResetsAt;

  /// The last `rate_limit_event` said `rejected`: new turns fail until
  /// [limitResetsAt]. [limitType] = the window that hit it (`five_hour`,
  /// `seven_day`…).
  final bool limitRejected;
  final DateTime? limitResetsAt;
  final String? limitType;

  FooterStats copyWith({CliStatus? cliStatus, String? claudeVersion}) =>
      FooterStats(
        cliStatus: cliStatus ?? this.cliStatus,
        claudeVersion: claudeVersion ?? this.claudeVersion,
        sessionsActive: sessionsActive,
        sessionsTotal: sessionsTotal,
        sessionsWaiting: sessionsWaiting,
        subagentsRunning: subagentsRunning,
        mcpConnected: mcpConnected,
        mcpTotal: mcpTotal,
        mcpFailed: mcpFailed,
        usage5h: usage5h,
        usage5hResetsAt: usage5hResetsAt,
        usageWeek: usageWeek,
        usageWeekResetsAt: usageWeekResetsAt,
        limitRejected: limitRejected,
        limitResetsAt: limitResetsAt,
        limitType: limitType,
      );
}

/// CLI status found by the startup check.
class CliStatusController extends Notifier<(CliStatus, String?)> {
  @override
  (CliStatus, String?) build() => (CliStatus.unknown, null);

  void set(CliStatus status, {String? version}) => state = (status, version);
}

final cliStatusProvider =
    NotifierProvider<CliStatusController, (CliStatus, String?)>(
      CliStatusController.new,
    );

/// Footer data (plano, Fase 5 item 11): CLI status, sessions of the active
/// workspace, approvals and subagents of every live session, plan usage
/// (last `rate_limit_event`, persisted) and MCP servers of
/// the newest `claude mcp list` / `system/init` ([mcpStatusBoardProvider],
/// Fase 11).
class FooterStatsController extends Notifier<FooterStats> {
  @override
  FooterStats build() {
    final (cli, version) = ref.watch(cliStatusProvider);
    final manager = ref.watch(sessionManagerProvider);
    final ws = ref.watch(activeWorkspaceProvider);
    final sessions = ws == null
        ? null
        : ref.watch(sessionsProvider(ws.id)).value;
    final rate = ref.watch(rateLimitProvider);
    final mcp = ref.watch(mcpStatusBoardProvider);

    int? active;
    if (sessions != null) {
      active = sessions
          .where(
            (s) =>
                manager.isAlive(s.id) &&
                (s.status == SessionStatus.running ||
                    s.status == SessionStatus.waitingApproval),
          )
          .length;
    }
    return FooterStats(
      cliStatus: cli,
      claudeVersion: version,
      sessionsActive: active,
      sessionsTotal: sessions?.length,
      sessionsWaiting: manager.approvals.map((a) => a.sessionId).toSet().length,
      subagentsRunning: manager.subagentsRunning,
      mcpConnected: mcp.isEmpty ? null : mcp.connected,
      mcpTotal: mcp.isEmpty ? null : mcp.total,
      mcpFailed: mcp.isEmpty ? null : mcp.failed,
      usage5h: rate?.fiveHourUtilization,
      usage5hResetsAt: rate?.fiveHourResetsAt,
      usageWeek: rate?.sevenDayUtilization,
      usageWeekResetsAt: rate?.sevenDayResetsAt,
      limitRejected: rate?.status == 'rejected',
      limitResetsAt: rate?.resetsAt,
      limitType: rate?.rateLimitType,
    );
  }

  void setCli(CliStatus status, {String? version}) =>
      ref.read(cliStatusProvider.notifier).set(status, version: version);
}

final footerStatsProvider =
    NotifierProvider<FooterStatsController, FooterStats>(
      FooterStatsController.new,
    );

/// Compact token count: 512k, 1.2M.
String formatTokens(int? n) {
  if (n == null) return '—';
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}M';
  }
  if (n >= 1000) return '${(n / 1000).round()}k';
  return '$n';
}
