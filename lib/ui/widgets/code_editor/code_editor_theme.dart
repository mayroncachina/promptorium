import 'package:flutter/painting.dart';

import '../../theme/tokens.dart';

/// Dark highlight theme of the editor built from the app tokens (mockup
/// Specs: headings amber, frontmatter / keys lilac, text primary).
/// Keys are highlight.js scopes produced by re_highlight.
abstract final class CodeEditorColors {
  static const lineNumber = Color(0xFF4A5260);
  static const lineNumberFocused = AppColors.textSecondary;
  static const cursorLine = Color(0xFF161A21);
  static const selection = Color(0x553A4458);
  static const findMatch = Color(0x55F2A541);
  static const string = Color(0xFF9FD89A);
  static const number = Color(0xFFE8B47A);
  static const comment = AppColors.textMuted;
}

const Map<String, TextStyle> promptoriumCodeTheme = {
  'root': TextStyle(color: AppColors.text),
  'comment': TextStyle(
    color: CodeEditorColors.comment,
    fontStyle: FontStyle.italic,
  ),
  'quote': TextStyle(
    color: AppColors.textSecondary,
    fontStyle: FontStyle.italic,
  ),
  'doctag': TextStyle(color: AppColors.lilac),
  'keyword': TextStyle(color: AppColors.lilac),
  'built_in': TextStyle(color: AppColors.blue),
  'type': TextStyle(color: AppColors.blue),
  'class': TextStyle(color: AppColors.blue),
  'title': TextStyle(color: AppColors.amber),
  'title.class_': TextStyle(color: AppColors.blue),
  'title.function_': TextStyle(color: AppColors.amber),
  'function': TextStyle(color: AppColors.amber),
  'params': TextStyle(color: AppColors.text),
  'literal': TextStyle(color: AppColors.teal),
  'number': TextStyle(color: CodeEditorColors.number),
  'string': TextStyle(color: CodeEditorColors.string),
  'subst': TextStyle(color: AppColors.text),
  'template-variable': TextStyle(color: AppColors.amber),
  'regexp': TextStyle(color: CodeEditorColors.string),
  'symbol': TextStyle(color: AppColors.teal),
  'variable': TextStyle(color: AppColors.text),
  'attr': TextStyle(color: AppColors.lilac),
  'attribute': TextStyle(color: AppColors.lilac),
  'meta': TextStyle(color: AppColors.textSecondary),
  'punctuation': TextStyle(color: AppColors.textSecondary),
  // Markdown.
  'section': TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600),
  'bullet': TextStyle(color: AppColors.teal),
  'code': TextStyle(color: AppColors.teal),
  'link': TextStyle(
    color: AppColors.blue,
    decoration: TextDecoration.underline,
  ),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.w700),
  'addition': TextStyle(color: AppColors.teal),
  'deletion': TextStyle(color: AppColors.red),
};
