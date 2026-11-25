import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Values of `debt_links.suggestion_state`.
abstract final class DebtSuggestionState {
  static const pending = 'pendente';
  static const accepted = 'aceita';
  static const discarded = 'descartada';
}

/// Values of `debt_links.suggestion_source`.
abstract final class DebtSuggestionSource {
  static const mcp = 'mcp';
  static const interview = 'entrevista';
  static const draft = 'rascunho';
}

/// Values of `debt_links.piggyback_state` (R17).
abstract final class DebtPiggybackState {
  static const toConfirm = 'a_confirmar';
  static const confirmed = 'confirmado';
  static const refused = 'recusado';
}

/// The links of the debts and decisions (SPEC-112 R4, schema v37).
class DebtLinksRepo {
  DebtLinksRepo(this._db);

  final AppDatabase _db;

  $DebtLinksTable get _t => _db.debtLinks;

  /// Links of [repoRoot] (suggestions included), oldest first.
  Stream<List<DebtLink>> watchRepo(String repoRoot) =>
      (_db.select(_t)
            ..where((l) => l.repoRoot.equals(repoRoot))
            ..orderBy([(l) => OrderingTerm.asc(l.id)]))
          .watch();

  Future<List<DebtLink>> forRepo(String repoRoot) =>
      (_db.select(_t)
            ..where((l) => l.repoRoot.equals(repoRoot))
            ..orderBy([(l) => OrderingTerm.asc(l.id)]))
          .get();

  Future<DebtLink?> byId(int id) =>
      (_db.select(_t)..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<DebtLink?> byCode(String repoRoot, String code) =>
      (_db.select(_t)
            ..where((l) => l.repoRoot.equals(repoRoot) & l.code.equals(code)))
          .getSingleOrNull();

  /// Highest number reserved for [prefix] (`DT` / `DP`) in [repoRoot].
  Future<int> maxReserved(String repoRoot, String prefix) async {
    final rows =
        await (_db.selectOnly(_t)
              ..addColumns([_t.code])
              ..where(_t.repoRoot.equals(repoRoot) & _t.code.like('$prefix-%')))
            .get();
    var max = 0;
    for (final r in rows) {
      final n = int.tryParse((r.read(_t.code) ?? '').split('-').last);
      if (n != null && n > max) max = n;
    }
    return max;
  }

  /// Reserves the next code of [prefix]: the highest of [minNumber] - 1 (the
  /// files) and of the codes already reserved, plus one (R3). The unique
  /// index keeps two callers from getting the same code. [link] fills the
  /// other columns; the id of the row is returned with the code.
  Future<({int id, String code})> reserve({
    required String repoRoot,
    required String kind,
    required String prefix,
    required int minNumber,
    DebtLinksCompanion link = const DebtLinksCompanion(),
  }) async {
    for (var attempt = 0; ; attempt++) {
      final n = [
        minNumber,
        await maxReserved(repoRoot, prefix) + 1,
      ].reduce((a, b) => a > b ? a : b);
      final code = '$prefix-${n.toString().padLeft(2, '0')}';
      try {
        final id = await _db
            .into(_t)
            .insert(
              link.copyWith(
                repoRoot: Value(repoRoot),
                kind: Value(kind),
                code: Value(code),
              ),
            );
        return (id: id, code: code);
      } on Exception {
        if (attempt >= 20) rethrow;
      }
    }
  }

  /// A row for a code already in the file (a link to an existing item, e.g.
  /// an item that is now being paid). Returns the id of the link.
  Future<int> ensure(String repoRoot, String kind, String code) async {
    final found = await byCode(repoRoot, code);
    if (found != null) return found.id;
    return _db
        .into(_t)
        .insert(
          DebtLinksCompanion.insert(
            repoRoot: repoRoot,
            kind: kind,
            code: Value(code),
          ),
        );
  }

  /// A pending suggestion (R7, R11): no code yet.
  Future<int> addSuggestion({
    required String repoRoot,
    required String kind,
    required String source,
    required Map<String, Object?> body,
    DebtLinksCompanion link = const DebtLinksCompanion(),
  }) => _db
      .into(_t)
      .insert(
        link.copyWith(
          repoRoot: Value(repoRoot),
          kind: Value(kind),
          suggestionSource: Value(source),
          suggestionState: const Value(DebtSuggestionState.pending),
          suggestionBody: Value(jsonEncode(body)),
        ),
      );

  /// The proposed cells of a suggestion.
  static Map<String, Object?> suggestionOf(DebtLink l) {
    try {
      final d = jsonDecode(l.suggestionBody ?? '{}');
      return d is Map ? d.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    }
  }

  Future<void> update(int id, DebtLinksCompanion values) =>
      (_db.update(_t)..where((l) => l.id.equals(id))).write(values);

  Future<void> delete(int id) =>
      (_db.delete(_t)..where((l) => l.id.equals(id))).go();

  /// Debts being paid by [specId] (R15).
  Future<List<DebtLink>> payingBy(int specId) =>
      (_db.select(_t)..where((l) => l.paymentSpecId.equals(specId))).get();

  /// Debts the steps of [specId] said they paid, in [state] (R17).
  Future<List<DebtLink>> piggybackOf(int specId, {String? state}) =>
      (_db.select(_t)..where(
            (l) =>
                l.piggybackSpecId.equals(specId) &
                (state == null
                    ? const Constant(true)
                    : l.piggybackState.equals(state)),
          ))
          .get();

  /// Discarding [specId] (R15, P7): its debts go back to open and its
  /// "pago de carona?" marks go away.
  Future<void> releaseSpec(int specId) => _db.transaction(() async {
    await (_db.update(_t)..where((l) => l.paymentSpecId.equals(specId))).write(
      const DebtLinksCompanion(paymentSpecId: Value(null)),
    );
    await (_db.update(
      _t,
    )..where((l) => l.piggybackSpecId.equals(specId))).write(
      const DebtLinksCompanion(
        piggybackSpecId: Value(null),
        piggybackState: Value(null),
      ),
    );
  });

  /// The link of the review comment [commentId] (R8).
  Future<DebtLink?> ofReviewComment(int commentId) =>
      (_db.select(_t)
            ..where((l) => l.originReviewCommentId.equals(commentId))
            ..limit(1))
          .getSingleOrNull();

  /// Codes of debts linked to review comments, by comment id (R8).
  Stream<Map<int, String>> watchReviewCommentCodes() =>
      (_db.select(_t)..where(
            (l) => l.originReviewCommentId.isNotNull() & l.code.isNotNull(),
          ))
          .watch()
          .map(
            (rows) => {for (final r in rows) r.originReviewCommentId!: r.code!},
          );
}
