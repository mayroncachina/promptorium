/// Names and labels of a snippet (SPEC-078 R3, R6).
library;

import '../../ui/widgets/code_editor/code_language.dart';

/// Longest suggested name (R3).
const snippetSuggestedMax = 60;

/// Longest name (R2).
const snippetNameMax = 80;

final _commentMarkers = [
  (RegExp(r'^--+\s?'), RegExp(r'$')),
  (RegExp(r'^//+\s?'), RegExp(r'$')),
  (RegExp(r'^/\*+\s?'), RegExp(r'\s*\*+/$')),
  (RegExp(r'^<!--\s?'), RegExp(r'\s*-->$')),
  (RegExp(r'^#+(?![!\[{])\s?'), RegExp(r'$')),
  (RegExp(r'^;+\s?'), RegExp(r'$')),
];

/// Text of the first line comment of [code] without the marker
/// (`-- Pedidos atrasados` → `Pedidos atrasados`); null when there is none.
/// `#` is not a comment in C (`#include`) nor in a shebang (`#!/bin/sh`).
String? firstComment(String code, {String? language}) {
  final cLike = switch (language?.toLowerCase()) {
    'c' || 'h' || 'cpp' || 'c++' || 'cc' || 'cxx' || 'hpp' || 'cs' => true,
    _ => false,
  };
  for (final raw in code.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    for (final (start, end) in _commentMarkers) {
      if (cLike && start.pattern.startsWith('^#')) continue;
      final m = start.firstMatch(line);
      if (m == null) continue;
      final text = line
          .substring(m.end)
          .replaceFirst(end, '')
          .replaceFirst(RegExp(r'^[-=*#/\s]+'), '')
          .trim();
      if (text.isNotEmpty) return text;
      break;
    }
  }
  return null;
}

/// [text] cut at [max] characters on a whole word (R3).
String cutAtWord(String text, [int max = snippetSuggestedMax]) {
  final t = text.trim();
  if (t.length <= max) return t;
  final space = t.lastIndexOf(RegExp(r'\s'), max);
  final cut = space <= 0 ? t.substring(0, max) : t.substring(0, space);
  return cut.replaceFirst(RegExp(r'[\s,;:.\-–—]+$'), '');
}

/// Name suggested for a code block (R3, P7): its first line comment;
/// without one, [title] (of the conversation or of the session's spec) plus
/// the language when the title does not say it: "Pedidos atrasados no
/// DBeaver (sql)". Cut at [snippetSuggestedMax] on a whole word.
String suggestSnippetName(String code, String? language, String? title) {
  final comment = firstComment(code, language: language);
  if (comment != null) return cutAtWord(comment);
  final lang = language?.trim().toLowerCase();
  final t = title?.trim() ?? '';
  final hasLang =
      lang == null ||
      lang.isEmpty ||
      RegExp('(^|[^a-z0-9])${RegExp.escape(lang)}(\$|[^a-z0-9])')
          .hasMatch(t.toLowerCase());
  if (t.isEmpty) return hasLang ? 'Snippet' : 'Snippet ($lang)';
  if (hasLang) return cutAtWord(t);
  final suffix = ' ($lang)';
  return '${cutAtWord(t, snippetSuggestedMax - suffix.length)}$suffix';
}

/// `1 linha`, `17 linhas`.
String snippetLines(String body) {
  final n = '\n'.allMatches(body).length + 1;
  return n == 1 ? '1 linha' : '$n linhas';
}

/// Word shown for the language (`sql`, `texto`).
String snippetLanguageWord(String? language) {
  final l = language?.trim().toLowerCase() ?? '';
  return l.isEmpty ? 'texto' : l;
}

/// `sql · 17 linhas` (R6, R13).
String snippetMeta(String? language, String body) =>
    '${snippetLanguageWord(language)} · ${snippetLines(body)}';

/// [name] cut to [max] characters with "…" (toasts, labels).
String shortName(String name, [int max = 24]) {
  final n = name.trim();
  if (n.length <= max) return n;
  return '${n.substring(0, max).trimRight()}…';
}

const _months = [
  'jan.',
  'fev.',
  'mar.',
  'abr.',
  'mai.',
  'jun.',
  'jul.',
  'ago.',
  'set.',
  'out.',
  'nov.',
  'dez.',
];

/// `12 nov.` (`12 nov. 2025` in another year).
String snippetDate(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final t = at.toLocal();
  final d = '${t.day} ${_months[t.month - 1]}';
  return t.year == n.year ? d : '$d ${t.year}';
}

/// Last use in the list (R9): `hoje`, `ontem`, `3 dias`, `12 nov.`, `nunca`.
String snippetWhen(DateTime? at, {DateTime? now}) {
  if (at == null) return 'nunca';
  final n = now ?? DateTime.now();
  final t = at.toLocal();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return 'hoje';
  if (days == 1) return 'ontem';
  if (days < 7) return '$days dias';
  return snippetDate(t, now: n);
}

/// `usado 4 vezes · último uso ontem` (R7, R9).
String snippetUsage(int uses, DateTime? lastUsedAt, {DateTime? now}) {
  if (uses == 0) return 'nunca usado';
  final times = uses == 1 ? 'usado 1 vez' : 'usado $uses vezes';
  return '$times · último uso ${snippetWhen(lastUsedAt, now: now)}';
}

/// Words of the language picker (R2, R9): the fence words of the
/// highlighted languages, [current] first when it is another one.
List<String> snippetLanguageOptions(String? current) {
  const words = [
    'sql',
    'bash',
    'dart',
    'python',
    'javascript',
    'typescript',
    'json',
    'yaml',
    'xml',
    'css',
    'markdown',
    'go',
    'rust',
    'java',
    'kotlin',
    'swift',
    'cpp',
    'cmake',
    'ini',
    'dockerfile',
    'makefile',
  ];
  final c = current?.trim().toLowerCase();
  return [
    if (c != null && c.isNotEmpty && !words.contains(c)) c,
    ...words,
    'texto',
  ];
}

/// The stored language of a picked word (`texto` = none).
String? snippetLanguageOf(String word) => word == 'texto' ? null : word;

/// What the screen reader says of a snippet (R14): "Snippet Pedidos
/// atrasados, SQL, 17 linhas".
String snippetSpoken(String name, String? language, String body) {
  final lang =
      CodeLanguage.forFence(language)?.label ?? snippetLanguageWord(language);
  return 'Snippet $name, $lang, ${snippetLines(body)}';
}
