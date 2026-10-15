import 'dart:io';

/// Runs git in [dir] and fails loudly.
Future<String> gitIn(String dir, List<String> args) async {
  final r = await Process.run('git', ['-C', dir, ...args]);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} falhou: ${r.stderr}');
  }
  return '${r.stdout}';
}

/// Fresh repository on branch `main` with one commit (`a.txt`).
Future<String> createRepo(Directory parent, {String name = 'repo'}) async {
  final dir = Directory('${parent.path}/$name')..createSync(recursive: true);
  await gitIn(dir.path, ['init', '-q', '-b', 'main']);
  await gitIn(dir.path, ['config', 'user.name', 'Teste']);
  await gitIn(dir.path, ['config', 'user.email', 'teste@example.com']);
  await gitIn(dir.path, ['config', 'commit.gpgsign', 'false']);
  File('${dir.path}/a.txt').writeAsStringSync(
    '${[for (var i = 1; i <= 30; i++) 'linha $i'].join('\n')}\n',
  );
  await gitIn(dir.path, ['add', '.']);
  await gitIn(dir.path, ['commit', '-q', '-m', 'inicial']);
  return dir.path;
}
