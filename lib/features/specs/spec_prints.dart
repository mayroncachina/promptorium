import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../prompt/attachments.dart' show attachmentBatchDir;
import 'prototype/prototype_files.dart';
import 'spec_draft.dart';

/// The prints (screenshots) of a spec draft (SPEC-083): pasted with Ctrl V,
/// dropped or picked in "Nova spec", seen by the planner and copied to
/// `docs/mockups/spec-0NN/` when the spec is created.

/// R3: at most this many prints per spec (P2).
const maxPrints = 4;

/// R3: larger files are refused.
const maxPrintBytes = 20 * 1024 * 1024;

/// R3, P3: the longest side is reduced to this.
const maxPrintSide = 1568;

/// Extensions of an image file that can become a print (R1).
const printExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

/// Bug of this project or reference of another app (R5, P4).
enum PrintKind {
  bug('bug', 'Bug neste projeto', 'Bug'),
  reference('referencia', 'Referência de outro app', 'Referência');

  const PrintKind(this.json, this.label, this.short);

  /// Value in the JSON of the draft and in `index.json`.
  final String json;

  /// The radio button.
  final String label;

  /// The tag of the draft ("Bug", "Referência").
  final String short;

  static PrintKind? parse(Object? v) =>
      values.where((k) => k.json == '$v').firstOrNull;
}

class PrintException implements Exception {
  const PrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One print of the draft.
@immutable
class SpecPrint {
  const SpecPrint({
    required this.path,
    required this.name,
    required this.width,
    required this.height,
    this.kind,
    this.originalWidth,
    this.originalHeight,
    this.description = '',
    this.descriptionEdited = false,
    this.brands = const [],
  });

  /// Absolute path of the temporary file (`.promptorium/attachments/…`).
  final String path;

  /// `print-1.png`, by the order it came in (P7).
  final String name;
  final int width;
  final int height;

  /// Null until the person chooses (R5).
  final PrintKind? kind;

  /// Size before the reduction (R3); null when it was not reduced.
  final int? originalWidth;
  final int? originalHeight;

  /// What the print shows, from the planner (R7), editable (R8).
  final String description;

  /// Typed by the person: the planner no longer changes it.
  final bool descriptionEdited;

  /// Product, company and brand names the planner read in it (R7).
  final List<String> brands;

  bool get reduced => originalWidth != null && originalHeight != null;

  /// `png`, `jpg`…
  String get extension => p.extension(path).replaceFirst('.', '').toLowerCase();

  /// `image/png`…
  String get mediaType => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/png',
  };

  /// `1568 × 980`.
  String get sizeLabel => '$width × $height';

  /// `1568 × 980 · reduzido de 2880 × 1800` (R3).
  String get fullSizeLabel => reduced
      ? '$sizeLabel · reduzido de $originalWidth × $originalHeight'
      : sizeLabel;

