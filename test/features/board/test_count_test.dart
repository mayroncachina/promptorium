import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/board/test_count.dart';

void main() {
  test('flutter / dart test: the last progress line of a passing run', () {
    const out = '''
Analyzing promptorium...
No issues found! (ran in 4.2s)
00:01 +0: loading /repo/test/a_test.dart
00:12 +398 ~1: /repo/test/b_test.dart: algo
00:45 +751 ~2: All tests passed!
''';
    expect(parseTestCount(out), const TestCount(passed: 751, skipped: 2));
    expect(
      parseTestCount('\x1B[32m00:03 +12: All tests passed!\x1B[0m\n'),
      const TestCount(passed: 12),
    );
    // dart test with the compact reporter rewrites the line with \r.
    expect(
      parseTestCount('00:00 +1: a\r00:00 +3 ~1: All tests passed!'),
      const TestCount(passed: 3, skipped: 1),
    );
  });

  test('pytest: the closing line, with or without -q', () {
    const out = '''
============================= test session starts ==============================
collected 13 items

tests/test_a.py ......s......                                            [100%]

======================== 12 passed, 1 skipped in 0.30s =========================
''';
    expect(parseTestCount(out), const TestCount(passed: 12, skipped: 1));
    expect(
      parseTestCount('.....\n5 passed, 2 warnings in 1.02s\n'),
      const TestCount(passed: 5),
    );
  });

  test('jest and vitest: the Tests line, not Test Suites / Test Files', () {
    const jest = '''
PASS  src/a.test.js
Test Suites: 1 passed, 1 total
Tests:       1 skipped, 3 passed, 4 total
Snapshots:   0 total
Time:        0.512 s
''';
    expect(parseTestCount(jest), const TestCount(passed: 3, skipped: 1));
    const vitest = '''
 ✓ src/a.test.ts (4 tests | 1 skipped) 3ms

 Test Files  1 passed (1)
      Tests  3 passed | 1 skipped (4)
   Start at  10:12:01
   Duration  412ms
''';
    expect(parseTestCount(vitest), const TestCount(passed: 3, skipped: 1));
  });

  test('cargo: summed over the test binaries', () {
    const out = '''
running 13 tests
.............
test result: ok. 12 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0.01s

   Doc-tests demo

running 2 tests
test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.20s
''';
    expect(parseTestCount(out), const TestCount(passed: 14, skipped: 1));
  });

  test('no summary → null', () {
    expect(parseTestCount(''), isNull);
    expect(parseTestCount('3 testes ok\nfeito'), isNull);
    expect(parseTestCount('No issues found!'), isNull);
  });

  test('drop: fewer passing or more skipped; JSON round trip', () {
    const before = TestCount(passed: 10);
    expect(const TestCount(passed: 9).droppedFrom(before), isTrue);
    expect(const TestCount(passed: 10, skipped: 1).droppedFrom(before), isTrue);
    expect(const TestCount(passed: 11).droppedFrom(before), isFalse);
    expect(const TestCount(passed: 10).droppedFrom(before), isFalse);
    const c = TestCount(passed: 751, skipped: 2);
    expect(TestCount.fromJson(c.toJson()), c);
    expect(c.toJson(), {'passaram': 751, 'pulados': 2});
    expect(TestCount.fromJson('x'), isNull);
    expect('$c', '751 passaram, 2 pulados');
  });
}
