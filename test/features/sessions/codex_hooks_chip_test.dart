import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/codex/codex_hooks.dart';
import 'package:promptorium/core/providers/agent_event.dart' show UnknownEvent;
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/codex_hooks_chip.dart';
import 'package:promptorium/features/sessions/widgets/timeline_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

/// SPEC-103 R9 (chip of the session) and P4 (badge of the hook cards).
void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    CodexHookStatus? status,
  }) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    if (status != null) {
      c.read(codexHookStatusProvider.notifier).set('s1', status);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  final all = ManagedHook.values.toSet();

  testWidgets('nativos: teal chip; the list shows the Codex events', (
    tester,
  ) async {
    await pump(
      tester,
      const CodexHooksChip(sessionId: 's1'),
      status: CodexHookStatus(
        mode: CodexHookMode.native,
        planned: all,
        active: all,
        at: DateTime(2026, 11, 21, 14, 12),
      ),
    );
    expect(find.text('Hooks nativos'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Hooks nativos'));
    expect(label.style?.color, codexHookModeColor(CodexHookMode.native));
    await tester.tap(find.byKey(const ValueKey('codex-hooks-chip-s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('codex-hooks-dialog')), findsOneWidget);
    expect(find.text('hooks/list · 14:12'), findsOneWidget);
    Text row(ManagedHook h) =>
        tester.widget<Text>(find.byKey(ValueKey('codex-hooks-row-${h.name}')));
    expect(row(ManagedHook.block).data, 'preToolUse');
    expect(row(ManagedHook.format).data, 'postToolUse');
    expect(row(ManagedHook.end).data, 'sessionEnd');
    expect(find.textContaining('sessionFlags'), findsOneWidget);
  });

  testWidgets('só pós-turno: amber chip; each hook with its substitute and '
      'the reason; YOLO has no prior block', (tester) async {
    await pump(
      tester,
      const CodexHooksChip(sessionId: 's1', yolo: true),
      status: CodexHookStatus(
        mode: CodexHookMode.postTurn,
        planned: all,
        reason: codexUntrustedReason,
        at: DateTime.now(),
      ),
    );
    final label = tester.widget<Text>(find.text('Hooks só pós-turno'));
    expect(label.style?.color, codexHookModeColor(CodexHookMode.postTurn));
    await tester.tap(find.byKey(const ValueKey('codex-hooks-chip-s1')));
    await tester.pumpAndSettle();
    Text row(ManagedHook h) =>
        tester.widget<Text>(find.byKey(ValueKey('codex-hooks-row-${h.name}')));
    expect(row(ManagedHook.secrets).data, hookSubstitute(ManagedHook.secrets));
    expect(row(ManagedHook.format).data, hookSubstitute(ManagedHook.format));
    expect(row(ManagedHook.end).data, hookSubstitute(ManagedHook.end));
    expect(row(ManagedHook.block).data, 'indisponível no YOLO');
    expect(find.textContaining(codexUntrustedReason), findsOneWidget);
  });

  testWidgets('no state (Claude session, or not started) = no chip', (
    tester,
  ) async {
    await pump(tester, const CodexHooksChip(sessionId: 's1'));
    expect(find.byKey(const ValueKey('codex-hooks-chip-s1')), findsNothing);
  });

  testWidgets('P4: a hook card of a Codex session carries the badge; a '
      'Claude one does not', (tester) async {
    await pump(
      tester,
      Column(
        children: [
          TimelineItemView(
            item: NoticeItem(
              'Hook bloqueou `git push --force` (git push --force)',
              level: NoticeLevel.error,
              provider: 'codex',
            ),
          ),
          TimelineItemView(item: NoticeItem('Formatado: lib/a.dart')),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('notice-provider-codex')), findsOneWidget);
  });

  test('P4: the stored note keeps the provider for the timeline', () {
    final t = Timeline()
      ..apply(
        UnknownEvent(
          AppEventTypes.noteMessage('Formatado: a', provider: 'codex'),
        ),
      );
    expect((t.items.single as NoticeItem).provider, 'codex');
  });
}