  factory SpecPrint.fromJson(Map<Object?, Object?> j) {
    int? n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final brands = j['marcas'];
    return SpecPrint(
      path: '${j['caminho'] ?? ''}',
      name: '${j['nome'] ?? ''}',
      width: n(j['largura']) ?? 0,
      height: n(j['altura']) ?? 0,
      kind: PrintKind.parse(j['tipo']),
      originalWidth: n(j['larguraOriginal']),
      originalHeight: n(j['alturaOriginal']),
      description: '${j['descricao'] ?? ''}'.trim(),
      descriptionEdited: j['descricaoEditada'] == true,
      brands: [
        if (brands is List)
          for (final b in brands)
            if ('$b'.trim().isNotEmpty) '$b'.trim(),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'caminho': path,
    'nome': name,
    'largura': width,
    'altura': height,
    'tipo': ?kind?.json,
    'larguraOriginal': ?originalWidth,
    'alturaOriginal': ?originalHeight,
    if (description.isNotEmpty) 'descricao': description,
    if (descriptionEdited) 'descricaoEditada': true,
    if (brands.isNotEmpty) 'marcas': brands,
  };

  SpecPrint copyWith({
    String? name,
    PrintKind? kind,
    String? description,
    bool? descriptionEdited,
    List<String>? brands,
  }) => SpecPrint(
    path: path,
    name: name ?? this.name,
    width: width,
    height: height,
    kind: kind ?? this.kind,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    description: description ?? this.description,
    descriptionEdited: descriptionEdited ?? this.descriptionEdited,
    brands: brands ?? this.brands,
  );

  @override
  bool operator ==(Object other) =>
      other is SpecPrint &&
      other.path == path &&
      other.name == name &&
      other.kind == kind &&
      other.description == description &&
      other.descriptionEdited == descriptionEdited &&
      listEquals(other.brands, brands);

  @override
  int get hashCode =>
      Object.hash(path, name, kind, description, Object.hashAll(brands));
}

/// `print-1.png`, `print-2.jpg`… by position (P7).
List<SpecPrint> renumberPrints(List<SpecPrint> prints) => [
  for (final (i, s) in prints.indexed)
    s.copyWith(name: 'print-${i + 1}.${s.extension}'),
];

/// Every print has Bug or Referência (R5).
bool printsTyped(List<SpecPrint> prints) => prints.every((s) => s.kind != null);

/// The format of [bytes] by its signature; null when it is not an image the
/// app accepts.
String? sniffImageExtension(List<int> bytes) {
  bool starts(List<int> sig, [int at = 0]) {
    if (bytes.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'png';
  }
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
      starts(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'webp';
  }
  return null;
}

String _notImage(String? name) =>
    '${name == null ? 'O arquivo' : '"$name"'} não é uma imagem. Aceitos: '
    'PNG, JPEG, WebP e GIF, até 20 MB.';

const printLimitMessage =
    'No máximo $maxPrints prints por spec. Remova um para colar outro.';

/// Target size of [w]×[h] with the longest side at [maxPrintSide]; null
/// when it already fits.
({int width, int height})? reducedSize(int w, int h) {
  final side = w > h ? w : h;
  if (side <= maxPrintSide) return null;
  final scale = maxPrintSide / side;
  return w >= h
      ? (
          width: maxPrintSide,
          height: (h * scale).round().clamp(1, maxPrintSide),
        )
      : (
          width: (w * scale).round().clamp(1, maxPrintSide),
          height: maxPrintSide,
        );
}

/// Checks [bytes], reduces them to [maxPrintSide] with `dart:ui` and writes
/// the print to `.promptorium/attachments/<date>/` of [workspacePath]
/// (R3, R4). [existing] are the prints already attached: the fifth is
/// refused. [sourceName] names the file in the messages.
Future<SpecPrint> preparePrint(
  Uint8List bytes, {
  required String workspacePath,
  List<SpecPrint> existing = const [],
  String? sourceName,
  DateTime? now,
}) async {
  if (existing.length >= maxPrints) {
    throw const PrintException(printLimitMessage);
  }
  if (bytes.length > maxPrintBytes) {
    throw PrintException(
      '${sourceName == null ? 'A imagem' : '"$sourceName"'} tem mais de '
      '20 MB. Reduza a imagem e tente de novo.',
    );
  }
  final format = sniffImageExtension(bytes);
  if (format == null) throw PrintException(_notImage(sourceName));
  final ui.Image first;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    first = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    throw PrintException(_notImage(sourceName));
  }
  final w = first.width;
  final h = first.height;
  final target = reducedSize(w, h);
  var out = bytes;
  var ext = format;
  // A GIF goes as its first frame (out of scope: animation).
  if (target != null || format == 'gif') {
    ui.Image image = first;
    if (target != null) {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: target.width,
        targetHeight: target.height,
      );
      image = (await codec.getNextFrame()).image;
      codec.dispose();
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!identical(image, first)) image.dispose();
    if (png == null) throw PrintException(_notImage(sourceName));
    out = png.buffer.asUint8List();
    ext = 'png';
  }
  first.dispose();
  final dir = await attachmentBatchDir(workspacePath, now: now);
  var file = File('${dir.path}/print-${existing.length + 1}.$ext');
  for (var n = 2; await file.exists(); n++) {
    file = File('${dir.path}/print-${existing.length + 1}-$n.$ext');
  }
  await file.writeAsBytes(out, flush: true);
  return SpecPrint(
    path: file.path,
    name: 'print-${existing.length + 1}.$ext',
    width: target?.width ?? w,
    height: target?.height ?? h,
    originalWidth: target == null ? null : w,
    originalHeight: target == null ? null : h,
  );
}

/// Removes the temporary files of [prints] (discarding the draft, R4, or
/// after the copy, R10). Missing files are fine.
Future<void> deletePrintFiles(Iterable<SpecPrint> prints) async {
  for (final s in prints) {
    try {
      final f = File(s.path);
      if (await f.exists()) await f.delete();
      final dir = f.parent;
      if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
    } on FileSystemException {
      // Already gone or not ours to remove.
    }
  }
}

/// What `index.json` keeps of each print (P6).
@immutable
class PrintMeta {
  const PrintMeta({
    required this.kind,
    this.description = '',
    this.brands = const [],
  });

  final PrintKind kind;
  final String description;
  final List<String> brands;

