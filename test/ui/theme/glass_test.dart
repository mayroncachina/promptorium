import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/glass.dart';
import 'package:promptorium/ui/theme/tokens.dart';
import 'package:promptorium/ui/widgets/app_dialog.dart';

Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

int _dist(Color a, Color b) => [
  ((a.r - b.r) * 255).abs(),
  ((a.g - b.g) * 255).abs(),
  ((a.b - b.b) * 255).abs(),
].map((d) => d.round()).reduce((x, y) => x > y ? x : y);

class _Settings extends AppSettingsController {
  _Settings(this.initial);
  final Map<String, String> initial;
  @override
  Map<String, String> build() => initial;
}

Widget _app(Widget child, {Map<String, String> settings = const {}}) =>
    ProviderScope(
      overrides: [appSettingsProvider.overrideWith(() => _Settings(settings))],
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [const GlassBackdrop(), child]),
        ),
      ),
    );

void main() {
  group('tokens (R3, R6)', () {
    test(
      'glass over the flat background gives the opaque colours of before',
      () {
        expect(
          _dist(
            _over(AppColors.panel, AppColors.backgroundSolid),
            AppColors.panelSolid,
          ),
          lessThanOrEqualTo(1),
        );
        expect(
          _dist(
            _over(AppColors.surfaceRaised, AppColors.backgroundSolid),
            AppColors.surfaceRaisedSolid,
          ),
          lessThanOrEqualTo(1),
        );
        // A well (background) inside a panel keeps the depth of before.
        expect(
          _dist(
            _over(
              AppColors.background,
              _over(AppColors.panel, AppColors.backgroundSolid),
            ),
            AppColors.backgroundSolid,
          ),
          lessThanOrEqualTo(1),
        );
      },
    );

    test('the glass levels and the opaque variant', () {
      expect(AppGlass.fill(GlassLevel.shell), AppColors.panel);
      expect(AppGlass.fill(GlassLevel.card), AppColors.surfaceRaised);
      expect(AppGlass.fill(GlassLevel.shell, opaque: true).a, 1);
      expect(AppGlass.fill(GlassLevel.card, opaque: true).a, 1);
    });
  });

  group('effects switch (R6)', () {
    test('PROMPTORIUM_SEM_VIDRO turns the effects off', () {
      expect(glassDisabledByEnvironment(const {}), isFalse);
      expect(
        glassDisabledByEnvironment(const {'PROMPTORIUM_SEM_VIDRO': '1'}),
        isTrue,
      );
      expect(
        glassDisabledByEnvironment(const {'PROMPTORIUM_SEM_VIDRO': 'true'}),
        isTrue,
      );
      expect(
        glassDisabledByEnvironment(const {'PROMPTORIUM_SEM_VIDRO': '0'}),
        isFalse,
      );
    });

    testWidgets('on: the backdrop paints the lights', (tester) async {
      await tester.pumpWidget(_app(const SizedBox()));
      expect(find.byKey(const ValueKey('glass-backdrop')), findsOneWidget);
      expect(find.byKey(const ValueKey('glass-backdrop-flat')), findsNothing);
    });

    testWidgets('off in Configurações: flat backdrop and no blur', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const GlassBlur(child: SizedBox(width: 10, height: 10)),
          settings: const {'aparencia.vidro': 'false'},
        ),
      );
      expect(find.byKey(const ValueKey('glass-backdrop-flat')), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('GlassBlur blurs with the effects on', (tester) async {
      await tester.pumpWidget(
        _app(const GlassBlur(child: SizedBox(width: 10, height: 10))),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  test('Aparência is found by its words and marks the change (R6)', () {
    expect(filterSections('vidro'), [SettingsSection.appearance]);
    expect(sectionChanged(SettingsSection.appearance, const {}, null), isFalse);
    expect(
      sectionChanged(SettingsSection.appearance, const {
        'aparencia.vidro': 'false',
      }, null),
      isTrue,
    );
  });

  group('dialog (R5)', () {
    testWidgets('a dialog blurs the screen behind it, once', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => const Dialog(child: Text('oi')),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dialog-blur')), findsOneWidget);
    });
  });

  testWidgets('AppGlass lights its border only with a glow (R4)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            AppGlass(
              key: ValueKey('a'),
              child: SizedBox(width: 40, height: 20),
            ),
            AppGlass(
              key: ValueKey('b'),
              glow: AppColors.amber,
              child: SizedBox(width: 40, height: 20),
            ),
          ],
        ),
      ),
    );
    BoxDecoration deco(String k) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byKey(ValueKey(k)),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(deco('a').boxShadow, isEmpty);
    expect(deco('b').boxShadow, isNotEmpty);
  });
}
