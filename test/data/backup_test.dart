import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'migration_test.dart' show downgrade;

void main() {
  test('a copy is kept before migrating; Restaurar backup is applied on the '
      'next open', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final tmp = Directory.systemTemp.createTempSync('promptorium-bak-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/promptorium.sqlite');
    var db = AppDatabase(NativeDatabase(file, setup: backupBeforeMigration));
    await db.ensureOpen();
    await db.customStatement(
      "INSERT INTO workspaces (path, name) VALUES ('/r', 'antes')",
    );
    await downgrade(db, 11);
    await db.close();
    // Current schema: no copy.
    expect(listBackups(tmp), isEmpty);

    db = AppDatabase(NativeDatabase(file, setup: backupBeforeMigration));
    await db.ensureOpen();
    final backups = listBackups(tmp);
    expect(backups.map((f) => f.uri.pathSegments.last), [
      'promptorium.sqlite.bak-v11',
    ]);
    final raw = sqlite3.open(backups.single.path);
    expect(raw.userVersion, 11);
    expect(raw.select('SELECT name FROM workspaces').single['name'], 'antes');
    raw.close();
    await db.customStatement("UPDATE workspaces SET name = 'depois'");
    await db.close();

    await requestRestore(tmp, backups.single);
    applyPendingRestore(tmp);
    expect(restoreRequest(tmp).existsSync(), isFalse);
    expect(File('${file.path}.antes-da-restauracao').existsSync(), isTrue);
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    await db.ensureOpen(); // migrates the restored v11 again
    expect((await db.select(db.workspaces).getSingle()).name, 'antes');
  });

  test('the copy kept before restoring includes the -wal and -shm, so the '
      'transactions not yet checkpointed survive (SPEC-071 R20)', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-wal-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final live = Directory('${tmp.path}/live')..createSync();
    final dir = Directory('${tmp.path}/data')..createSync();
    final name = '${AppDatabase.fileName}.sqlite';
    final raw = sqlite3.open('${live.path}/$name');
    raw.execute('PRAGMA journal_mode=WAL');
    raw.execute('PRAGMA wal_autocheckpoint=0');
    raw.execute('CREATE TABLE t (v TEXT)');
    raw.execute("INSERT INTO t VALUES ('recente')");
    // A crash: the files as they are while the connection is open.
    for (final side in ['', '-wal', '-shm']) {
      File('${live.path}/$name$side').copySync('${dir.path}/$name$side');
    }
    raw.close();
    expect(File('${dir.path}/$name-wal').lengthSync(), greaterThan(0));

    final backup = File('${tmp.path}/backup.sqlite');
    sqlite3.open(backup.path)
      ..execute('CREATE TABLE t (v TEXT)')
      ..close();
    await requestRestore(dir, backup);
    applyPendingRestore(dir);

    expect(File('${dir.path}/$name-wal').existsSync(), isFalse);
    final before = '${dir.path}/$name.antes-da-restauracao';
    expect(File('$before-wal').existsSync(), isTrue);
    final kept = sqlite3.open(before);
    addTearDown(kept.close);
    expect(kept.select('SELECT v FROM t').single['v'], 'recente');
  });
}
