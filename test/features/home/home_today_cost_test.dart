import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';

/// SPEC-097 R9, decision 5: the Início "Hoje · Custo" card never shows a
/// Codex run as "$0.00".
void main() {
  Session run(String provider, double cost) => Session(
    id: '$provider-$cost',
    workspaceId: 1,
    provider: provider,
    worktreePath: '/r',
    branch: 'main',
    status: SessionStatus.completed,
    model: provider == 'codex' ? 'gpt-6.2-sol' : 'sonnet',
    permissionMode: 'default',
    costUsd: cost,
    tokensIn: 0,
    tokensOut: 0,
    startedAt: DateTime(2026, 11, 21, 14),
  );

  test('a day with only Codex sessions shows "indisponível", not \$0.00', () {
    expect(formatRunsCost([run('codex', 0), run('codex', 0)]), 'indisponível');
  });

  test('Claude and Codex together: the Claude sum with " +"', () {
    expect(formatRunsCost([run('claude', 0.01), run('codex', 0)]), '\$0.01 +');
  });

  test('only Claude, or no session at all, stays in dollars', () {
    expect(formatRunsCost([run('claude', 1.5), run('claude', 0.25)]), '\$1.75');
    expect(formatRunsCost(const []), '\$0.00');
  });
}
