import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repos/sessions_repo.dart';
import '../../data/repos/specs_repo.dart';
import '../project/project_service.dart' show TrashFolder, trashFolderProvider;
import '../project/project_config.dart';
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
  final dir = Directory(
    '${workspace.path}/${ProjectConfig.loadSync(workspace.path).specsDir}',
  );
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
  SpecService(this._repo, {SessionsRepo? sessions, TrashFolder? trash})
    // ignore: prefer_initializing_formals
    : _sessions = sessions,
      // ignore: prefer_initializing_formals
      _trash = trash;

  final SpecsRepo _repo;
  final SessionsRepo? _sessions;
  final TrashFolder? _trash;

  /// Reads `specs/SPEC-*.md`, inserts the files missing from the table and
  /// updates title / status / path of the others (the file is the source).
  /// Rows whose file disappeared are kept (shown as "arquivo ausente").
  Future<void> sync(Workspace ws) async {
    final specsDir = ProjectConfig.loadSync(ws.path).specsDir;
    final dir = Directory('${ws.path}/$specsDir');
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
      await _upsert(ws, code: code, rel: '$specsDir/$name', doc: doc);
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
    final reqs = doc.requirements;
    final existing = await _repo.getByCode(ws.id, code);
    if (existing == null) {
      return _repo.insert(
        workspaceId: ws.id,
        code: code,
        title: title,
        path: rel,
        status: doc.status ?? SpecStatus.draft,
        requirements: reqs,
        dependsOn: doc.dependsOn,
        phase: doc.phase,
      );
    }
    final status = doc.status ?? existing.status;
    // `depende-de` absent from the file keeps the stored list (written by
    // the schema v8 migration or the Projeto screen until the next save).
    final deps = doc.hasDependsOn ? doc.dependsOn : existing.dependsOn;
    if (existing.title != title ||
        existing.path != rel ||
        existing.status != status ||
        existing.phase != doc.phase ||
        !_sameReqs(existing.requirements, reqs) ||
        existing.dependsOn.join(',') != deps.join(',')) {
      await _repo.update(
        existing.id,
        SpecsCompanion(
          title: Value(title),
          path: Value(rel),
          status: Value(status),
          phase: Value(doc.phase),
          requirements: Value(reqs),
          dependsOn: Value(deps),
        ),
      );
    }
    return (await _repo.getById(existing.id))!;
  }

  static bool _sameReqs(List<SpecRequirement> a, List<SpecRequirement> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Relative paths a spec may have: a `.md` file in a plain folder of the
  /// workspace (no `..`, no absolute path, not inside `.git` /
  /// `.promptorium`) — guards against a row pointing outside the workspace
  /// (path traversal). The folder is configurable and may change over time,
  /// so older specs keep their path.
  static final _specPath = RegExp(
    r'^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*/[A-Za-z0-9._ -]+\.md$',
  );

  static bool isSafeSpecPath(String rel) {
    if (!_specPath.hasMatch(rel)) return false;
    final parts = rel.split('/');
    return !parts.any((p) => p == '.' || p == '..') &&
        parts.first != '.git' &&
        parts.first != '.promptorium';
  }

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

  /// Writes [text] (temporary file + rename) and refreshes the row. Stored
  /// dependencies missing from the file are written to its frontmatter.
  Future<Spec> save(Workspace ws, Spec spec, String text) async {
    final current = SpecDocument.parse(text);
    if (!current.hasDependsOn && spec.dependsOn.isNotEmpty) {
      text = current.withMeta(dependsOn: spec.dependsOn);
    }
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
    final rel =
        '${ProjectConfig.loadSync(ws.path).specsDir}/$code${slug.isEmpty ? '' : '-$slug'}.md';
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
      requirements: doc.requirements,
      dependsOn: doc.dependsOn,
      phase: doc.phase,
    );
  }

  /// "Clonar para alterar": a new draft spec with the text of [spec] minus
  /// the requirements in [doneIds], depending on [spec].
  Future<Spec> cloneForChange(
    Workspace ws,
    Spec spec, {
    required Set<String> doneIds,
  }) async {
    final text = await read(ws, spec);
    if (text == null) throw SpecException('O arquivo ${spec.path} não existe.');
    final title = '${SpecDocument.parse(text).title ?? spec.title} (alteração)';
    return create(
      ws,
      title: title,
      render: (code) => cloneSpecText(
        text,
        newCode: code,
        originalCode: spec.code,
        doneIds: doneIds,
      ),
    );
  }

  /// "Arquivar": a finished spec leaves the lists (`status: arquivada`).
  /// [restore] puts it back as concluded.
  Future<Spec> archive(Workspace ws, Spec spec, {bool restore = false}) async {
    if (!restore && spec.stage != SpecStage.done) {
      throw SpecException('${spec.code} ainda não foi concluída.');
    }
    final text = await read(ws, spec);
    if (text == null) throw SpecException('O arquivo ${spec.path} não existe.');
    final status = restore ? SpecStatus.done : SpecStatus.archived;
    return save(ws, spec, SpecDocument.parse(text).withMeta(status: status));
  }

  /// Codes of the specs that list [spec] in `depende-de`.
  Future<List<String>> dependentsOf(Workspace ws, Spec spec) async => [
    for (final o in await _repo.watchByWorkspace(ws.id).first)
      if (o.id != spec.id && o.dependsOn.contains(spec.code)) o.code,
  ];

  /// "Excluir": only a spec never executed. The file goes to the trash
  /// (recoverable) and the row is removed.
  Future<void> delete(Workspace ws, Spec spec) async {
    final sessions = await _sessions?.bySpec(spec.id) ?? const [];
    if (spec.stage != SpecStage.backlog ||
        spec.worktreePath != null ||
        sessions.isNotEmpty) {
      throw SpecException(
        '${spec.code} já foi executada: arquive em vez de excluir.',
      );
    }
    final f = fileOf(ws, spec);
    if (await f.exists()) {
      final trash = _trash;
      if (trash == null) throw const SpecException('Lixeira indisponível.');
      await trash(f.path);
    }
    await _repo.delete(spec.id);
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
  (ref) => SpecService(
    ref.watch(specsRepoProvider),
    sessions: ref.watch(sessionsRepoProvider),
    trash: ref.watch(trashFolderProvider),
  ),
);

/// "Arquivadas": show the archived specs in the Specs list and the Quadro.
class ShowArchived extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final showArchivedProvider = NotifierProvider<ShowArchived, bool>(
  ShowArchived.new,
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
