import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_memory.dart';
import 'package:promptorium/features/project/widgets/project_memory_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

void main() {
  test('round trip with origin and date; add moves duplicates, replaces, '
      'caps at 60; clear old', () {
    final m = ProjectMemory.parse('''
# Memória do projeto

- `flutter test` (testes) passa em ~50 s  <!-- verificação, 2026-09-01 -->
- Use drift para o banco  <!-- SPEC-002 R1, 2026-10-16 -->
- linha sem metadados
''');
    expect(m.entries.map((e) => e.origin), [
      'verificação',
      'SPEC-002 R1',
      'você',
    ]);
    expect(m.entries.first.date, DateTime(2026, 9, 1));
    final back = ProjectMemory.parse(m.toMarkdown());
    expect(
      back.entries.map((e) => e.toLine()),
      m.entries.map((e) => e.toLine()),
    );
    expect(
      m.toPrompt(),
      startsWith('- `flutter test` (testes) passa em ~50 s\n'),
    );

    final faster = m.add(
      MemoryEntry(
        text: '`flutter test` (testes) passa em ~40 s',
        origin: 'verificação',
        date: DateTime(2026, 10, 17),
      ),
      replacing: (e) => e.text.startsWith('`flutter test` (testes)'),
    );
    expect(faster.entries, hasLength(3));
    expect(faster.entries.last.text, contains('~40 s'));

    var big = const ProjectMemory([]);
    for (var i = 0; i < 70; i++) {
      big = big.add(MemoryEntry(text: 'fato $i'));
    }
    expect(big.entries, hasLength(ProjectMemory.maxEntries));
    expect(big.entries.first.text, 'fato 10');

    final cleaned = m.withoutOlderThan(
      const Duration(days: 30),
      now: DateTime(2026, 10, 17),
    );
    expect(cleaned.entries.map((e) => e.origin), ['SPEC-002 R1', 'você']);
    expect(
      parseLearning('ok\nAPRENDIZADO: rode build_runner\nETAPA CONCLUÍDA: R1'),
      'rode build_runner',
    );
    expect(parseLearning('sem nada'), isNull);
  });

  testWidgets('Memória: add, remove and clear old lines', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-mem-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ws = Workspace(
      id: 1,
      path: tmp.path,
      name: 'w',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: ProjectMemoryView(workspace: ws)),
        ),
      ),
    );
    Future<void> io([Finder? until]) async {
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (i >= 5 && (until == null || until.evaluate().isNotEmpty)) return;
      }
    }

    await io(find.text('Nada anotado ainda.'));
    expect(find.text('Nada anotado ainda.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('memory-new')),
      'docker precisa estar rodando',
    );
    await tester.tap(find.byKey(const ValueKey('memory-add')));
    await io(find.text('docker precisa estar rodando'));
    expect(find.text('docker precisa estar rodando'), findsOneWidget);
    final file = File('${tmp.path}/${ProjectMemory.filePath}');
    expect(file.readAsStringSync(), contains('- docker precisa estar rodando'));
    await tester.tap(find.byKey(const ValueKey('memory-remove-0')));
    await io(find.text('Nada anotado ainda.'));
    expect(find.text('Nada anotado ainda.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
