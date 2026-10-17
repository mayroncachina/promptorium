import 'package:flutter/painting.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../../ui/widgets/code_editor/code_editor_theme.dart';
import '../../../ui/widgets/code_editor/code_language.dart';

/// Syntax colors of a diff line (re_highlight, the language of the file's
/// extension). Each line is highlighted alone: a construct that spans lines
/// (block comment, multi-line string) may lose its color in the middle.
abstract final class DiffHighlight {
  static final _hl = Highlight()
    ..registerLanguages({for (final l in CodeLanguage.values) l.id: l.mode});

  static final Map<(String, String), TextSpan> _cache = {};
  static const _max = 6000;

  static TextSpan line(String path, String text, TextStyle base) {
    final lang = CodeLanguage.forPath(path);
    if (lang == CodeLanguage.plaintext || text.trim().isEmpty) {
      return TextSpan(text: text.isEmpty ? ' ' : text, style: base);
    }
    final key = (lang.id, text);
    final hit = _cache[key];
    if (hit != null) return TextSpan(style: base, children: [hit]);
    TextSpan span;
    try {
      final r = _hl.highlight(code: text, language: lang.id);
      final renderer = TextSpanRenderer(null, promptoriumCodeTheme);
      r.render(renderer);
      span = renderer.span ?? TextSpan(text: text);
    } catch (_) {
      span = TextSpan(text: text);
    }
    if (_cache.length >= _max) _cache.clear();
    _cache[key] = span;
    return TextSpan(style: base, children: [span]);
  }
}
