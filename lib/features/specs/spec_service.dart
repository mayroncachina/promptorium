import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repos/specs_repo.dart';
import '../sessions/session_manager.dart' show slugify;
import 'spec_file.dart';

export 'spec_file.dart';

class SpecException implements Exception {
  const SpecException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Next `SPEC-NNN` of the workspace: 1 + the highest number found in the
/// `specs` table or in `<workspace>/specs/SPEC-*`.
Future<String> nextSpecCode(SpecsRepo repo, Workspace workspace) async {
  var max = await repo.maxNumber(workspace.id);
  final dir = Directory('${workspace.path}/specs');
  if (await dir.exists()) {
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final m = RegExp(r'^SPEC-(\d+)').firstMatch(name);
      if (m != null) max = math.max(max, int.parse(m.group(1)!));
    }
  }
  return 'SPEC-${(max + 1).toString().padLeft(3, '0')}';
}

/// Spec files of a workspace (`specs/SPEC-*.md`) ↔ `specs` table.
class SpecService {
  SpecService(this._repo);

  final SpecsRepo _repo;

  /// Reads `specs/SPEC-*.md`, inserts the files missing from the table and
  /// updates title / status / path of the others (the file is the source).
  /// Rows whose file disappeared are kept (shown as "arquivo ausente").
  Future<void> sync(Workspace ws) async {
    final dir = Directory('${ws.path}/specs');
    if (!await dir.exists()) return;
    final files = <File>[];
    await for (final f in dir.list()) {
      if (f is File && f.path.toLowerCase().endsWith('.md')) files.add(f);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final seen = <String>{};
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final String text;
      try {
        text = await f.readAsString();
      } on FileSystemException {
        continue;
      }
      final doc = SpecDocument.parse(text);
      final code = _codeOf(doc, name);
      if (code == null || !seen.add(code)) continue;
      await _upsert(ws, code: code, rel: 'specs/$name', doc: doc);
    }
  }

  static String? _codeOf(SpecDocument doc, String fileName) {
    final id = doc.id;
    if (id != null && RegExp(r'^SPEC-\d+$').hasMatch(id)) return id;
    return specCodeFromFileName(fileName);
  }

  Future<Spec> _upsert(
    Workspace ws, {
    required String code,
    required String rel,
    required SpecDocument doc,
  }) async {
    final title = doc.title ?? code;
    final existing = await _repo.getByCode(ws.id, code);
    if (existing == null) {
      return _repo.insert(
        workspaceId: ws.id,
        code: code,
        title: title,
        path: rel,
        status: doc.status ?? SpecStatus.draft,
      );
    }
    final status = doc.status ?? existing.status;
    if (existing.title != title ||
        existing.path != rel ||
        existing.status != status) {
      await _repo.update(
        existing.id,
        SpecsCompanion(
          title: Value(title),
          path: Value(rel),
          status: Value(status),
        ),
      );
    }
    return (await _repo.getById(existing.id))!;
  }

  /// Relative paths a spec may have: one `.md` file directly inside
  /// `<workspace>/specs` (no separators, no `..`) — guards against a row
  /// pointing outside the folder (path traversal).
  static final _specPath = RegExp(r'^specs/[^/\\]+\.md$');

  static bool isSafeSpecPath(String rel) => _specPath.hasMatch(rel);

  File fileOf(Workspace ws, Spec spec) {
    if (!isSafeSpecPath(spec.path)) {
      throw SpecException('Caminho de spec inválido: ${spec.path}');
    }
    return File('${ws.path}/${spec.path}');
  }

  /// File text (null when the file does not exist).
  Future<String?> read(Workspace ws, Spec spec) async {
    final f = fileOf(ws, spec);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  /// Writes [text] (temporary file + rename) and refreshes the row.
  Future<Spec> save(Workspace ws, Spec spec, String text) async {
    final f = fileOf(ws, spec);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.promptorium-tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
    final doc = SpecDocument.parse(text);
    return _upsert(ws, code: spec.code, rel: spec.path, doc: doc);
  }

  /// "Nova spec": `specs/SPEC-NNN-<slug>.md` with [body], or the text
  /// [render] builds for the new code (default template).
  Future<Spec> create(
    Workspace ws, {
    required String title,
    String? body,
    String Function(String code)? render,
  }) async {
    final t = title.trim();
    if (t.isEmpty) throw const SpecException('Informe o título da spec.');
    final code = await nextSpecCode(_repo, ws);
    final slug = slugify(t, maxLength: 40);
    final rel = 'specs/$code${slug.isEmpty ? '' : '-$slug'}.md';
    final file = File('${ws.path}/$rel');
    await file.parent.create(recursive: true);
    // Exclusive create: a second click racing on the same number fails here
    // instead of overwriting the first draft.
    try {
      await file.create(exclusive: true);
    } on FileSystemException {
      throw SpecException('O arquivo $rel já existe.');
    }
    final text =
        body ?? render?.call(code) ?? newSpecMarkdown(code: code, title: t);
    await file.writeAsString(text);
    final doc = SpecDocument.parse(text);
    final existing = await _repo.getByCode(ws.id, code);
    if (existing != null) return _upsert(ws, code: code, rel: rel, doc: doc);
    return _repo.insert(
      workspaceId: ws.id,
      code: code,
      title: doc.title ?? t,
      path: rel,
      status: doc.status ?? SpecStatus.draft,
    );
  }

  /// "Aprovar spec": `status: aprovada` in the frontmatter of [text] (the
  /// editor content, unsaved changes included), saved to disk.
  Future<({Spec spec, String text})> approve(
    Workspace ws,
    Spec spec,
    String text,
  ) async {
    final updated = SpecDocument.parse(text)
        .withMeta(id: spec.code, status: SpecStatus.approved);
    final saved = await save(ws, spec, updated);
    return (spec: saved, text: updated);
  }
}

final specServiceProvider = Provider(
  (ref) => SpecService(ref.watch(specsRepoProvider)),
);

/// Spec selected in the Specs screen (null = first of the list).
class SelectedSpec extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}

final selectedSpecProvider = NotifierProvider<SelectedSpec, int?>(
  SelectedSpec.new,
);
