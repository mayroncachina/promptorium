import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CliStatus { unknown, connected, notFound }

/// Data shown in the fixed footer. `null` = not known yet (rendered as "—").
///
/// Fase 2 only fills [cliStatus] (from the startup check). Fase 5 wires the
/// sessions, MCP and `rate_limit_event` data (see plano, Fase 0.2).
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
    this.tokensToday,
    this.tokensIn,
    this.tokensOut,
    this.tokensCache,
    this.usage5h,
    this.usage5hResetsAt,
    this.usageWeek,
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
  final int? tokensToday;
  final int? tokensIn;
  final int? tokensOut;
  final int? tokensCache;

  /// 0–1 (`rate_limit_info.unifiedWindows.five_hour.utilization`).
  final double? usage5h;
  final DateTime? usage5hResetsAt;

  /// 0–1 (`…seven_day.utilization`).
  final double? usageWeek;

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
        tokensToday: tokensToday,
        tokensIn: tokensIn,
        tokensOut: tokensOut,
        tokensCache: tokensCache,
        usage5h: usage5h,
        usage5hResetsAt: usage5hResetsAt,
        usageWeek: usageWeek,
      );
}

class FooterStatsController extends Notifier<FooterStats> {
  @override
  FooterStats build() => const FooterStats();

  void setCli(CliStatus status, {String? version}) =>
      state = state.copyWith(cliStatus: status, claudeVersion: version);

  /// Generic setter for later phases.
  void replace(FooterStats stats) => state = stats;
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
