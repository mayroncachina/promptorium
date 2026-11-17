import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_draft.dart';
import 'package:promptorium/features/specs/spec_planner.dart';
import 'package:promptorium/features/specs/spec_prints.dart';

import '../../../helpers/test_db.dart';
import '../../sessions/session_test_utils.dart';
import '../spec_planner_test.dart' show plannerOutput, resultLine;

void main() {
  late FakeCli cli;
  late ProviderContainer c;
  late Workspace ws;
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-planner-prints-');
    cli = FakeCli();
    c = ProviderContainer(
      overrides: sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
      ),
    );
    c.listen(specPlannerProvider, (_, _) {});
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: tmp.path, name: 'r');
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  SpecPlanner planner() => c.read(specPlannerProvider.notifier);

  Future<SpecDraftData> load() async => SpecDraftData.decode(
    (await c.read(specDraftsRepoProvider).get(ws.id))!.data,
  );

  Future<void> answer(int n, String line) async {
    for (var i = 0; i < 200 && cli.processes.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    cli.processes[n - 1].emit(line);
  }

  /// The user message the CLI got on its stdin.
  Map<String, dynamic> sent(int n) =>
      cli.processes[n - 1].writtenJson.lastWhere((m) => m['type'] == 'user');

  SpecPrint print(String name, List<int> bytes, PrintKind kind) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return SpecPrint(
      path: f.path,
      name: name,
      width: 1568,
      height: 980,
      kind: kind,
    );
  }

  test('R6: the first turn sends the prints as image blocks before the text, '
      'with the name and kind of each; the next turns do not send them '
      'again', () async {
    final prints = [
      print('print-1.png', [1, 2, 3], PrintKind.bug),
      print('print-2.jpg', [4, 5], PrintKind.reference),
    ];
    final first = planner().begin(ws, 'Botão cortado', prints: prints);
    await answer(
      1,
      resultLine({
        ...plannerOutput(),
        'prints': [
          {
            'nome': 'print-1.png',
            'descricao': 'O card SPEC-073 com o botão Retomar cortado',
            'marcas': <String>[],
          },
          {
            'nome': 'print-2.jpg',
            'descricao': 'Três colunas de planos',
            'marcas': ['Nimbo'],
          },
        ],
      }),
    );
    await first;
    final content = sent(1)['message']['content'] as List;
    expect(content.map((b) => b['type']), ['image', 'image', 'text']);
    expect(content[0]['source'], {
      'type': 'base64',
      'media_type': 'image/png',
      'data': base64Encode([1, 2, 3]),
    });
    expect(content[1]['source']['media_type'], 'image/jpeg');
    final text = content[2]['text'] as String;
    expect(text, startsWith('Botão cortado'));
    expect(text, contains('- print-1.png (1568 × 980): bug neste projeto'));
    expect(text, contains('print-2.jpg (1568 × 980): referência de outro app'));

    var data = await load();
    expect(data.printsSent, isTrue);
    expect(
      data.prints.first.description,
      'O card SPEC-073 com o botão Retomar cortado',
    );
    expect(data.prints.last.brands, ['Nimbo']);
    expect(data.prints.first.brands, isEmpty);

    // The person edits a description: the planner no longer changes it.
    await planner().editPrintDescription(ws, 1, 'Colunas lado a lado');
    final second = planner().send(ws, 'Rolam juntas.');
    await answer(
      2,
      resultLine({
        ...plannerOutput(),
        'prints': [
          {'nome': 'print-1.png', 'descricao': 'Outra', 'marcas': <String>[]},
          {
            'nome': 'print-2.jpg',
            'descricao': 'Mudou',
            'marcas': ['Nimbo', 'Nimbo Pro'],
          },
        ],
      }),
    );
    await second;
    expect(sent(2)['message']['content'], isA<String>(), reason: 'text only');
    expect(sent(2)['message']['content'], isNot(contains('Prints anexados')));
    data = await load();
    expect(data.prints.last.description, 'Colunas lado a lado');
    expect(data.prints.last.brands, ['Nimbo', 'Nimbo Pro']);
    expect(data.prints.first.description, 'Outra');
  });

  test('with prints and no text, the idea is what they show (R5)', () async {
    final first = planner().begin(
      ws,
      '  ',
      prints: [
        print('print-1.png', [1], PrintKind.bug),
      ],
    );
    await answer(1, resultLine({...plannerOutput(), 'prints': <Object>[]}));
    await first;
    final data = await load();
    expect(data.messages.first.text, 'O que o print mostra.');
  });

  test('R7: the schema asks descricao and marcas per print; the prompt has '
      'the rules of bug and reference', () {
    final props = specPlannerSchema['properties'] as Map;
    final item = (props['prints'] as Map)['items'] as Map;
    expect((item['properties'] as Map).keys, ['nome', 'descricao', 'marcas']);
    expect(specPlannerSchema['required'], contains('prints'));
    expect(specPlannerSystemPrompt, contains(specPlannerPrintRules));
    expect(specPlannerPrintRules, contains('PROIBIDO'));
    expect(specPlannerPrintRules, contains('"o app de referência"'));
    expect(specPlannerPrintRules, contains('Print de BUG'));
  });

  test('"Pedir ao planner para reescrever" sends a turn naming the brands '
      '(R9)', () async {
    final first = planner().begin(ws, 'Ideia');
    await answer(1, resultLine({...plannerOutput(), 'prints': <Object>[]}));
    await first;
    final again = planner().rewriteBrands(ws, ['Nimbo']);
    await answer(2, resultLine({...plannerOutput(), 'prints': <Object>[]}));
    await again;
    final msg = sent(2)['message']['content'] as String;
    expect(msg, contains('"Nimbo"'));
    expect(msg, contains('o app de referência'));
  });
}
