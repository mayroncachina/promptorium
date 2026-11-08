import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/repository/graph/commit_log.dart';
import 'package:promptorium/features/repository/graph/lane_layout.dart';

/// Time of the first page and of the next ones on a real repository, read
/// only (SPEC-045 R7). Runs with `GRAPH_PERF_REPO=/path flutter test
/// test/features/repository/graph_perf_test.dart`; skipped otherwise.
void main() {
  final env = Platform.environment;
  final path = env['GRAPH_PERF_REPO'];
  final branch = env['GRAPH_PERF_BRANCH'] ?? 'main';
  final maxPages = int.tryParse(env['GRAPH_PERF_PAGES'] ?? '') ?? 1 << 30;
  test('first page and paging on a real repository', () async {
    final log = CommitLog(
      GitService(path!),
      defaultBranch: branch,
      remote: 'origin',
    );
    const q = GraphQuery(remoteOnly: true);
    final total = Stopwatch()..start();
    final first = Stopwatch()..start();
    final refs = await log.refs();
    final revs = log.revisions(q, refs);
    final count = await log.count(q, revs);
    var page = await log.page(q, revs);
    final read1 = first.elapsedMicroseconds;
    final l = Stopwatch()..start();
    var lay = layoutLanes(
      page.rows,
      defaultBranch: branch,
      collapsed: (n) => !refs.openSpecNumbers.contains(n),
    );
    final lay1 = l.elapsedMicroseconds;
    final firstMs = first.elapsedMilliseconds;
    var rows = page.rows.length;
    final pages = <String>[];
    while (page.more && pages.length < maxPages) {
      final p = Stopwatch()..start();
      page = await log.page(q, revs, skip: rows);
      final read = p.elapsedMilliseconds;
      final lp = Stopwatch()..start();
      lay = layoutLanes(
        page.rows,
        defaultBranch: branch,
        from: lay.state,
        collapsed: (n) => !refs.openSpecNumbers.contains(n),
      );
      pages.add('${read}ms git + ${lp.elapsedMicroseconds}µs layout');
      rows += page.rows.length;
    }
    final full = Stopwatch()..start();
    final all = await log.page(q, revs, limit: rows);
    final allLay = layoutLanes(all.rows, defaultBranch: branch);
    final fullMs = full.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'commits: $count · 1ª página: ${firstMs}ms '
      '(git ${read1 ~/ 1000}ms, layout $lay1 µs) · '
      'páginas seguintes: ${pages.join('; ')} · '
      'as $rows de uma vez: ${fullMs}ms, ${allLay.rows.length} linhas, '
      'raias até ${allLay.rows.fold(0, (w, r) => r.width > w ? r.width : w)} '
      '· total ${total.elapsedMilliseconds}ms',
    );
    if (page.more) {
      expect(rows, pages.length * CommitLog.pageSize + CommitLog.pageSize);
    } else {
      expect(rows, count);
    }
  }, skip: path == null ? 'GRAPH_PERF_REPO não definido' : false);
}
