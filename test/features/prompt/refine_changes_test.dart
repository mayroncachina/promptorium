import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/conversations_repo.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/prompt/refine_changes.dart';
import 'package:promptorium/features/prompt/refine_origin.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prompt_test_utils.dart';

const _root = '/work/repo';
const _rel = 'docs/specs/SPEC-024-acoes.md';
const _abs = '$_root/$_rel';

const _base =
    '---\n'
    'id: SPEC-024\n'
    'status: rascunho\n'
    '---\n'
    '# Ações da spec mais claras\n'
    '\n'
    '## Objetivo\n'
    '\n'
    'O cabeçalho mistura modos.\n'
    '\n'
    '## Requisitos\n'
    '\n'
    '- R1 · O cabeçalho deve separar modos.\n'
    '- R2 · Uma ação primária por estado.\n'
    '- R3 · Nenhum rótulo de ação deve ser truncado.\n'
    '\n'
    '## Critérios de aceite\n'
    '\n'
    '- [ ] Os rótulos aparecem inteiros.\n'
    '- [ ] Um teste qualquer [R1]\n';

final _e1 = {
  'file_path': _abs,
  'old_string': '- R3 · Nenhum rótulo de ação deve ser truncado.',
  'new_string':
      '- R3 · Quando a janela tiver 1100×700, nenhum rótulo é truncado.\n'
      '- R4 · Quando as ações não couberem, vão para "Mais ações".',
};
final _e2 = {
  'file_path': _abs,
  'old_string': '- [ ] Os rótulos aparecem inteiros.',
  'new_string':
      '- [ ] A 1100×700, nenhum rótulo termina em reticências [R3]\n'
      '- [ ] Com a janela estreita, Arquivar vai para "Mais ações" [R4]\n'
      '- [ ] Cada estado tem uma única ação primária [R2]',
};
final _e3 = {
  'file_path': _abs,
  'old_string': '- [ ] Um teste qualquer [R1]',
  'new_string':
      '- [ ] Um teste qualquer [R1]\n\n## Fora do escopo\n\n'
      '- O diálogo "Nova spec" não muda.',
};

String _apply(String text, List<Map<String, dynamic>> edits) {
  for (final e in edits) {
    text = text.replaceFirst(
      e['old_string'] as String,
      e['new_string'] as String,
    );
  }
  return text;
}

Map<String, dynamic> _assistant(
  List<Map<String, dynamic>> content,
  String id,
) => {
  'type': 'assistant',
  'message': {'id': id, 'role': 'assistant', 'content': content},
  'parent_tool_use_id': null,
  'session_id': 'conv-sid',
};

Map<String, dynamic> _use(String id, String name, Map<String, dynamic> i) =>
    _assistant([
      {'type': 'tool_use', 'id': id, 'name': name, 'input': i},
    ], 'm-$id');

Map<String, dynamic> _result(String id, {bool error = false, String? text}) => {
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      {
        'type': 'tool_result',
        'tool_use_id': id,
        'content': text ?? 'The file $_abs has been updated successfully.',
        'is_error': error,
      },
    ],
  },
  'parent_tool_use_id': null,
  'session_id': 'conv-sid',
};

/// [SpecService] over an in-memory map of files.
class _MemorySpecs extends SpecService {
  _MemorySpecs(super.repo, this.files);

  final Map<String, String> files;
  int syncs = 0;

  @override
  Future<String?> read(Workspace ws, Spec spec) async => files[spec.path];

  @override
  String? readSync(Workspace ws, Spec spec) => files[spec.path];

  @override
  Future<void> sync(Workspace ws) async => syncs++;
}

class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(navigationProvider);
    return s == AppSection.prompt
        ? const PromptScreen()
        : Text('section:${s.name}', key: const ValueKey('host-section'));
  }
}

typedef _Setup = ({
  AppDatabase db,
  ProviderContainer c,
  FakeCli cli,
  _MemorySpecs specs,
});

