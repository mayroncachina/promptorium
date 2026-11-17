import 'package:drift/drift.dart';

import '../../core/secrets/secret_rules.dart';
import '../db/app_database.dart';

/// Minimum length of the reason of a waiver (SPEC-085 R11).
const secretWaiverMinReason = 10;

/// Days without a match after which a waiver goes away by itself (R12).
const secretWaiverMaxIdleDays = 90;

/// `secret_waivers.scope`.
abstract final class SecretWaiverScope {
  /// The same value (fingerprint) in any file of the workspace.
  static const value = 'valor';

  /// Any finding of the rule in this path.
  static const file = 'arquivo';
}

/// Findings of the Vigia de segredos ignored with a reason (SPEC-085 R11,
/// R12). Only the fingerprint of the value is stored, never the value.
class SecretWaiversRepo {
  SecretWaiversRepo(this._db);

  final AppDatabase _db;

  $SecretWaiversTable get _t => _db.secretWaivers;

  Stream<List<SecretWaiver>> watch(int workspaceId) =>
      (_db.select(_t)
            ..where((w) => w.workspaceId.equals(workspaceId))
            ..orderBy([(w) => OrderingTerm.desc(w.createdAt)]))
          .watch();

  /// The waivers of [workspaceId], after removing the ones idle for more
  /// than 90 days (R12).
  Future<List<SecretWaiver>> active(int workspaceId, {DateTime? now}) async {
    final limit = (now ?? DateTime.now()).subtract(
      const Duration(days: secretWaiverMaxIdleDays),
    );
    await (_db.delete(_t)..where(
          (w) =>
              w.workspaceId.equals(workspaceId) &
              w.lastUsedAt.isSmallerThanValue(limit),
        ))
        .go();
    return (_db.select(
      _t,
    )..where((w) => w.workspaceId.equals(workspaceId))).get();
  }

  /// [active] as the scanners read it.
  Future<List<SecretWaiverRef>> refs(int workspaceId) async => [
    for (final w in await active(workspaceId)) refOf(w),
  ];

  static SecretWaiverRef refOf(SecretWaiver w) => SecretWaiverRef(
    id: w.id,
    rule: w.rule,
    path: w.path,
    fingerprint: w.fingerprint,
    byValue: w.scope == SecretWaiverScope.value,
  );

  /// Records a waiver; throws [ArgumentError] on a reason shorter than
  /// [secretWaiverMinReason].
  Future<int> add({
    required int workspaceId,
    required String rule,
    required String path,
    required String fingerprint,
    required String scope,
    required String reason,
    required String origin,
  }) {
    final r = reason.trim();
    if (r.length < secretWaiverMinReason) {
      throw ArgumentError.value(reason, 'reason', 'mínimo de 10 caracteres');
    }
    return _db
        .into(_t)
        .insert(
          SecretWaiversCompanion.insert(
            workspaceId: workspaceId,
            rule: rule,
            path: path,
            fingerprint: scope == SecretWaiverScope.value ? fingerprint : '',
            scope: scope,
            reason: r,
            origin: origin,
          ),
        );
  }

  /// The waivers [ids] matched a finding now (R12).
  Future<void> touch(Iterable<int> ids, {DateTime? at}) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.update(_t)..where((w) => w.id.isIn(list))).write(
      SecretWaiversCompanion(lastUsedAt: Value(at ?? DateTime.now())),
    );
  }

  Future<void> remove(int id) =>
      (_db.delete(_t)..where((w) => w.id.equals(id))).go();
}
