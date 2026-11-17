import 'package:flutter/painting.dart';

import '../../../ui/widgets/code_editor/code_highlight.dart';
import '../../../ui/widgets/code_editor/code_language.dart';

/// Syntax colors of a diff line (re_highlight, the language of the file's
/// extension). Each line is highlighted alone: a construct that spans lines
/// (block comment, multi-line string) may lose its color in the middle.
abstract final class DiffHighlight {
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
    final span = CodeHighlight.render(text, lang);
    if (_cache.length >= _max) _cache.clear();
    _cache[key] = span;
    return TextSpan(style: base, children: [span]);
  }
}
