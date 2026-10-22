import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/review/merge_options.dart';
import 'package:promptorium/features/review/widgets/review_dialogs.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

/// SPEC-012: what the merge dialog offers and says (the service side is in
/// review_service_test.dart, on real temporary repositories).
void main() {
  Future<({MergeOptions? options, bool? delete})> open(
    WidgetTester tester, {
    MergeFacts facts = const MergeFacts(rootBranch: 'main'),
    MergeMethod initial = MergeMethod.merge,
    bool published = false,
    Future<void> Function()? act,
  }) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MergeOptions? options;
    bool? delete;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                delete = await showMergeDialog(
                  context,
                  branch: 'pr/barra',
                  base: 'main',
                  uncommitted: 1,
                  facts: facts,
                  initialMethod: initial,
                  published: published,
                  onOptions: (o) => options = o,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    if (act != null) await act();
    return (options: options, delete: delete);
  }

  Future<void> chooseMethod(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButton<MergeMethod>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('each method says its effect on the history, its command and '
      'how a conflict is undone', (tester) async {
    await open(tester);
    expect(find.textContaining('cria um commit de merge'), findsOneWidget);
    expect(find.textContaining('(merge --no-ff)'), findsOneWidget);
    expect(find.textContaining('(merge --abort)'), findsOneWidget);

    await chooseMethod(tester, 'Squash — junta os commits de etapa');
    expect(
      find.textContaining('Junta todos os commits de etapa num único commit'),
      findsOneWidget,
    );
    expect(find.textContaining('merge --squash + commit'), findsOneWidget);
    expect(find.textContaining('(reset --merge)'), findsOneWidget);

    await chooseMethod(tester, 'Rebase — histórico linear');
    expect(find.textContaining('histórico linear).'), findsOneWidget);
    expect(find.textContaining('rebase + merge --ff-only'), findsOneWidget);
    expect(find.textContaining('(rebase --abort)'), findsOneWidget);
  });

  testWidgets('the config default preselects the method', (tester) async {
    await open(tester, initial: MergeMethod.squash);
    expect(find.text('Squash — junta os commits de etapa'), findsOneWidget);
  });

  testWidgets('rebase is unavailable, with the reason, when the branch has '
      'a PR or an upstream', (tester) async {
    await open(
      tester,
      facts: const MergeFacts(rootBranch: 'main', published: true),
      initial: MergeMethod.rebase,
    );
    // A published branch never starts on rebase.
    expect(find.textContaining('cria um commit de merge'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<MergeMethod>));
    await tester.pumpAndSettle();
    final rebase = tester
        .widgetList<DropdownMenuItem<MergeMethod>>(
          find.byType(DropdownMenuItem<MergeMethod>),
        )
        .firstWhere((i) => i.value == MergeMethod.rebase);
    expect(rebase.enabled, isFalse);
    expect(
      find.textContaining('Rebase indisponível: branch publicada'),
      findsWidgets,
    );
  });

  testWidgets('switching branch is offered only with the root on another '
      'branch, returning by default; stash only with tracked changes, which '
      'are listed, off by default', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('review-merge-switch')), findsNothing);
    expect(find.byKey(const ValueKey('review-merge-stash')), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    final r = await open(
      tester,
      facts: const MergeFacts(
        rootBranch: 'outra',
        rootChanges: ['lib/a.dart', 'README.md'],
      ),
      act: () async {
        expect(find.textContaining('lib/a.dart, README.md'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('review-merge-stash')),
              )
              .value,
          isFalse,
        );
        await tester.tap(find.byKey(const ValueKey('review-merge-switch')));
        await tester.pumpAndSettle();
        expect(find.text('Voltar à branch anterior'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('review-merge-confirm')));
        await tester.pumpAndSettle();
      },
    );
    expect(r.options!.switchBase, isTrue);
    expect(r.options!.restoreBranch, isTrue);
    expect(r.options!.stash, isFalse);
  });

  testWidgets('the dialog warns that the pending commit runs the hooks and '
      'skipping them is off by default', (tester) async {
    final r = await open(
      tester,
      act: () async {
        expect(
          find.text('O commit de pendências executa os hooks do projeto.'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('review-merge-confirm')));
        await tester.pumpAndSettle();
      },
    );
    expect(r.options!.skipHooks, isFalse);
    expect(r.options!.method, MergeMethod.merge);
  });
}
