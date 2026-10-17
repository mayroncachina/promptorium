import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// History of the notifications shown by the app (schema v12).
class NotificationsRepo {
  NotificationsRepo(this._db);

  final AppDatabase _db;

  $NotificationsTable get _t => _db.notifications;

  static const keep = 200;

  /// Fires after every change (a plain broadcast: the title bar listens to
  /// it without keeping a query stream open).
  static final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  Future<List<AppNotification>> recent({int limit = 100}) =>
      (_db.select(_t)
            ..orderBy([(n) => OrderingTerm.desc(n.id)])
            ..limit(limit))
          .get();

  /// Records one (the oldest beyond [keep] go away).
  Future<void> add({
    required String title,
    required String body,
    String? section,
    String? sessionId,
  }) async {
    await _db
        .into(_t)
        .insert(
          NotificationsCompanion.insert(
            title: title,
            body: body,
            section: Value(section),
            sessionId: Value(sessionId),
          ),
        );
    await _db.customStatement(
      'DELETE FROM notifications WHERE id NOT IN '
      '(SELECT id FROM notifications ORDER BY id DESC LIMIT $keep)',
    );
    _changes.add(null);
  }

  Future<void> markAllRead() async {
    await _db.update(_t).write(const NotificationsCompanion(read: Value(true)));
    _changes.add(null);
  }

  Future<void> clear() async {
    await _db.delete(_t).go();
    _changes.add(null);
  }
}
