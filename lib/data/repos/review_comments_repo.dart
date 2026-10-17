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
}
