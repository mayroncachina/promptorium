import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart'
    show workspaceFilesProvider;
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prompt_test_utils.dart';

const spec = '''---
id: SPEC-001
status: rascunho
---

# Salvar a spec da resposta

## Objetivo

Salvar com um clique.

## Requisitos

- R1 · Mostrar a barra.
- R2 · Gravar só a spec.

## Critérios de aceite

- [ ] [R1] A barra aparece.
''';

String fenced(String body) =>
    'Neste modo não tenho ferramenta de escrita. Salve em docs/specs:\n\n'
    '```markdown\n$body```';

class Harness {
  Harness(this.tmp, this.db, this.ws, this.container);

  final Directory tmp;
  final AppDatabase db;
  final Workspace ws;
  final ProviderContainer container;

  File file(String rel) => File('${tmp.path}/$rel');
}

/// Real file I/O runs outside the fake clock; waits until [cond] holds.
Future<void> until(WidgetTester tester, bool Function() cond) async {
  for (var i = 0; i < 100 && !cond(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(cond(), isTrue, reason: 'condition not reached');
}

Future<Harness> pumpPrompt(
  WidgetTester tester, {
  required String answer,
  Future<void> Function(Harness h)? before,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tmp = Directory.systemTemp.createTempSync('promptorium-answer-bar-');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final db = memoryDatabase();
  final ws = await addWorkspace(db, tmp.path);
  final conv = await db
      .into(db.conversations)
      .insertReturning(
        ConversationsCompanion.insert(
          workspaceId: ws.id,
          title: 'Spec do botão',
          model: 'sonnet',
          claudeSessionId: const Value('conv-sid'),
          messageCount: const Value(2),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
  final events = [
    AppEventTypes.userMessage('Escreva a spec final.', DateTime.now()),
    textLine(answer),
    resultLine(),
  ];
  var seq = 0;
  for (final e in events) {
    await db
        .into(db.conversationEvents)
        .insert(
          ConversationEventsCompanion.insert(
            conversationId: conv.id,
            seq: ++seq,
            type: '${e['type']}',
            json: jsonEncode(e),
          ),
        );
  }
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
      workspaceFilesProvider.overrideWith((ref, root) async => const []),
    ],
  );
  final h = Harness(tmp, db, ws, container);
  await container.read(appSettingsProvider.notifier).load();
  if (before != null) await tester.runAsync(() => before(h));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: PromptScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await until(
    tester,
    () => find.byKey(const ValueKey('conversation-1')).evaluate().isNotEmpty,
  );
  await tester.tap(find.byKey(const ValueKey('conversation-1')));
  await tester.pump();
  return h;
}

String? textOf(WidgetTester tester, String key) {
  final f = find.byKey(ValueKey(key));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

Finder button(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('the bar shows the spec; the preview saves it with the edited '
      'title and the bar then shows the saved spec', (tester) async {
    final h = await pumpPrompt(tester, answer: fenced(spec));
    await until(
      tester,
      () => find.text('Salvar como SPEC-001').evaluate().isNotEmpty,
    );
    expect(
      textOf(tester, 'answer-spec-title'),
      'Spec detectada nesta resposta',
    );
    expect(
      textOf(tester, 'answer-spec-subtitle'),
      'nova · SPEC-001 · 2 requisitos · 1 critério de aceite',
    );

    await tester.tap(button('answer-spec-preview'));
    await until(
      tester,
      () => button('answer-spec-title-field').evaluate().isNotEmpty,
    );
    await tester.enterText(button('answer-spec-title-field'), 'Botão da spec');
    await tester.pump();
    expect(
      textOf(tester, 'answer-spec-path'),
      'specs/SPEC-001-botao-da-spec.md',
    );
    await tester.tap(button('answer-spec-preview-save'));
    await until(
      tester,
      () => textOf(tester, 'answer-spec-title') == 'SPEC-001 salva',
    );

    final text = h.file('specs/SPEC-001-botao-da-spec.md').readAsStringSync();
    expect(text, startsWith('---\nid: SPEC-001\nstatus: rascunho\n---'));
    expect(text, contains('# Botão da spec'));
    expect(text, isNot(contains('ferramenta de escrita')));
    expect(h.container.read(navigationProvider), AppSection.specs);
    expect(button('answer-spec-open'), findsOneWidget);
  });

  testWidgets('"Transformar em spec" uses the detected spec; without one it '
      'still compiles the conversation', (tester) async {
    final h = await pumpPrompt(tester, answer: fenced(spec));
    await until(
      tester,
      () => find.text('Salvar como SPEC-001').evaluate().isNotEmpty,
    );
    await tester.tap(button('prompt-to-spec'));
    await until(
      tester,
      () => textOf(tester, 'answer-spec-title') == 'SPEC-001 salva',
    );
    final saved = h.file('specs/SPEC-001-salvar-a-spec-da-resposta.md');
    expect(saved.readAsStringSync(), isNot(contains('Conversa (resumo)')));
  });

  testWidgets('without a spec in the answers "Transformar em spec" compiles '
      'the conversation', (tester) async {
    final h = await pumpPrompt(tester, answer: 'Use um LineSplitter.');
    await until(
      tester,
      () => find.textContaining('LineSplitter').evaluate().isNotEmpty,
    );
    expect(button('answer-spec-bar'), findsNothing);
    await tester.tap(button('prompt-to-spec'));
    // Created empty first (exclusive), then written: wait for the text.
    var text = '';
    await until(tester, () {
      final dir = Directory('${h.tmp.path}/specs');
      final files = dir.existsSync() ? dir.listSync() : const [];
      text = files.isEmpty ? '' : File(files.single.path).readAsStringSync();
      return text.isNotEmpty;
    });
    expect(text, contains('## Conversa (resumo)'));
  });

  testWidgets('an answer with the id of an existing spec applies to it', (
    tester,
  ) async {
    late Spec target;
    final h = await pumpPrompt(
      tester,
      answer: fenced(spec),
      before: (h) async {
        target = await SpecService(SpecsRepo(h.db)).create(
          h.ws,
          title: 'Antiga',
          render: (code) =>
              '---\nid: $code\nstatus: em-revisao\n---\n\n# Antiga\n',
        );
        // Written before the conversation started: not stale.
        h
            .file(target.path)
            .setLastModifiedSync(
              DateTime.now().subtract(const Duration(days: 1)),
            );
      },
    );
    await until(
      tester,
      () => find.text('Aplicar na SPEC-001').evaluate().isNotEmpty,
    );
    expect(textOf(tester, 'answer-spec-title'), 'Nova versão da SPEC-001');
    expect(button('answer-spec-stale'), findsNothing);
    await tester.tap(find.text('Aplicar na SPEC-001'));
    await until(
      tester,
      () => textOf(tester, 'answer-spec-title') == 'SPEC-001 salva',
    );
    final text = h.file(target.path).readAsStringSync();
    expect(text, contains('status: em-revisao'));
    expect(text, contains('# Salvar a spec da resposta'));
  });
}
