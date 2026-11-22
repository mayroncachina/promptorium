import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/claude/run_prefs.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';

import '../codex/fake_codex.dart';
import '../../helpers/test_db.dart';

ProcessRunner _codex(String version) => (exe, args) async {
  if (args.first == '--version') {
    return ProcessResult(1, 0, 'codex-cli $version', '');
  }
  return ProcessResult(1, 0, 'ok', '');
};

const _fixtures = 'test/fixtures/codex/0.170';

void main() {
  group('versão mínima (SPEC-094 R10)', () {
    test('0.168 fica incompatível com a orientação', () async {
      final a = await inspectProvider(CodexProvider(), _codex('0.168.0'));
      expect(a.status, ProviderStatus.incompatible);
      expect(a.message, contains('Versão instalada 0.168.0, mínimo 0.170'));
      expect(a.message, contains('codex update'));
    });

    test('0.170 funciona sem aviso; acima funciona com aviso', () async {
      final ok = await inspectProvider(CodexProvider(), _codex('0.170.3'));
      expect(ok.status, ProviderStatus.ready);
      expect(ok.warning, isNull);
      final newer = await inspectProvider(CodexProvider(), _codex('0.172.0'));
      expect(newer.status, ProviderStatus.ready);
      expect(newer.warning, 'versão mais nova que a testada (0.170)');
    });

    test('método ausente deixa incompatível, nomeando o método', () async {
      final a = await inspectProvider(
        CodexProvider(),
        _codex('0.171.0'),
        missingMethods: (exe, v) async => ['turn/steer'],
      );
      expect(a.status, ProviderStatus.incompatible);
      expect(a.message, contains('turn/steer'));
    });

    test('a conferência lê os métodos do schema gerado', () async {
      final dir = await Directory.systemTemp.createTemp('schema-');
      addTearDown(() => dir.delete(recursive: true));
      final methods = [...codexAdapterMethods]..remove('turn/steer');
      File('${dir.path}/ClientRequest.json').writeAsStringSync(
        jsonEncode({
          'oneOf': [
            for (final m in methods)
              {
                'properties': {
                  'method': {
                    'enum': [m],
                  },
                },
              },
          ],
        }),
      );
      expect(await missingMethodsIn(dir.path), ['turn/steer']);
    });
  });

  group('sandbox disponível (R7a)', () {
    test('configWarning no initialize = sandbox indisponível, sem turno', () async {
      final fake = FakeCodex.replay(
        readCodexTranscript('$_fixtures/sandbox.jsonl'),
        fallback: {
          'model/list': {
            'data': [
              {
                'id': 'gpt-5.6-luna',
                'inputModalities': ['text', 'image'],
                'supportedReasoningEfforts': [
                  {'reasoningEffort': 'low'},
                ],
              },
            ],
          },
        },
      );
      final h = await codexHandshake(
        executable: 'codex',
        starter: (exe, args, {workingDirectory, environment}) async => fake,
      );
      expect(h.sandboxAvailable, isFalse);
      expect(h.sandboxWarning, contains('bubblewrap'));
      expect(h.models.single.id, 'gpt-5.6-luna');
      expect(
        fake.writtenJson.map((m) => m['method']),
        isNot(anyOf(contains('turn/start'), contains('thread/start'))),
      );
    });

    test('sem aviso e command/exec com sucesso = sandbox disponível', () async {
      final fake = FakeCodex.replay(
        const [],
        fallback: {
          'command/exec': {'exitCode': 0, 'stdout': '', 'stderr': ''},
          'model/list': {'data': []},
        },
      );
      final h = await codexHandshake(
        executable: 'codex',
        starter: (exe, args, {workingDirectory, environment}) async => fake,
      );
      expect(h.sandboxAvailable, isTrue);
      final exec = fake.writtenJson.singleWhere(
        (m) => m['method'] == 'command/exec',
      );
      expect(exec['params']['command'], ['true']);
      expect(exec['params']['sandboxPolicy'], {'type': 'readOnly'});
    });

    test('inspectProvider repassa o aviso; "Verificar de novo" refaz', () async {
      var calls = 0;
      Future<String?> sandbox(String exe) async {
        calls++;
        return calls == 1 ? 'bwrap sem user namespaces' : null;
      }

      final first = await inspectProvider(
        CodexProvider(),
        _codex('0.170.0'),
        sandbox: sandbox,
      );
      expect(first.sandboxAvailable, isFalse);
      final again = await inspectProvider(
        CodexProvider(),
        _codex('0.170.0'),
        sandbox: sandbox,
      );
      expect(again.sandboxAvailable, isTrue);
    });

    test('a detecção guarda o model/list com a versão (P2)', () async {
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          codexExecutableCandidatesProvider.overrideWithValue(['/mock/codex']),
          processRunnerProvider.overrideWithValue(_codex('0.170.0')),
          codexProcessStarterProvider.overrideWithValue(
            (exe, args, {workingDirectory, environment}) async =>
                FakeCodex.replay(
                  readCodexTranscript('$_fixtures/handshake.jsonl'),
                ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final a = await c.read(providerAvailabilityProvider('codex').future);
      expect(a.status, ProviderStatus.ready);
      expect(a.sandboxAvailable, isFalse);
      final cache = codexModelsCache(c.read(appSettingsProvider))!;
      expect(cache.version, '0.170.0');
      expect(cache.models, isNotEmpty);
    });
  });

  test('modelo salvo que sumiu usa o padrão do provedor (R9)', () {
    final settings = {
      codexModelsCacheKey: CodexModelsCache(
        version: '0.170.0',
        readAt: DateTime(2026, 11, 21, 14, 2),
        models: const [
          CodexModelInfo('gpt-6-luna', ['low'], ['text']),
        ],
      ).encode(),
      'codex.model.conversation': 'gpt-5.9-sol',
      'codex.model.session': 'gpt-6-luna',
    };
    const prefs = RunPrefs({});
    expect(providerModelMissing(settings, 'codex', 'gpt-5.9-sol'), isTrue);
    expect(
      providerModelFrom(prefs, settings, 'codex', RunKind.conversation),
      'inherit',
    );
    expect(
      providerModelFrom(prefs, settings, 'codex', RunKind.session),
      'gpt-6-luna',
    );
    // A Claude alias never goes to the Codex, nor the opposite (R8).
    expect(providerModelFrom(prefs, settings, 'claude', RunKind.session), 'sonnet');
  });
}
