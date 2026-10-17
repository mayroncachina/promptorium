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
}
