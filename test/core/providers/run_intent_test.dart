import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/providers/structured_run.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_command.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/permission_policy.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';

import '../codex/fake_codex.dart';
import '../../helpers/test_db.dart';
import '../../features/sessions/session_test_utils.dart' show settle;

void main() {
  group('intenção + extras (SPEC-094 R4, R5)', () {
    const claudeOnly = ClaudeExtras(
      maxBudgetUsd: 2,
      maxTurns: 8,
      agent: 'revisor',
      mcpAllowedTools: ['mcp__a__b'],
    );

    test('o Codex não recebe extras do Claude', () {
      expect(extrasFor(ProviderCapabilities.codex, claude: claudeOnly), isNull);
      const codex = CodexExtras(compactLimit: '200k');
      expect(
        extrasFor(ProviderCapabilities.codex, claude: claudeOnly, codex: codex),
        same(codex),
      );
    });

    test('o Claude recebe só o que suporta', () {
      final e = extrasFor(
        ProviderCapabilities.claude,
        claude: claudeOnly,
      ) as ClaudeExtras;
      expect(e.maxBudgetUsd, 2);
      expect(e.agent, 'revisor');
      expect(
        extrasFor(ProviderCapabilities.acp('g', 'G'), claude: claudeOnly),
        isNull,
      );
    });

    test('opção do Claude vira flag do Claude', () {
      final cli = ClaudeCodeProvider.optionsFor(
        const AgentStartOptions(
          workingDirectory: '/w',
          mode: PromptMode.edit,
          appMcpConfigs: ['/run/mcp.json'],
          extras: ClaudeExtras(maxBudgetUsd: 1.5, mcpConfigs: ['/u.json']),
        ),
      );
      expect(cli.maxBudgetUsd, 1.5);
      expect(cli.mcpConfigs, ['/run/mcp.json', '/u.json']);
      expect(cli.permissionMode, ClaudePermissionMode.acceptEdits);
    });
  });

  group('falhar fechado (R6)', () {
    test('extras do Claude no Codex fazem o teste falhar', () {
      expect(
        () => CodexProvider.validateOptions(
          const AgentStartOptions(
            workingDirectory: '/w',
            mode: PromptMode.ask,
            extras: ClaudeExtras(maxBudgetUsd: 2),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => CodexProvider.validateOptions(
          const AgentStartOptions(
            workingDirectory: '/w',
            mode: PromptMode.ask,
            appMcpConfigs: ['/run/mcp.json'],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('extras do Codex no Claude e no ACP também', () {
      expect(
        () => ClaudeCodeProvider.optionsFor(
          const AgentStartOptions(
            workingDirectory: '/w',
            mode: PromptMode.ask,
            extras: CodexExtras(sandbox: 'read-only'),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        AcpProvider(id: 'g', displayName: 'G', command: const ['g']).start(
          const AgentStartOptions(
            workingDirectory: '/w',
            mode: PromptMode.ask,
            extras: ClaudeExtras(agent: 'x'),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('acesso → política (R7)', () {
    test('Codex: valores comprovados pela SPEC-093', () {
      expect(codexAccessPolicy(AgentAccess.ask), (
        sandbox: 'read-only',
        approval: 'never',
      ));
      expect(codexAccessPolicy(AgentAccess.plan), (
        sandbox: 'read-only',
        approval: 'never',
      ));
      expect(codexAccessPolicy(AgentAccess.edit), (
        sandbox: 'workspace-write',
        approval: 'on-request',
      ));
      expect(codexAccessPolicy(AgentAccess.refine).approval, 'untrusted');
      expect(codexAccessPolicy(AgentAccess.yolo), (
        sandbox: 'danger-full-access',
        approval: 'never',
      ));
      // `-a untrusted` sai com código 2 na CLI 0.170.
      expect(codexCliPolicy(AgentAccess.refine).approval, 'on-request');
      expect(
        codexCommandArgs(permissionMode: ClaudePermissionMode.defaultMode),
        isNot(contains('untrusted')),
      );
      expect(
        () => codexCommandArgs(permissionMode: ClaudePermissionMode.dontAsk),
        throwsA(isA<AgentUnavailable>()),
      );
    });

    test('Claude: acesso → --permission-mode', () {
      expect(
        ClaudeCodeProvider.permissionModeFor(AgentAccess.plan),
        ClaudePermissionMode.plan,
      );
      expect(
        ClaudeCodeProvider.permissionModeFor(AgentAccess.yolo),
        ClaudePermissionMode.skipPermissions,
      );
      expect(
        AgentStartOptions.forAccess(
          AgentAccess.yolo,
          workingDirectory: '/w',
        ).access,
        AgentAccess.yolo,
      );
    });
  });

  test('review automático com o Codex não monta orçamento nem agente e '
      'não é barrado pelo validateOptions (R4–R6)', () async {
    final servers = <FakeCodex>[];
    final c = ProviderContainer(
      overrides: [
        providerFlowsProvider.overrideWithValue(
          ProviderFlows.defaults.copyWith('codex', {AppFlow.autoReview}),
        ),
        databaseOverride(memoryDatabase()),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final s = FakeCodex();
          servers.add(s);
          return s;
        }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(12), 'codex');
    final review = Provider(
      (ref) =>
          () => runStructured(
            ref,
            StructuredIntent(
              cwd: '/work',
              workspaceId: 12,
              flow: AppFlow.autoReview,
              // What the reviewer builds (DT-56).
              claude: const ClaudeStructuredExtras(
                maxBudgetUsd: 2,
                agent: 'revisor',
              ),
              schema: _okSchema,
              prompt: 'Revise',
            ),
          ),
    );
    final response = c.read(review)();
    await settle();
    final turn = servers.single.writtenJson.singleWhere(
      (r) => r['method'] == 'turn/start',
    );
    expect(turn['params']['outputSchema'], _okSchema);
    servers.single.answer('{"ok":true}');
    servers.single.completeTurn();
    expect((await response).isSuccess, isTrue);

    // Same run in a flow Codex is not released in: refused with the reason.
    final other = Provider(
      (ref) =>
          () => runStructured(
            ref,
            StructuredIntent(cwd: '/work', workspaceId: 12, prompt: 'x'),
          ),
    );
    await expectLater(
      c.read(other)(),
      throwsA(
        isA<PlannerException>().having(
          (e) => e.message,
          'message',
          contains('ainda não roda com o Codex'),
        ),
      ),
    );
    expect(servers, hasLength(1));
  });
}

/// A schema already in the strict form the Codex takes (SPEC-100 R3).
const _okSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'ok': {'type': 'boolean'},
  },
  'required': ['ok'],
  'additionalProperties': false,
};
