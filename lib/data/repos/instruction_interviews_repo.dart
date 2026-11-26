import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// The interview of "Melhorar com IA" (SPEC-113 R18), one per workspace.
class InstructionInterviewsRepo {
  InstructionInterviewsRepo(this._db);

  final AppDatabase _db;

  $InstructionInterviewsTable get _t => _db.instructionInterviews;

  SimpleSelectStatement<$InstructionInterviewsTable, InstructionInterview> _of(
    int workspaceId,
  ) => _db.select(_t)..where((i) => i.workspaceId.equals(workspaceId));

  Future<InstructionInterview?> get(int workspaceId) =>
      _of(workspaceId).getSingleOrNull();

  Stream<InstructionInterview?> watch(int workspaceId) =>
      _of(workspaceId).watchSingleOrNull();

  /// Starts the interview on [provider] (R17), replacing an old one.
  Future<InstructionInterview> start(
    int workspaceId, {
    required String provider,
    String data = '{}',
  }) => _db
      .into(_t)
      .insertReturning(
        InstructionInterviewsCompanion.insert(
          workspaceId: Value(workspaceId),
          provider: provider,
          data: Value(data),
        ),
        mode: InsertMode.insertOrReplace,
      );

  /// Writes [changes] and bumps `updatedAt`. A discarded interview stays
  /// gone.
  Future<void> update(
    int workspaceId,
    InstructionInterviewsCompanion changes,
  ) => (_db.update(_t)..where((i) => i.workspaceId.equals(workspaceId))).write(
    changes.copyWith(updatedAt: Value(DateTime.now())),
  );

  /// Adds [delta] tokens.
  Future<void> addTokens(int workspaceId, int delta) async {
    if (delta <= 0) return;
    final row = await get(workspaceId);
    if (row == null) return;
    await update(
      workspaceId,
      InstructionInterviewsCompanion(tokens: Value(row.tokens + delta)),
    );
  }

  Future<int> delete(int workspaceId) =>
      (_db.delete(_t)..where((i) => i.workspaceId.equals(workspaceId))).go();
}
