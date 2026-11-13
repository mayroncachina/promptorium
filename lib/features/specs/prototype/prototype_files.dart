import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

/// Screens of a spec's prototype (SPEC-022): self-contained HTML files in
/// `docs/mockups/<code>/`, named `R<n>-<slug>.html` (variation A) and
/// `R<n>-<slug>.<letter>.html` (B, C…), plus the app's `index.json`
/// (description and time of each screen, history of the requests).

/// `docs/mockups/spec-022` (relative to the workspace root).
String mockupDir(String specCode) => 'docs/mockups/${specCode.toLowerCase()}';

final _name = RegExp(r'^(R\d+)-([a-z0-9][a-z0-9-]*?)(?:\.([a-z]))?\.html$');

/// One HTML screen of the folder.
@immutable
class MockupScreen {
  const MockupScreen({
    required this.file,
    required this.requirement,
    required this.slug,
    required this.letter,
  });

  /// File name (`R1-lista.b.html`).
  final String file;

  /// `R1`.
  final String requirement;

  /// `lista`.
  final String slug;

  /// `a`, `b`… (no letter in the name = `a`).
  final String letter;

  /// `Lista de prompts` from `lista-de-prompts`.
  String get title {
    final words = slug.split('-').where((w) => w.isNotEmpty).join(' ');
    return words.isEmpty
        ? requirement
        : words[0].toUpperCase() + words.substring(1);
  }

  /// `R1 · Lista de prompts` (variation ≠ A: `… · B`).
  String get label =>
      '$requirement · $title${letter == 'a' ? '' : ' · ${letter.toUpperCase()}'}';

  int get number => int.tryParse(requirement.substring(1)) ?? 0;

  /// `A`, `B`… (SPEC-027 R1: the badge of every card, A included).
  String get letterLabel => letter.toUpperCase();

  /// `R1, Lista de prompts, variação A` (SPEC-027 R1a, R4).
  String get spokenName => '$requirement, $title, variação $letterLabel';

  @override
  bool operator ==(Object other) => other is MockupScreen && other.file == file;

  @override
  int get hashCode => file.hashCode;
}

/// [MockupScreen] of [file]; null when the name does not follow the pattern.
MockupScreen? parseMockupName(String file) {
  final m = _name.firstMatch(file);
  if (m == null) return null;
  return MockupScreen(
    file: file,
    requirement: m.group(1)!,
    slug: m.group(2)!,
    letter: m.group(3) ?? 'a',
  );
}

/// Sorted by requirement number, then letter.
List<MockupScreen> sortScreens(Iterable<MockupScreen> screens) =>
    screens.toList()..sort((a, b) {
      final n = a.number.compareTo(b.number);
      return n != 0 ? n : a.letter.compareTo(b.letter);
    });

/// Next free variation of [requirement] (R7): `R1-lista.html` →
/// `R1-lista.b.html` → `R1-lista.c.html`. [slug] is used when the
/// requirement has no screen yet.
String nextVariationName(
  List<MockupScreen> screens,
  String requirement, {
  String slug = 'tela',
}) {
  final mine = [
    for (final s in screens)
      if (s.requirement == requirement) s,
  ];
  if (mine.isEmpty) return '$requirement-$slug.html';
  final base = sortScreens(mine).first.slug;
  final used = {for (final s in mine) s.letter};
  for (var c = 'b'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++) {
    final l = String.fromCharCode(c);
    if (!used.contains(l)) return '$requirement-$base.$l.html';
  }
  throw StateError('$requirement já tem 26 variações.');
}

/// Description and time of one screen (`index.json` › `telas`).
@immutable
class ScreenMeta {
  const ScreenMeta({this.description, this.createdAt});

  final String? description;
  final DateTime? createdAt;

  Map<String, Object?> toJson() => {
    'descricao': ?description,
    if (createdAt != null) 'criada': createdAt!.toIso8601String(),
  };

  static ScreenMeta fromJson(Object? j) {
    if (j is! Map) return const ScreenMeta();
    final d = '${j['descricao'] ?? ''}'.trim();
    return ScreenMeta(
      description: d.isEmpty ? null : d,
      createdAt: DateTime.tryParse('${j['criada'] ?? ''}'),
    );
  }
}

/// One request of the "Pedir ao Claude" panel (`index.json` › `historico`).
@immutable
class PrototypeRequest {
  const PrototypeRequest({
    required this.request,
    required this.at,
    this.requirements = const [],
    this.answer,
    this.files = const [],
    this.failed = false,
  });

  final String request;
  final DateTime at;
  final List<String> requirements;
  final String? answer;
  final List<String> files;
  final bool failed;

  Map<String, Object?> toJson() => {
    'pedido': request,
    'em': at.toIso8601String(),
    'telas': requirements,
    'resposta': ?answer,
    'arquivos': files,
    if (failed) 'falhou': true,
  };