/// Prompt screen with a refine conversation of SPEC-024 whose stored events
/// are [events] (JSON lines, in order).
Future<_Setup> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> events = const [],
  String? base = _base,
  String? file,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final cli = FakeCli();
  final ws = await addWorkspace(db, _root);
  await db
      .into(db.specs)
      .insert(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: 'SPEC-024',
          title: 'Ações da spec mais claras',
          path: _rel,
        ),
      );
  final conv = await db
      .into(db.conversations)
      .insertReturning(
        ConversationsCompanion.insert(
          workspaceId: ws.id,
          title: 'Refinar SPEC-024',
          model: 'sonnet',
          mode: const Value('refine'),
          claudeSessionId: const Value('conv-sid'),
          refineSpecCode: const Value('SPEC-024'),
          refineOrigin: const Value('specs'),
          refineBaseText: Value(base),
          updatedAt: Value(DateTime.now()),
        ),
      );
  final repo = ConversationsRepo(db);
  await repo.appendEvent(
    conv.id,
    type: AppEventTypes.user,
    json: jsonEncode(
      AppEventTypes.userMessage('Refine a spec @$_rel', DateTime.now()),
    ),
  );
  for (final e in events) {
    await repo.appendEvent(conv.id, type: '${e['type']}', json: jsonEncode(e));
  }
  late _MemorySpecs specs;
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      workspaceFilesProvider.overrideWith((ref, root) async => const []),
      specServiceProvider.overrideWith(
        (ref) => specs = _MemorySpecs(ref.watch(specsRepoProvider), {
          _rel: file ?? _base,
        }),
      ),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  container.read(navigationProvider.notifier).go(AppSection.prompt);
  container.read(specServiceProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: _Host()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester);
  await tester.tap(find.byKey(ValueKey('conversation-${conv.id}')));
  await pumpFor(tester);
  return (db: db, c: container, cli: cli, specs: specs);
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// A finished turn with the three edits of the mockup.
List<Map<String, dynamic>> _turn({
  List<Map<String, dynamic>> extra = const [],
}) => [
  _assistant([
    {'type': 'text', 'text': 'Vou deixar o R3 verificável.'},
  ], 'm-0'),
  _use('e1', 'Edit', _e1),
  _result('e1'),
  _use('e2', 'Edit', _e2),
  _result('e2'),
  _use('e3', 'Edit', _e3),
  _result('e3'),
  ...extra,
  _assistant([
    {'type': 'text', 'text': 'Pronto. O R3 ficou verificável.'},
  ], 'm-9'),
  resultLine(),
];

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

final _view = find.byKey(const ValueKey('refine-view-changes'));

