import 'package:flutter/painting.dart';
import 'package:re_highlight/re_highlight.dart';

import 'code_editor_theme.dart';
import 'code_language.dart';

/// Syntax colors of a piece of code (re_highlight with the editor theme),
/// shared by the diff and the code blocks of the markdown (SPEC-077 R5).
abstract final class CodeHighlight {
  static final _hl = Highlight()
    ..registerLanguages({for (final l in CodeLanguage.values) l.id: l.mode});

  /// Above this many lines a code block stays plain (R5).
  static const maxLines = 2000;

  static final Map<(String, String), TextSpan> _cache = {};
  static const _maxCached = 200;

  /// [code] highlighted as [language], uncached; plain on error.
  static TextSpan render(String code, CodeLanguage language) {
    try {
      final r = _hl.highlight(code: code, language: language.id);
      final renderer = TextSpanRenderer(null, promptoriumCodeTheme);
      r.render(renderer);
      return renderer.span ?? TextSpan(text: code);
    } catch (_) {
      return TextSpan(text: code);
    }
  }

  /// [code] highlighted as [language], computed once per (language, code).
  /// Null when it stays plain: no language, plain text, or more than
  /// [maxLines] lines.
  static TextSpan? spans(String code, CodeLanguage? language) {
    if (language == null || language == CodeLanguage.plaintext) return null;
    if ('\n'.allMatches(code).length >= maxLines) return null;
    final key = (language.id, code);
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    final span = render(code, language);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    return _cache[key] = span;
  }
}
