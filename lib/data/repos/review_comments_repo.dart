import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Comments of the review rounds of a spec (schema v10).
class ReviewCommentsRepo {
  ReviewCommentsRepo(this._db);

  final AppDatabase _db;

  $ReviewCommentsTable get _t => _db.reviewComments;

  Stream<List<ReviewCommentRow>> watchBySpec(int specId) =>
      (_db.select(_t)
            ..where((c) => c.specId.equals(specId))
            ..orderBy([(c) => OrderingTerm.asc(c.id)]))
          .watch();

  Future<List<ReviewCommentRow>> bySpec(int specId) =>
      (_db.select(_t)
            ..where((c) => c.specId.equals(specId))
            ..orderBy([(c) => OrderingTerm.asc(c.id)]))
          .get();

  Future<void> insertAll(List<ReviewCommentsCompanion> rows) =>
      _db.batch((b) => b.insertAll(_t, rows));

  Future<void> setResolved(int id, bool resolved) =>
      (_db.update(_t)..where((c) => c.id.equals(id))).write(
        ReviewCommentsCompanion(
          resolved: Value(resolved),
          resolvedAt: Value(resolved ? DateTime.now() : null),
        ),
      );

  /// Reconciles pre-v16 comments before inserting, in deterministic order.
  Future<void> insertExternal(ReviewCommentsCompanion row) => _db.transaction(
    () async {
      final external = row.externalId.value;
      if (external == null) {
        await _db.into(_t).insert(row);
        return;
      }
      final existing =
          await (_db.select(_t)..where(
                (c) =>
                    c.specId.equals(row.specId.value) &
                    c.externalId.equals(external),
              ))
              .getSingleOrNull();
      if (existing != null) {
        if (existing.body != row.body.value ||
            existing.path != row.path.value ||
            existing.line != row.line.value ||
            existing.commitSha != row.commitSha.value) {
          await (_db.update(_t)..where((c) => c.id.equals(existing.id))).write(
            ReviewCommentsCompanion(
              body: row.body,
              path: row.path,
              line: row.line,
              commitSha: row.commitSha,
            ),
          );
        }
        return;
      }
      final legacy =
          await (_db.select(_t)
                ..where(
                  (c) =>
                      c.specId.equals(row.specId.value) &
                      c.author.equals('pr') &
                      c.externalId.isNull() &
                      c.body.equals(row.body.value),
                )
                ..orderBy([
                  (c) => OrderingTerm.asc(c.createdAt),
                  (c) => OrderingTerm.asc(c.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (legacy != null) {
        await (_db.update(_t)..where((c) => c.id.equals(legacy.id))).write(
          ReviewCommentsCompanion(
            externalId: Value(external),
            path: row.path,
            line: row.line,
            commitSha: row.commitSha,
          ),
        );
      } else {
        await _db.into(_t).insert(row, mode: InsertMode.insertOrIgnore);
      }
    },
  );

  // --- acceptance criteria ---------------------------------------------------

  Stream<List<SpecCriteriaData>> watchCriteria(int specId) => (_db.select(
    _db.specCriteria,
  )..where((c) => c.specId.equals(specId))).watch();

  Future<List<SpecCriteriaData>> criteria(int specId) => (_db.select(
    _db.specCriteria,
  )..where((c) => c.specId.equals(specId))).get();

  /// Marks [criterion] (its text) as checked / unchecked by [by].
  Future<void> setCriterion(
    int specId,
    String criterion, {
    required bool checked,
    required String by,
  }) => _db
      .into(_db.specCriteria)
      .insertOnConflictUpdate(
        SpecCriteriaCompanion.insert(
          specId: specId,
          criterion: criterion,
          checked: Value(checked),
          checkedBy: Value(checked ? by : null),
          checkedAt: Value(checked ? DateTime.now() : null),
        ),
      );

  /// Checks / unchecks [texts] by [by] in one transaction (all or none).
  /// The marks are read again inside it: checking skips what is already
  /// checked (the gate or the reviewer may have checked it meanwhile) and
  /// unchecking skips what is not. Returns the texts actually changed.
  Future<List<String>> setCriteria(
    int specId,
    List<String> texts, {
    required bool checked,
    required String by,
  }) => _db.transaction(() async {
    final marks = {for (final m in await criteria(specId)) m.criterion: m};
    final changed = <String>[];
    for (final t in texts) {
      if ((marks[t]?.checked ?? false) == checked) continue;
      await setCriterion(specId, t, checked: checked, by: by);
      changed.add(t);
    }
    return changed;
  });

  /// Unchecks those of [texts] still checked by the user (`humano`), in one
  /// transaction; a mark the gate or the reviewer made again is kept.
  /// Returns the texts actually unchecked.
  Future<List<String>> uncheckHumanOnly(int specId, List<String> texts) =>
      _db.transaction(() async {
        final marks = {for (final m in await criteria(specId)) m.criterion: m};
        final changed = <String>[];
        for (final t in texts) {
          final m = marks[t];
          if (m == null || !m.checked || m.checkedBy != 'humano') continue;
          await setCriterion(specId, t, checked: false, by: 'humano');
          changed.add(t);
        }
        return changed;
      });
}
