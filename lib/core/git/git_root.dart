import 'dart:io';

import '../process/process_runner.dart';

/// A folder that cannot be used as a workspace.
class InvalidWorkspaceFolder implements Exception {
  const InvalidWorkspaceFolder(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => details == null ? message : '$message — $details';
}

/// An existing folder that is not inside a git repository: the workspace
/// selector offers to `git init` it or clone into it (see `RepoSetup`).
class NotAGitRepository extends InvalidWorkspaceFolder {
  const NotAGitRepository(this.path, {super.details})
    : super('A pasta não é um repositório git.');

  /// Absolute folder (`~` expanded).
  final String path;
}

/// Expands a leading `~` with `$HOME`.
String expandHome(String path, {String? home}) {
  final h = home ?? Platform.environment['HOME'];
  if (h == null) return path;
  if (path == '~') return h;
  if (path.startsWith('~/')) return '$h${path.substring(1)}';
  return path;
}

/// Returns the repository root of [folder] (`git rev-parse --show-toplevel`).
///
/// Throws [InvalidWorkspaceFolder] if the folder does not exist or git is not
/// installed, and [NotAGitRepository] if it is not inside a git repository.
Future<String> resolveGitRoot(
  String folder, {
  required ProcessRunner run,
}) async {
  final path = expandHome(folder.trim());
  if (path.isEmpty) {
    throw const InvalidWorkspaceFolder('Informe o caminho da pasta.');
  }
  if (!Directory(path).isAbsolute) {
    throw const InvalidWorkspaceFolder(
      'Use um caminho absoluto (ex.: /home/voce/projeto ou ~/projeto).',
    );
  }
  if (!await Directory(path).exists()) {
    throw InvalidWorkspaceFolder('A pasta não existe.', details: path);
  }
  final ProcessResult result;
  try {
    result = await run('git', ['-C', path, 'rev-parse', '--show-toplevel']);
  } on ProcessException catch (e) {
    throw InvalidWorkspaceFolder('git não encontrado.', details: e.message);
  }
  final out = '${result.stdout}'.trim();
  if (result.exitCode != 0 || out.isEmpty) {
    throw NotAGitRepository(path, details: '${result.stderr}'.trim());
  }
  return out;
}

/// Last path segment (workspace display name).
String folderName(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}
