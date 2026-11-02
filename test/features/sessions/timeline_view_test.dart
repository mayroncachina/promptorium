import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/features/sessions/edit_diff.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/timeline_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

Map<String, dynamic> _use(String id, String name, Map<String, dynamic> i) => {
  'type': 'assistant',
  'message': {
    'id': 'm-$id',
    'role': 'assistant',
    'content': [
      {'type': 'tool_use', 'id': id, 'name': name, 'input': i},
    ],
  },
  'parent_tool_use_id': null,
  'session_id': 's',
};

Map<String, dynamic> _result(String id, String content, {bool error = false}) =>
    {
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': id,
            'content': content,
            'is_error': error,
          },
        ],
      },
      'parent_tool_use_id': null,
      'session_id': 's',
    };

const _ok = 'The file /w/a.md has been updated successfully.';

List<TimelineItem> _items() {
  final t = Timeline();
  for (final l in [
    _use('e1', 'Edit', {
      'file_path': '/w/a.md',
      'old_string': '- R3 · velho',
      'new_string': '- R3 · novo',
    }),
    _result('e1', _ok),
    _use('e2', 'Edit', {
      'file_path': '/w/a.md',
      'old_string': 'não existe',
      'new_string': 'x',
    }),
    _result('e2', 'String to replace not found in file.', error: true),
  ]) {
    for (final e in ClaudeEvent.expand(l)) {
      t.apply(e);
    }
  }
  return t.items;
}

Future<void> _pump(
  WidgetTester tester, {
  EditInfo? Function(ToolItem)? editInfo,
}) async {
  tester.view.physicalSize = const Size(1100, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: TimelineListView(items: _items(), root: '/w', editInfo: editInfo),
      ),
    ),
  );
}

void main() {
  testWidgets('a finished Edit expands into its diff, not "has been updated '
      'successfully"; a failed one shows the tool_result (SPEC-026 R2)', (
    tester,
  ) async {
    await _pump(tester);
    final card = find.byKey(const ValueKey('tool-e1'));
    expect(find.descendant(of: card, matching: find.text('a.md')), findsOne);
    await tester.tap(find.byKey(const ValueKey('tool-toggle-e1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-diff-e1')), findsOneWidget);
    expect(find.text('- R3 · velho'), findsOneWidget);
    expect(find.text('- R3 · novo'), findsOneWidget);
    expect(find.textContaining('has been updated successfully'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tool-toggle-e2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-diff-e2')), findsNothing);
    expect(find.text('String to replace not found in file.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a known spec shows "<código> · <seção>" in the target (R2)', (
    tester,
  ) async {
    await _pump(
      tester,
      editInfo: (t) =>
          t.id == 'e1' ? const EditInfo(target: 'SPEC-024 · Requisitos') : null,
    );
    expect(find.text('SPEC-024 · Requisitos'), findsOneWidget);
  });

  testWidgets('each diff line has its sign and accessible label; the card '
      'announces whether it is expanded and opens with Enter and Space (R9)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final toggle = find.byKey(const ValueKey('tool-toggle-e1'));
    SemanticsNode node() => tester.getSemantics(
      find.ancestor(of: toggle, matching: find.byType(Semantics)).first,
    );
    expect(
      node(),
      isSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );

    // Tab focus, then Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-diff-e1')), findsOneWidget);
    expect(node(), isSemantics(hasExpandedState: true, isExpanded: true));
    expect(
      find.bySemanticsLabel('linha removida: - R3 · velho'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('linha adicionada: - R3 · novo'),
      findsOneWidget,
    );
    expect(find.text('-'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);

    // Space closes it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-diff-e1')), findsNothing);
    handle.dispose();
  });
}
