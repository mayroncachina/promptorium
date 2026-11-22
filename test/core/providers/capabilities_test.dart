import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_registry.dart';

import '../../helpers/test_db.dart';

void main() {
  group('ProviderCapabilities (SPEC-094 R1, R2)', () {
    test('Claude e Codex declaram todos os campos de R1', () {
      for (final caps in [
        ProviderCapabilities.claude,
        ProviderCapabilities.codex,
      ]) {
        for (final c in ProviderCapability.values) {
          expect(
            caps.values.containsKey(c),
            isTrue,
            reason: '${caps.providerId} sem ${c.name}',
          );
        }
      }
    });

    test('Codex segue a tabela comprovada no 0.170', () {
      const caps = ProviderCapabilities.codex;
      const supported = CapabilitySupport.supported;
      const partial = CapabilitySupport.partial;
      const no = CapabilitySupport.unsupported;
      final expected = {
        ProviderCapability.images: supported,
        ProviderCapability.structuredOutput: supported,
        ProviderCapability.budgetUsd: no,
        ProviderCapability.maxTurns: no,
        ProviderCapability.planMode: no,
        ProviderCapability.readOnlyEnforced: partial,
        ProviderCapability.managedHooks: no,
        ProviderCapability.agentFiles: no,
        // "não testada" = não suportada (R2).
        ProviderCapability.subagents: no,
        ProviderCapability.mcpConfig: partial,
        ProviderCapability.appMcpServer: no,
        ProviderCapability.compactNow: supported,
        ProviderCapability.steerMidTurn: partial,
        ProviderCapability.liveApprovalChange: supported,
        ProviderCapability.quota: supported,
        ProviderCapability.costUsd: no,
        ProviderCapability.nativeReview: no,
        ProviderCapability.revertConversation: no,
      };
      expected.forEach((c, s) => expect(caps[c].support, s, reason: c.name));
      expect(caps.reasonFor(ProviderCapability.budgetUsd), contains('US\$'));
    });

    test('campo ausente conta como não suportado', () {
      final acp = ProviderCapabilities.acp('gemini', 'Gemini CLI');
      expect(acp.supports(ProviderCapability.structuredOutput), isFalse);
      expect(acp.supports(ProviderCapability.quota), isFalse);
      expect(acp.supports(ProviderCapability.costUsd), isFalse);
      expect(acp[ProviderCapability.quota].reason, 'não testada');
    });

    test('modelo sobrescreve só imagens e esforços (P5)', () {
      final m = ProviderCapabilities.codex.forModel(
        modalities: const ['text'],
        efforts: const ['low', 'max'],
      );
      expect(m.supports(ProviderCapability.images), isFalse);
      expect(m.efforts, ['low', 'max']);
      expect(m.supports(ProviderCapability.structuredOutput), isTrue);
    });

    test('cada adaptador expõe as suas capacidades', () {
      expect(
        ClaudeCodeProvider().capabilities,
        same(ProviderCapabilities.claude),
      );
      expect(CodexProvider().capabilities, same(ProviderCapabilities.codex));
      expect(
        AcpProvider(
          id: 'g',
          displayName: 'G',
          command: const ['g'],
        ).capabilities.supports(ProviderCapability.structuredOutput),
        isFalse,
      );
    });
  });

  group('providerFlows (R3)', () {
    test('SPEC-096 R1: o Codex roda só em Prompt e Sessões', () {
      for (final f in AppFlow.values) {
        expect(
          ProviderFlows.defaults.allows('codex', f),
          f == AppFlow.prompt || f == AppFlow.sessions,
          reason: f.name,
        );
        expect(ProviderFlows.defaults.allows('claude', f), isTrue);
      }
      // Each flow still locked names the spec that releases it (mock 4).
      expect(codexFlowSpecs.keys, isNot(contains(AppFlow.prompt)));
      expect(codexFlowSpecs[AppFlow.runSpec], 'SPEC-101');
      expect(flowLockedLabel('Codex'), 'Codex · Só Claude Code por enquanto');
    });

    test('ligar um fluxo não liga os outros', () {
      final f = ProviderFlows.defaults.copyWith('codex', {
        AppFlow.prompt,
        AppFlow.sessions,
      });
      expect(f.allows('codex', AppFlow.prompt), isTrue);
      expect(f.allows('codex', AppFlow.runSpec), isFalse);
    });

    test('o Codex fica registrado e o fluxo fechado recusa com motivo', () {
      final c = ProviderContainer(
        overrides: [databaseOverride(memoryDatabase())],
      );
      addTearDown(c.dispose);
      final all = c.read(agentProvidersProvider);
      expect(all.whereType<CodexProvider>(), hasLength(1));
      final probe = Provider(
        (ref) =>
            () => agentProviderForFlow(ref, 'codex', AppFlow.autoReview),
      );
      expect(
        () => c.read(probe)(),
        throwsA(
          isA<AgentUnavailable>().having(
            (e) => e.message,
            'message',
            allOf(contains('Review automático'), contains('Claude Code')),
          ),
        ),
      );
    });
  });
}
