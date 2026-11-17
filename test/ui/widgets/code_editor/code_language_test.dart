import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/widgets/code_editor/code_highlight.dart';
import 'package:promptorium/ui/widgets/code_editor/code_language.dart';

void main() {
  group('CodeLanguage.forFence (SPEC-077 R5)', () {
    test('SQL aliases', () {
      for (final w in [
        'sql',
        'postgres',
        'postgresql',
        'psql',
        'mysql',
        'sqlite',
      ]) {
        expect(CodeLanguage.forFence(w), CodeLanguage.sql, reason: w);
      }
    });

    test('shell aliases', () {
      for (final w in ['sh', 'bash', 'zsh', 'shell', 'console']) {
        expect(CodeLanguage.forFence(w), CodeLanguage.shell, reason: w);
      }
    });

    test('short names', () {
      expect(CodeLanguage.forFence('js'), CodeLanguage.javascript);
      expect(CodeLanguage.forFence('jsx'), CodeLanguage.javascript);
      expect(CodeLanguage.forFence('ts'), CodeLanguage.typescript);
      expect(CodeLanguage.forFence('tsx'), CodeLanguage.typescript);
      expect(CodeLanguage.forFence('py'), CodeLanguage.python);
      expect(CodeLanguage.forFence('yml'), CodeLanguage.yaml);
      expect(CodeLanguage.forFence('jsonc'), CodeLanguage.json);
      expect(CodeLanguage.forFence('html'), CodeLanguage.xml);
      expect(CodeLanguage.forFence('toml'), CodeLanguage.ini);
    });

    test('every CodeLanguage id is its own alias', () {
      for (final l in CodeLanguage.values) {
        if (l == CodeLanguage.plaintext) continue;
        expect(CodeLanguage.forFence(l.id), l, reason: l.id);
      }
    });

    test('case, extra words and class prefix are ignored', () {
      expect(CodeLanguage.forFence('SQL'), CodeLanguage.sql);
      expect(CodeLanguage.forFence('PostgreSQL'), CodeLanguage.sql);
      expect(CodeLanguage.forFence('dart title="x"'), CodeLanguage.dart);
      expect(CodeLanguage.forFence('language-py'), CodeLanguage.python);
    });

    test('unknown or none → no highlight', () {
      expect(CodeLanguage.forFence('cobol'), isNull);
      expect(CodeLanguage.forFence(''), isNull);
      expect(CodeLanguage.forFence(null), isNull);
      expect(CodeHighlight.spans('x = 1', null), isNull);
      expect(CodeHighlight.spans('x = 1', CodeLanguage.plaintext), isNull);
    });
  });

  group('CodeHighlight.spans', () {
    test('colors SQL keywords and keeps the text', () {
      const code = 'SELECT id\nFROM pedidos;';
      final span = CodeHighlight.spans(code, CodeLanguage.sql)!;
      expect(span.toPlainText(), code);
      var colored = false;
      span.visitChildren((s) {
        if (s is TextSpan && s.style?.color != null) colored = true;
        return !colored;
      });
      expect(colored, isTrue);
    });

    test('cached: the same span for the same code', () {
      const code = 'SELECT 2;';
      expect(
        identical(
          CodeHighlight.spans(code, CodeLanguage.sql),
          CodeHighlight.spans(code, CodeLanguage.sql),
        ),
        isTrue,
      );
    });

    test('more than 2000 lines stay plain', () {
      final code = List.filled(2001, 'SELECT 1;').join('\n');
      expect(CodeHighlight.spans(code, CodeLanguage.sql), isNull);
    });
  });
}
