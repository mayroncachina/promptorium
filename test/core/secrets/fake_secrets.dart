/// Fake secrets with the right shape, built at run time so the repository
/// never holds a string a secret scanner would flag (SPEC-085 tests). None
/// of them is a real credential.
library;

/// [n] letters and digits, the same for the same [seed].
String fakeChars(int n, {int seed = 7, String alphabet = _alnum}) {
  var x = seed * 2654435761 % 4294967296;
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) % 2147483648;
    b.write(alphabet[x % alphabet.length]);
  }
  return b.toString();
}

const _alnum = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// The example key of the AWS documentation.
String get fakeAws => ['AKIA', 'IOSFODNN7', 'EXAMPLE'].join();
String get fakeStripe => ['sk', 'live', fakeChars(99, seed: 1)].join('_');
String get fakeGithub => ['ghp', fakeChars(36, seed: 2)].join('_');
String get fakeGitlab => ['glpat', fakeChars(20, seed: 3)].join('-');
String get fakeSlack =>
    ['xoxb', '1234567890', fakeChars(24, seed: 4)].join('-');
String get fakeGoogle => ['AI', 'za', fakeChars(35, seed: 5)].join();
String get fakeAnthropic =>
    ['sk', 'ant', 'api03', fakeChars(40, seed: 6)].join('-');
String get fakeOpenai => ['sk', 'proj', fakeChars(40, seed: 8)].join('-');
String get fakeJwt => [
  ['ey', 'JhbGciOiJIUzI1NiJ9'].join(),
  ['ey', 'JzdWIiOiIxMjM0NTY3ODkwIn0'].join(),
  fakeChars(43, seed: 9),
].join('.');
String get fakeKeyHeader => ['-----BEGIN RSA', 'PRIVATE KEY-----'].join(' ');
String get fakeKeyFooter => ['-----END RSA', 'PRIVATE KEY-----'].join(' ');
List<String> get fakePrivateKey => [
  fakeKeyHeader,
  for (var i = 0; i < 24; i++) fakeChars(64, seed: 20 + i),
  fakeKeyFooter,
];

/// A random-looking 32-character password (entropy > 4).
String get fakeToken => fakeChars(32, seed: 11);

/// Unified diff adding [lines] to [path] (a new file).
String addedDiff(String path, List<String> lines, {int from = 1}) {
  final b = StringBuffer()
    ..writeln('diff --git a/$path b/$path')
    ..writeln('new file mode 100644')
    ..writeln('--- /dev/null')
    ..writeln('+++ b/$path')
    ..writeln('@@ -0,0 +$from,${lines.length} @@');
  for (final l in lines) {
    b.writeln('+$l');
  }
  return b.toString();
}