  Map<String, Object?> toJson() => {
    'tipo': kind.json,
    if (description.isNotEmpty) 'descricao': description,
    if (brands.isNotEmpty) 'marcas': brands,
  };

  static PrintMeta? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = PrintKind.parse(j['tipo']);
    if (kind == null) return null;
    final b = j['marcas'];
    return PrintMeta(
      kind: kind,
      description: '${j['descricao'] ?? ''}'.trim(),
      brands: [
        if (b is List)
          for (final x in b)
            if ('$x'.trim().isNotEmpty) '$x'.trim(),
      ],
    );
  }
}

/// Copies [prints] to `docs/mockups/<code>/print-N.<ext>` of
/// [workspacePath] and records them in `index.json` (R10, P6). Returns the
/// file names. On a failure the copies already made are removed and the
/// error goes up: the spec is not created (R10).
Future<List<String>> copyPrintsToMockups(
  String workspacePath,
  String code,
  List<SpecPrint> prints,
) async {
  if (prints.isEmpty) return const [];
  final dir = p.join(workspacePath, mockupDir(code));
  final named = renumberPrints(prints);
  final written = <File>[];
  try {
    await Directory(dir).create(recursive: true);
    for (final s in named) {
      final target = File(p.join(dir, s.name));
      await File(s.path).copy(target.path);
      written.add(target);
    }
    final index = await PrototypeIndex.read(dir);
    await index
        .copyWith(
          prints: {
            for (final s in named)
              s.name: PrintMeta(
                kind: s.kind ?? PrintKind.bug,
                description: s.description,
                brands: s.brands,
              ),
          },
        )
        .write(dir);
  } catch (_) {
    for (final f in written) {
      await f.delete().catchError((Object _) => f);
    }
    rethrow;
  }
  return [for (final s in named) s.name];
}

/// Brands of the reference prints of `index.json` in [dir] (R9 lint).
Future<List<String>> referenceBrandsOf(String dir) async {
  final index = await PrototypeIndex.read(dir);
  return {
    for (final m in index.prints.values)
      if (m.kind == PrintKind.reference) ...m.brands,
  }.toList();
}

/// One citation of a reference app's brand in the draft (R9).
@immutable
class BrandMention {
  const BrandMention({
    required this.brand,
    required this.where,
    required this.text,
    required this.start,
    required this.end,
  });

  /// The brand as the planner read it ("Nimbo").
  final String brand;

  /// "Título", "Objetivo", "R2", "Fora do escopo", "Print 1".
  final String where;

  /// The whole text it was found in.
  final String text;

  /// Range of the citation in [text].
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is BrandMention &&
      other.brand == brand &&
      other.where == where &&
      other.start == start;

  @override
  int get hashCode => Object.hash(brand, where, start);
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
};

/// Lower case without accents, with the same length (offsets still match).
String foldForSearch(String s) {
  final lower = s.toLowerCase();
  if (lower.length != s.length) return s;
  final b = StringBuffer();
  for (final c in lower.split('')) {
    b.write(_accents[c] ?? c);
  }
  return b.toString();
}

/// Ranges of [brand] in [text]: no case, no accents, whole words only (R9).
List<(int, int)> findBrand(String text, String brand) {
  final needle = foldForSearch(brand.trim());
  if (needle.isEmpty) return const [];
  final hay = foldForSearch(text);
  final re = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(needle)}(?![\\p{L}\\p{N}])',
    unicode: true,
  );
  return [for (final m in re.allMatches(hay)) (m.start, m.end)];
}

/// The brands of the reference prints of [data].
List<String> referenceBrands(SpecDraftData data) => {
  for (final s in data.prints)
    if (s.kind == PrintKind.reference) ...s.brands,
}.toList();

/// Every citation of [brands] in the title, objective, requirements, out of
/// scope and print descriptions of [data] (R9).
List<BrandMention> brandMentions(SpecDraftData data, [List<String>? brands]) {
  final names = brands ?? referenceBrands(data);
  if (names.isEmpty) return const [];
  final fields = <(String, String)>[
    ('Título', data.title),
    ('Objetivo', data.objective),
    for (final (i, r) in data.requirements.indexed) ('R${i + 1}', r),
    for (final o in data.outOfScope) ('Fora do escopo', o),
    for (final (i, s) in data.prints.indexed) ('Print ${i + 1}', s.description),
  ];
  return [
    for (final (where, text) in fields)
      for (final b in names)
        for (final (start, end) in findBrand(text, b))
          BrandMention(
            brand: b,
            where: where,
            text: text,
            start: start,
            end: end,
          ),
  ];
}