void main() {
  testWidgets('"Spec em refino" shows the spec and the counts; "Ver '
      'alterações" is disabled until an edit is applied (SPEC-026 R5)', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('refine-panel')), findsOneWidget);
    expect(find.text('SPEC EM REFINO'), findsOneWidget);
    expect(find.text('Ações da spec mais claras'), findsOneWidget);
    expect(_textOf(tester, 'refine-panel-status'), 'Rascunho');
    expect(_textOf(tester, 'refine-panel-applied'), '0');
    expect(_textOf(tester, 'refine-panel-pending'), 'nenhuma');
    expect(_textOf(tester, 'refine-panel-lines'), '+0 −0');
    expect(
      find.ancestor(of: _view, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: _view, matching: find.byType(Tooltip)),
          )
          .message,
      'Nenhuma edição aplicada ainda',
    );
    await tester.tap(_view, warnIfMissed: false);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('refine-changes-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel counts the applied edits and the lines since the '
      'start; the cards show "<código> · <seção>" (R2, R5)', (tester) async {
    await _pump(tester, events: _turn(), file: _apply(_base, [_e1, _e2, _e3]));
    expect(_textOf(tester, 'refine-panel-applied'), '3 edições');
    expect(_textOf(tester, 'refine-panel-denied'), 'nenhuma');
    expect(_textOf(tester, 'refine-panel-lines'), '+9 −2');
    expect(find.text('SPEC-024 · Requisitos'), findsOneWidget);
    expect(find.text('SPEC-024 · Critérios de aceite'), findsOneWidget);
    expect(find.text('SPEC-024 · Fora do escopo'), findsOneWidget);
    expect(find.byType(Tooltip), findsWidgets);
    expect(
      find.ancestor(of: _view, matching: find.byType(Tooltip)),
      findsNothing,
    );
  });

  testWidgets('at the end of a turn with an applied edit, the summary shows '
      'the sections and the requirements touched, "Ver alterações" and '
      '"Voltar à <código>" (R6)', (tester) async {
    final s = await _pump(
      tester,
      events: _turn(),
      file: _apply(_base, [_e1, _e2, _e3]),
    );
    final card = find.byKey(const ValueKey('refine-summary'));
    expect(card, findsOneWidget);
    Finder inCard(String t) =>
        find.descendant(of: card, matching: find.text(t));
    expect(inCard('SPEC-024 atualizada'), findsOneWidget);
    expect(inCard('3 edições aplicadas'), findsOneWidget);
    expect(inCard('+9'), findsOneWidget);
    expect(inCard('−2'), findsOneWidget);
    expect(inCard('Requisitos'), findsOneWidget);
    expect(inCard('R3 reescrito, R4 novo'), findsOneWidget);
    expect(inCard('Critérios de aceite'), findsOneWidget);
    expect(inCard('1 reescrito, 2 novos'), findsOneWidget);
    expect(inCard('Fora do escopo'), findsOneWidget);
    expect(inCard('seção nova'), findsOneWidget);
    expect(inCard('Objetivo'), findsNothing);
    expect(inCard('Ver alterações'), findsOneWidget);
    expect(inCard('Voltar à SPEC-024'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('refine-summary-back')));
    await pumpFor(tester);
    expect(s.c.read(navigationProvider), AppSection.specs);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no summary when the last turn applied nothing to the spec', (
    tester,
  ) async {
    await _pump(
      tester,
      events: [
        _assistant([
          {'type': 'text', 'text': 'Nada a mudar.'},
        ], 'm-0'),
        resultLine(),
      ],
    );
    expect(find.byKey(const ValueKey('refine-summary')), findsNothing);
  });

  testWidgets('the dialog compares the base text with the current file, '
      'folds unchanged runs over 3 lines, switches to "Spec como ficou" and '
      'closes with Esc (R7)', (tester) async {
    await _pump(tester, events: _turn(), file: _apply(_base, [_e1, _e2, _e3]));
    await tester.tap(find.byKey(const ValueKey('refine-summary-view')));
    await pumpFor(tester);
    final dialog = find.byKey(const ValueKey('refine-changes-dialog'));
    expect(dialog, findsOneWidget);
    expect(find.text('Alterações do refino em SPEC-024'), findsOneWidget);
    expect(find.textContaining('3 edições'), findsWidgets);
    expect(find.byKey(const ValueKey('refine-external-warning')), findsNothing);
    final totals = find.byKey(const ValueKey('refine-changes-totals'));
    expect(find.descendant(of: totals, matching: find.text('+9')), findsOne);
    expect(find.descendant(of: totals, matching: find.text('−2')), findsOne);
    // The frontmatter and the objective (more than 3 lines) are folded.
    expect(find.textContaining('linhas sem mudança'), findsWidgets);
    expect(find.text('O cabeçalho mistura modos.'), findsNothing);
    expect(
      find.text('- R3 · Nenhum rótulo de ação deve ser truncado.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mostrar').first);
    await tester.pump();
    expect(find.text('O cabeçalho mistura modos.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('refine-tab-rendered')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('refine-rendered')), findsOneWidget);
    expect(find.byKey(const ValueKey('refine-total-diff')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(tester);
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dialog warns when the spec was also changed outside the '
      'conversation and keeps comparing with the file (R8)', (tester) async {
    final file = '${_apply(_base, [_e1, _e2, _e3])}\nNota de fora.\n';
    await _pump(tester, events: _turn(), file: file);
    await tester.tap(find.byKey(const ValueKey('refine-summary-view')));
    await pumpFor(tester);
    expect(
      find.text('A spec também foi alterada fora desta conversa'),
      findsOneWidget,
    );
    final totals = find.byKey(const ValueKey('refine-changes-totals'));
    expect(find.descendant(of: totals, matching: find.text('+11')), findsOne);
  });

  testWidgets('a conversation without the base text lists the edits one by '
      'one (R8)', (tester) async {
    await _pump(
      tester,
      events: _turn(),
      base: null,
      file: _apply(_base, [_e1, _e2, _e3]),
    );
    expect(_textOf(tester, 'refine-panel-applied'), '3 edições');
    await tester.tap(_view);
    await pumpFor(tester);
    final list = find.byKey(const ValueKey('refine-edits-list'));
    expect(list, findsOneWidget);
    expect(find.byKey(const ValueKey('refine-total-diff')), findsNothing);
    expect(
      find.descendant(of: list, matching: find.text('Edit')),
      findsNWidgets(3),
    );
    expect(find.textContaining('uma a uma'), findsOneWidget);
  });

  test('a refine conversation stores the spec text when it is created '
      '(R8)', () async {
    final db = memoryDatabase();
    final ws = await addWorkspace(db, _root);
    await db
        .into(db.specs)
        .insert(
          SpecsCompanion.insert(
            workspaceId: ws.id,
            code: 'SPEC-024',
            title: 'Ações',
            path: _rel,
          ),
        );
    final c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        conversationManagerProvider.overrideWith(SilentConversationManager.new),
        specServiceProvider.overrideWith(
          (ref) => _MemorySpecs(ref.watch(specsRepoProvider), {
            _rel: '$_base\nsalvo antes de abrir\n',
          }),
        ),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final m = c.read(conversationManagerProvider.notifier);
    final refine = await m.create(
      workspace: ws,
      text: 'refine',
      mode: PromptMode.refine,
      origin: (specCode: 'SPEC-024', source: RefineSource.specs),
    );
    final ask = await m.create(workspace: ws, text: 'pergunta');
    final repo = c.read(conversationsRepoProvider);
    expect(
      (await repo.getById(refine))!.refineBaseText,
      '$_base\nsalvo antes de abrir\n',
    );
    expect((await repo.getById(ask))!.refineBaseText, isNull);
  });

  testWidgets('a denied edit stays in the conversation as "Negada, não '
      'aplicada", with its diff in neutral colors, out of the counts (R1, '
      'R4)', (tester) async {
    final s = await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('prompt-field')),
      'pode editar',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester);
    s.cli.last.emit(jsonEncode(_use('e1', 'Edit', _e1)));
    s.cli.last.emit(
      jsonEncode({
        'type': 'control_request',
        'request_id': 'req-1',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'Edit',
          'input': _e1,
          'tool_use_id': 'e1',
        },
      }),
    );
    await pumpFor(tester);
    // R1: the approval card with the section and the diff.
    expect(find.text('Aprovar esta edição na spec?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approval-section-req-1')),
      findsOneWidget,
    );
    expect(find.text('Aprovar edição'), findsOneWidget);
    expect(_textOf(tester, 'refine-panel-pending'), '1 edição');
    expect(_textOf(tester, 'refine-panel-lines'), '+0 −0');

    await tester.tap(find.byKey(const ValueKey('deny-req-1')));
    await pumpFor(tester);
    s.cli.last.emit(
      jsonEncode(_result('e1', error: true, text: AppEventTypes.deniedMessage)),
    );
    s.cli.last.emit(
      jsonEncode(
        _assistant([
          {'type': 'text', 'text': 'Entendido, mantive.'},
        ], 'm-2'),
      ),
    );
    s.cli.last.emit(jsonEncode(resultLine()));
    await pumpFor(tester);

    expect(find.byKey(const ValueKey('tool-denied-e1')), findsOneWidget);
    expect(find.text('Negada, não aplicada'), findsOneWidget);
    expect(_textOf(tester, 'refine-panel-denied'), '1 edição');
    expect(_textOf(tester, 'refine-panel-applied'), '0');
    expect(_textOf(tester, 'refine-panel-pending'), 'nenhuma');
    expect(_textOf(tester, 'refine-panel-lines'), '+0 −0');
    expect(find.byKey(const ValueKey('refine-summary')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tool-toggle-e1')));
    await pumpFor(tester);
    final diff = find.byKey(const ValueKey('tool-diff-e1'));
    expect(diff, findsOneWidget);
    expect(
      find.descendant(
        of: diff,
        matching: find.text('- R3 · Nenhum rótulo de ação deve ser truncado.'),
      ),
      findsOneWidget,
    );
    final colored = tester
        .widgetList<Container>(
          find.descendant(of: diff, matching: find.byType(Container)),
        )
        .where(
          (c) =>
              c.color == SessionColors.addBg || c.color == SessionColors.delBg,
        );
    expect(colored, isEmpty);
    final plus = tester.widget<Text>(
      find.descendant(of: diff, matching: find.text('+')).first,
    );
    expect(plus.style!.color, AppColors.textDisabled);

    // Stored: the mark survives a reload of the conversation.
    final rows = await s.c.read(conversationsRepoProvider).events(1);
    expect(rows.map((r) => r.type), contains(AppEventTypes.denied));
    await s.c.read(conversationManagerProvider.notifier).shutdown();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an edit of another file is "fora da spec", with the full path, '
      'and stays out of the counts and the summary (R11)', (tester) async {
    await _pump(
      tester,
      events: _turn(
        extra: [
          _use('x1', 'Edit', {
            'file_path': '$_root/lib/main.dart',
            'old_string': 'a',
            'new_string': 'b\nc',
          }),
          _result('x1'),
        ],
      ),
      file: _apply(_base, [_e1, _e2, _e3]),
    );
    expect(find.byKey(const ValueKey('tool-outside-x1')), findsOneWidget);
    expect(find.text('fora da spec'), findsOneWidget);
    expect(find.text('$_root/lib/main.dart'), findsOneWidget);
    expect(_textOf(tester, 'refine-panel-applied'), '3 edições');
    expect(_textOf(tester, 'refine-panel-lines'), '+9 −2');
    final card = find.byKey(const ValueKey('refine-summary'));
    expect(
      find.descendant(of: card, matching: find.textContaining('main.dart')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.text('3 edições aplicadas')),
      findsOneWidget,
    );
  });

  test('section changes: rewritten and new requirements, criteria by count, '
      'new and removed sections (R6)', () {
    final now = _apply(_base, [
      _e1,
      _e2,
      _e3,
    ]).replaceFirst('## Objetivo\n\nO cabeçalho mistura modos.\n\n', '');
    expect(refineSectionChanges(_base, now), [
      (section: 'Requisitos', change: 'R3 reescrito, R4 novo'),
      (section: 'Critérios de aceite', change: '1 reescrito, 2 novos'),
      (section: 'Fora do escopo', change: 'seção nova'),
      (section: 'Objetivo', change: 'seção removida'),
    ]);
  });
}
