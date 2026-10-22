import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/run_spec_dialog.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

const _noDesign = '''---
id: SPEC-001
---

# Grande

## Objetivo

Algo.

## Requisitos

- R1 · a
- R2 · b
- R3 · c
- R4 · d
''';

void main() {
  test('the warning: no Design and more steps than one session takes', () {
    expect(needsDesignWarning(_noDesign, maxSingleSession: 3), isTrue);
    expect(needsDesignWarning(_noDesign, maxSingleSession: 4), isFalse);
    expect(
      needsDesignWarning(
        _noDesign.replaceFirst(
          '## Requisitos',
          '## Design\n\n### O que já existe\n- lib/a.dart\n\n## Requisitos',
        ),
        maxSingleSession: 3,
      ),
      isFalse,
    );
    expect(needsDesignWarning(null, maxSingleSession: 3), isFalse);
  });

  testWidgets('"Executar" without Design: Cancelar does nothing, "Gerar '
      'design" opens Specs on the spec to generate it (SPEC-017 R3)', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-nodesign-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-001.md').writeAsStringSync(_noDesign);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    final spec = await tester.runAsync(() async {
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: tmp.path, name: 'w');
      return c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-001',
            title: 'Grande',
            path: 'specs/SPEC-001.md',
          );
    });
    final data = SpecCardData(
      spec: spec!,
      steps: const [],
      sessions: const [],
      blockers: const [],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                key: const ValueKey('run'),
                onPressed: () => runSpec(context, ref, data),
                child: const Text('Executar'),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.byKey(const ValueKey('run')));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await open();
    expect(find.byKey(const ValueKey('run-no-design-dialog')), findsOneWidget);
    expect(find.textContaining('Com 4 etapas'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('run-no-design-dialog')), findsNothing);
    expect(c.read(pendingDesignProvider), isNull);

    await open();
    await tester.tap(find.byKey(const ValueKey('run-no-design-generate')));
    await tester.pumpAndSettle();
    expect(c.read(pendingDesignProvider), spec.id);
    expect(c.read(selectedSpecProvider), spec.id);
    expect(c.read(navigationProvider), AppSection.specs);
    expect(tester.takeException(), isNull);
  });
}
