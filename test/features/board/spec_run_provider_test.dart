import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/features/board/spec_run_provider.dart';
import 'package:promptorium/features/review/ci_fixer.dart' show ciFixMode;
import 'package:promptorium/core/providers/run_intent.dart';
import 'package:promptorium/features/sessions/session_manager.dart'
    show sandboxCommitRefusal;

void main() {
  final catalog = {
    codexModelsCacheKey: CodexModelsCache(
      version: '0.170.0',
      readAt: DateTime(2026, 11, 20),
      models: const [
        CodexModelInfo('gpt-6.1-terra', ['low', 'medium'], ['text']),
        CodexModelInfo('gpt-5.6-luna', ['low'], ['text']),
      ],
    ).encode(),
  };

  group('R3: model and effort of a Codex run', () {
    test('never inherit nor a Claude alias; the saved Codex model, else the '
        'first of the catalog', () {
      expect(codexRunModel(catalog), 'gpt-6.1-terra');
      expect(codexRunModel(catalog, requested: 'sonnet'), 'gpt-6.1-terra');
      expect(codexRunModel(catalog, requested: 'inherit'), 'gpt-6.1-terra');
      expect(codexRunModel(catalog, requested: 'gpt-5.6-luna'), 'gpt-5.6-luna');
      expect(
        codexRunModel({...catalog, 'codex.model.session': 'gpt-5.6-luna'}),
        'gpt-5.6-luna',
      );
      // A saved model that left the catalog is not used.
      expect(
        codexRunModel({...catalog, 'codex.model.session': 'gpt-4'}),
        'gpt-6.1-terra',
      );
      // Without the catalog only the provider default is left.
      expect(codexRunModel(const {}), 'inherit');
      expect(
        codexRunEffort(catalog, 'gpt-5.6-luna', requested: 'high'),
        'default',
      );
      expect(
        codexRunEffort(catalog, 'gpt-6.1-terra', requested: 'medium'),
        'medium',
      );
      expect(codexModelEfforts(catalog, 'gpt-6.1-terra'), [
        'default',
        'low',
        'medium',
      ]);
    });
  });

  group('R4: modes of a Codex run', () {
    test('Editar and YOLO; Perguntar and Planejar do not run steps; without '
        'the sandbox only YOLO', () {
      expect(codexRunModes(), [
        ClaudePermissionMode.acceptEdits,
        ClaudePermissionMode.skipPermissions,
      ]);
      expect(codexRunModes(worktree: false), [
        ClaudePermissionMode.acceptEdits,
      ]);
      expect(codexRunModes(sandbox: false), [
        ClaudePermissionMode.skipPermissions,
      ]);
      expect(
        codexRunMode(ClaudePermissionMode.plan),
        ClaudePermissionMode.acceptEdits,
      );
      expect(codexRunMode(null), ClaudePermissionMode.acceptEdits);
      expect(
        codexRunMode(ClaudePermissionMode.acceptEdits, sandbox: false),
        ClaudePermissionMode.skipPermissions,
      );
    });

    test('the CI fix of a Codex session leaves Planejar for Editar, the '
        'equivalent mode', () {
      final mode = ciFixMode(ClaudePermissionMode.plan);
      expect(AgentAccess.fromClaudeMode(mode), AgentAccess.edit);
      expect(
        AgentAccess.fromClaudeMode(
          ciFixMode(ClaudePermissionMode.skipPermissions),
        ),
        AgentAccess.yolo,
      );
    });
  });

  group('R10, P2: continuation limit', () {
    test('the configured limit, capped at 70% of the Codex window', () {
      expect(
        effectiveContinueLimit(150000, provider: 'claude', window: 100),
        150000,
      );
      expect(effectiveContinueLimit(150000, provider: 'codex'), 150000);
      expect(
        effectiveContinueLimit(150000, provider: 'codex', window: 400000),
        150000,
      );
      expect(
        effectiveContinueLimit(150000, provider: 'codex', window: 120000),
        84000,
      );
    });
  });

  group('R14, P3: autopilot brake on the Codex quota', () {
    QuotaSnapshot snap(double pct, {String? reached}) => QuotaSnapshot(
      provider: 'codex',
      main: QuotaBucket(
        id: 'codex',
        reached: reached,
        windows: [
          QuotaWindow(
            id: 'primary',
            label: '5 h',
            usedPercent: pct,
            minutes: 300,
            resetsAt: DateTime(2030),
          ),
        ],
      ),
      ordinaryUsageAllowed: true,
    );

    test('above 90% or with a limit reached', () {
      final now = DateTime(2026, 11, 22);
      expect(codexAutopilotBrake(null, now), isNull);
      expect(codexAutopilotBrake(snap(90), now), isNull);
      expect(
        codexAutopilotBrake(snap(92), now),
        'Autopilot parado: cota do Codex em 92%',
      );
      expect(
        codexAutopilotBrake(snap(40, reached: 'rate_limit_reached'), now),
        'Autopilot parado: cota do Codex em 40%',
      );
    });
  });

  group('R6: Só Claude Code note', () {
    test('names what the Codex runs without', () {
      expect(
        claudeOnlyAgentsNote(agent: 'spec-implementer', subagents: true),
        'O agente spec-implementer e os subagentes desta spec são só do '
        'Claude Code; o Codex executa sem eles.',
      );
      expect(
        claudeOnlyAgentsNote(agent: 'x', subagents: false),
        'O agente x é só do Claude Code; o Codex executa sem ele.',
      );
      expect(
        claudeOnlyAgentsNote(subagents: true),
        'Os subagentes desta spec são só do Claude Code; o Codex executa '
        'sem eles.',
      );
    });
  });

  group('R8: sandbox refusing the commit', () {
    AgentEvent cmd(
      String command,
      String out, {
      CommandStatus status = CommandStatus.failed,
    }) => AgentEvent.fromJson(
      CommandEvent.toJson(
        provider: 'codex',
        toolUseId: 'c1',
        command: command,
        cwd: '/wt/spec-031',
        status: status,
        exitCode: 128,
        output: out,
      ),
    );

    test('a failed git commit with a permission error says the command and '
        'the path', () {
      final e = cmd(
        'git add -A && git commit -m "SPEC-031 R1"',
        "fatal: Não foi possível criar '/repo/.git/worktrees/wt/index.lock': "
            'Permissão negada',
      );
      expect(
        sandboxCommitRefusal(e as CommandEvent),
        'O sandbox do Codex bloqueou o commit: `git add -A && git commit -m '
        '"SPEC-031 R1"` em /repo/.git/worktrees/wt/index.lock. O app commita '
        'o que ficou no fim do turno.',
      );
    });

    test('other commands and other failures are not a refusal', () {
      expect(
        sandboxCommitRefusal(
          cmd('flutter test', 'Permission denied') as CommandEvent,
        ),
        isNull,
      );
      expect(
        sandboxCommitRefusal(
          cmd('git commit -m x', 'nothing to commit') as CommandEvent,
        ),
        isNull,
      );
      expect(
        sandboxCommitRefusal(
          cmd('git commit -m x', 'bwrap: x', status: CommandStatus.completed)
              as CommandEvent,
        ),
        isNull,
      );
    });
  });
}
