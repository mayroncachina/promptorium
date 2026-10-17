import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/fs/dir_watcher.dart';
import 'package:promptorium/core/process/orphans.dart';
import 'package:promptorium/features/code/worktree_files.dart';

void main() {
  test('orphans: only a claude of that session is ended', () {
    final killed = <int>[];
    final ended = killOrphans(
      {'s1': 10, 's2': 20, 's3': 30},
      read: (pid) => switch (pid) {
        10 => '/home/u/.local/bin/claude\x00-p\x00--resume\x00s1\x00',
        20 => '/usr/bin/vim\x00s2\x00', // PID reused by something else
        _ => null, // gone
      },
      kill: (pid) {
        killed.add(pid);
        return true;
      },
    );
    expect(ended, ['s1']);
    expect(killed, [10]);
  });

  test(
    'DirWatcher: events of each folder, debounced; folders added later',
    () async {
      final tmp = Directory.systemTemp.createTempSync('promptorium-watch-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final sub = Directory('${tmp.path}/a/b')..createSync(recursive: true);
      final batches = <Set<String>>[];
      final w = DirWatcher(
        [tmp.path, sub.path],
        onChange: batches.add,
        debounce: const Duration(milliseconds: 100),
      );
      addTearDown(w.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      File('${sub.path}/x.txt').writeAsStringSync('1');
      File('${tmp.path}/y.txt').writeAsStringSync('1');
      for (var i = 0; i < 50 && batches.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(batches, hasLength(1));
      expect(
        batches.single,
        containsAll(['${sub.path}/x.txt', '${tmp.path}/y.txt']),
      );
      final later = Directory('${tmp.path}/c')..createSync();
      w.update([tmp.path, sub.path, later.path]);
      expect(w.watching, contains(later.path));
    },
  );

  test('atomic write keeps the mode and leaves no temporary file', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-atomic-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final f = File('${tmp.path}/run.sh')..writeAsStringSync('echo 1\n');
    await Process.run('chmod', ['755', f.path]);
    final files = WorktreeFiles(tmp.path);
    await files.write('run.sh', 'echo 2\n');
    expect(f.readAsStringSync(), 'echo 2\n');
    expect(f.statSync().mode & 0x1ff, 0x1ed); // 0755
    expect(tmp.listSync().map((e) => e.uri.pathSegments.last), ['run.sh']);
  });
}