  static PrototypeRequest? fromJson(Object? j) {
    if (j is! Map || j['pedido'] == null) return null;
    return PrototypeRequest(
      request: '${j['pedido']}',
      at: DateTime.tryParse('${j['em'] ?? ''}') ?? DateTime(2000),
      requirements: [for (final r in j['telas'] as List? ?? const []) '$r'],
      answer: j['resposta'] == null ? null : '${j['resposta']}',
      files: [for (final f in j['arquivos'] as List? ?? const []) '$f'],
      failed: j['falhou'] == true,
    );
  }
}

/// A requirement whose last screen was deleted (SPEC-027 R7): its title
/// and whether its approval left the spec with it.
@immutable
class EmptiedRequirement {
  const EmptiedRequirement({required this.title, this.hadApproval = false});

  final String title;
  final bool hadApproval;

  Map<String, Object?> toJson() => {
    'titulo': title,
    if (hadApproval) 'aprovada': true,
  };

  static EmptiedRequirement fromJson(Object? j) => j is Map
      ? EmptiedRequirement(
          title: '${j['titulo'] ?? ''}',
          hadApproval: j['aprovada'] == true,
        )
      : const EmptiedRequirement(title: '');
}

/// `docs/mockups/<code>/index.json`, written by the app (never the agent).
@immutable
class PrototypeIndex {
  const PrototypeIndex({
    this.screens = const {},
    this.history = const [],
    this.emptied = const {},
    this.shown = const {},
    this.unseen = const {},
  });

  static const fileName = 'index.json';

  final Map<String, ScreenMeta> screens;
  final List<PrototypeRequest> history;

  /// Requirements left without a screen by a deletion (`semTela`, R7).
  final Map<String, EmptiedRequirement> emptied;

  /// Requirement → file shown on its card (`mostrada`, SPEC-067 R6).
  final Map<String, String> shown;

  /// Variations not seen yet (`novas`, SPEC-067 R5): "nova" on the card and
  /// in "Versões".
  final Set<String> unseen;

  PrototypeIndex copyWith({
    Map<String, ScreenMeta>? screens,
    List<PrototypeRequest>? history,
    Map<String, EmptiedRequirement>? emptied,
    Map<String, String>? shown,
    Set<String>? unseen,
  }) => PrototypeIndex(
    screens: screens ?? this.screens,
    history: history ?? this.history,
    emptied: emptied ?? this.emptied,
    shown: shown ?? this.shown,
    unseen: unseen ?? this.unseen,
  );

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'telas': {
      for (final k in screens.keys.toList()..sort()) k: screens[k]!.toJson(),
    },
    'historico': [for (final h in history) h.toJson()],
    if (emptied.isNotEmpty)
      'semTela': {
        for (final k in emptied.keys.toList()..sort()) k: emptied[k]!.toJson(),
      },
    if (shown.isNotEmpty)
      'mostrada': {for (final k in shown.keys.toList()..sort()) k: shown[k]},
    if (unseen.isNotEmpty) 'novas': unseen.toList()..sort(),
  });

  static PrototypeIndex decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const PrototypeIndex();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const PrototypeIndex();
      final t = j['telas'];
      final e = j['semTela'];
      final m = j['mostrada'];
      return PrototypeIndex(
        unseen: {for (final f in j['novas'] as List? ?? const []) '$f'},
        shown: {
          if (m is Map)
            for (final x in m.entries)
              if (x.value is String) '${x.key}': x.value as String,
        },
        emptied: {
          if (e is Map)
            for (final x in e.entries)
              '${x.key}': EmptiedRequirement.fromJson(x.value),
        },
        screens: {
          if (t is Map)
            for (final e in t.entries) '${e.key}': ScreenMeta.fromJson(e.value),
        },
        history: [
          for (final h in j['historico'] as List? ?? const [])
            ?PrototypeRequest.fromJson(h),
        ],
      );
    } catch (_) {
      return const PrototypeIndex();
    }
  }

  static Future<PrototypeIndex> read(String dir) async {
    final f = File('$dir/$fileName');
    try {
      return decode(await f.exists() ? await f.readAsString() : null);
    } on FileSystemException {
      return const PrototypeIndex();
    }
  }

  Future<void> write(String dir) async {
    await Directory(dir).create(recursive: true);
    final f = File('$dir/$fileName');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString('${encode()}\n', flush: true);
    await tmp.rename(f.path);
  }
}

/// Screens of [dir] (absolute), sorted; empty when the folder is missing.
Future<List<MockupScreen>> listScreens(String dir) async {
  final d = Directory(dir);
  if (!await d.exists()) return const [];
  final out = <MockupScreen>[];
  await for (final e in d.list()) {
    if (e is! File) continue;
    final s = parseMockupName(e.uri.pathSegments.last);
    if (s != null) out.add(s);
  }
  return sortScreens(out);
}
