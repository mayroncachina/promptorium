import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/ai_memory_cli.dart';
import 'package:promptorium/core/memory/ai_memory_state.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/ai_memory_view.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-098 T1: Configurações → Memória (ai-memory), the four states of
/// the detection with the command to copy (R1) and the "não encontrado"
/// card (R2).
void main() {
  Future<(ProviderContainer, List<String>)> pump(
    WidgetTester tester,
    AiMemoryDetection d,
  ) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    var detections = 0;
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        aiMemoryEnvironmentProvider.overrideWithValue({'HOME': '/home/u'}),
        aiMemoryDetectionProvider.overrideWith((ref) async {
          detections++;
          return d;
        }),
        aiMemoryOpenerProvider.overrideWithValue((t) async => opened.add(t)),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AiMemorySettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(detections, 1);
    return (c, opened);
  }

  testWidgets('R2: without the binary only a "não encontrado" card with the '
      'project link', (tester) async {
    final (_, opened) = await pump(tester, AiMemoryDetection.notInstalled);
    expect(find.text('ai-memory'), findsOneWidget);
    expect(find.text('não encontrado'), findsOneWidget);
    expect(find.textContaining('sem ele nada muda no app'), findsOneWidget);
    expect(find.textContaining('install.sh | sh'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-memory-github')));
    expect(opened, [aiMemoryRepoUrl]);
  });

  testWidgets('R1: servidor parado shows systemctl and copies it', (
    tester,
  ) async {
    await pump(
      tester,
      const AiMemoryDetection(
        status: AiMemoryStatus.serverDown,
        executable: '/home/u/.local/bin/ai-memory',
        version: '3.5.1',
      ),
    );
    expect(find.text('ai-memory 3.5.1'), findsOneWidget);
    expect(find.text('servidor parado'), findsOneWidget);
    expect(find.text(aiMemoryStartCommand), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-memory-copy-fix')));
    await tester.pump();
    expect(copied, aiMemoryStartCommand);
  });

  testWidgets('R1: versão antiga shows the minimum and ai-memory upgrade', (
    tester,
  ) async {
    await pump(
      tester,
      const AiMemoryDetection(
        status: AiMemoryStatus.outdated,
        executable: '/usr/bin/ai-memory',
        version: '3.0.2',
      ),
    );
    expect(find.text('ai-memory 3.0.2'), findsOneWidget);
    expect(find.text('versão antiga'), findsOneWidget);
    expect(find.textContaining('Mínima: 3.1.0'), findsOneWidget);
    expect(find.text(aiMemoryUpgradeCommand), findsOneWidget);
  });

  testWidgets('R1: conectado shows binary and server, "Verificar de novo" '
      'detects again', (tester) async {
    final (c, _) = await pump(
      tester,
      const AiMemoryDetection(
        status: AiMemoryStatus.connected,
        executable: '/home/u/.local/bin/ai-memory',
        version: '3.5.1',
      ),
    );
    expect(find.text('conectado'), findsOneWidget);
    expect(
      find.textContaining('~/.local/bin/ai-memory  ·  http://127.0.0.1:49374'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai-memory-fix')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-memory-recheck')));
    await tester.pumpAndSettle();
    // The cached detection was dropped and ran again.
    expect(
      c.read(aiMemoryDetectionProvider).value?.status,
      AiMemoryStatus.connected,
    );
  });

  test('P8: a section "Memória (ai-memory)" in the app group', () {
    final s = SettingsSection.aiMemory;
    expect(s.label, 'Memória (ai-memory)');
    expect(s.group, SettingsGroup.app);
    expect(filterSections('handoff'), contains(s));
    final i = SettingsSection.values.indexOf(s);
    expect(SettingsSection.values[i - 1], SettingsSection.providers);
  });
}
