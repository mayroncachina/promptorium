import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/providers/provider_logo_paths.dart';
import 'package:promptorium/ui/providers/provider_logos.dart';
import 'package:promptorium/ui/theme/tokens.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  home: Scaffold(
    backgroundColor: const Color(0xFF222732),
    body: Center(child: RepaintBoundary(child: child)),
  ),
);

/// Colors of the opaque pixels of the first [RepaintBoundary].
Future<Set<int>> _inkColors(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).last,
  );
  late Set<int> colors;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    colors = {
      for (var i = 0; i < bytes.length; i += 4)
        if (bytes[i + 3] == 255)
          (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2],
    };
  });
  return colors;
}

void main() {
  group('ProviderLogo (SPEC-094 R14a)', () {
    for (final size in [14.0, 16.0]) {
      for (final p in ['claude', 'codex']) {
        testWidgets('golden $p ${size.toInt()} px', (tester) async {
          await tester.pumpWidget(_host(ProviderLogo(p, size: size)));
          await expectLater(
            find.byType(ProviderLogo),
            matchesGoldenFile('goldens/logo_${p}_${size.toInt()}.png'),
          );
        });
      }
    }

    testWidgets('a cor do logo não muda com o tema', (tester) async {
      for (final p in ['claude', 'codex']) {
        final seen = <Set<int>>[];
        for (final theme in [ThemeData.light(), ThemeData.dark()]) {
          await tester.pumpWidget(
            _host(ProviderLogo(p, size: 16), theme: theme),
          );
          seen.add(await _inkColors(tester));
        }
        expect(seen.first, seen.last, reason: p);
        final brand = p == 'claude' ? 0xD97757 : 0xFFFFFF;
        expect(seen.first, contains(brand), reason: p);
      }
    });

    test('mínimo de 14 px', () {
      expect(() => ProviderLogo('claude', size: 12), throwsAssertionError);
    });

    testWidgets('provedor sem identidade não desenha logo', (tester) async {
      await tester.pumpWidget(_host(const ProviderLogo('acp-gemini')));
      expect(find.byType(CustomPaint), findsNothing);
    });
  });

  group('ProviderChip', () {
    testWidgets('logo sempre ao lado do nome', (tester) async {
      await tester.pumpWidget(_host(ProviderChip('codex')));
      expect(find.text('Codex'), findsOneWidget);
      expect(find.byType(ProviderLogo), findsOneWidget);
      await tester.pumpWidget(_host(ProviderChip('claude', dense: true)));
      expect(find.text('Claude'), findsOneWidget);
      expect(
        tester.widget<ProviderLogo>(find.byType(ProviderLogo)).size,
        ProviderLogo.minSize,
      );
    });

    test('chip sem nome falha', () {
      expect(() => ProviderChip('claude', name: ''), throwsArgumentError);
      expect(() => ProviderChip('codex', name: '  '), throwsArgumentError);
    });

    testWidgets('sem token: só o nome, sem cor nem logo', (tester) async {
      await tester.pumpWidget(_host(ProviderChip('acp', name: 'Gemini CLI')));
      expect(find.text('Gemini CLI'), findsOneWidget);
      expect(find.byType(ProviderLogo), findsNothing);
      expect(find.byType(Container), findsNothing);
    });
  });

  group('ProviderGlyph (R14b)', () {
    for (final p in ['claude', 'codex']) {
      testWidgets('golden $p 14 px', (tester) async {
        await tester.pumpWidget(_host(ProviderGlyph(p)));
        await expectLater(
          find.byType(ProviderGlyph),
          matchesGoldenFile('goldens/glyph_$p.png'),
        );
      });
    }

    testWidgets('marca na cor do provedor, com nome acessível', (tester) async {
      await tester.pumpWidget(_host(const ProviderGlyph('claude')));
      expect(
        await _inkColors(tester),
        contains(AppColors.providerClaude.toARGB32() & 0xFFFFFF),
      );
      expect(find.bySemanticsLabel('Claude'), findsOneWidget);
    });
  });

  test('os paths vêm dos SVGs originais, sem alteração', () {
    String d(String f) =>
        RegExp(r' d="([^"]+)"')
            .firstMatch(File('assets/providers/$f').readAsStringSync())!
            .group(1)!;
    expect(claudeLogoPath, d('claude.svg'));
    expect(openAiBlossomPath, d('openai-blossom.svg'));
    expect(
      File('assets/providers/claude.svg').readAsStringSync(),
      contains('<title>Claude</title>'),
    );
    expect(File('assets/providers/LICENSES.md').existsSync(), isTrue);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('flutter_svg')),
    );
  });
}
