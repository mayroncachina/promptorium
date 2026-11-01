import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

void main() {
  test('"Gerar design" asks for "O que já existe" and at least one file per '
      'step (SPEC-017 R3)', () {
    expect(designPrompt, contains('### O que já existe'));
    expect(designPrompt, contains('ao menos um arquivo'));
    final etapa =
        ((designSchema['properties'] as Map)['etapas'] as Map)['items'] as Map;
    final arquivos = (etapa['properties'] as Map)['arquivos'] as Map;
    expect(arquivos['minItems'], 1);
  });

  test('SPEC-025 R5: completing "cancelled" stops the planner run and '
      'generate throws SpecActionCancelled', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-design-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final cli = FakeCli();
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        claudeProcessStarterProvider.overrideWithValue(cli.start),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = Workspace(
      id: 1,
      path: tmp.path,
      name: 'ws',
      createdAt: DateTime(2026),
    );
    final cancel = Completer<void>();
    final run = c
        .read(specDesignerProvider)
        .generate(ws, '# Spec\n', cancelled: cancel.future);
    final rejected = expectLater(run, throwsA(isA<SpecActionCancelled>()));
    await until(() async => cli.processes.isNotEmpty);
    expect(cli.last.signals, isEmpty);
    cancel.complete();
    await rejected;
    // The agent was stopped, not left running.
    expect(cli.last.signals, isNotEmpty);
  });
}
