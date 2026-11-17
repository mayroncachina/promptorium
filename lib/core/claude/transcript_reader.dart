import 'dart:convert';
import 'dart:io';

/// Read-only access to the transcript Claude Code keeps of a session
/// (`~/.claude/projects/<encoded cwd>/<session id>.jsonl`), used by the
/// replay only for the file text before each edit (SPEC-082 R10). Never
/// written. A missing or unreadable file is an empty answer, not an error:
/// Claude Code deletes old transcripts.
class TranscriptReader {
  TranscriptReader({String? configDir})
    : configDir = configDir ?? defaultConfigDir();

  /// `$CLAUDE_CONFIG_DIR`, or `~/.claude`.
  final String configDir;

  static String defaultConfigDir() {
    final env = Platform.environment;
    final custom = env['CLAUDE_CONFIG_DIR'];
    if (custom != null && custom.isNotEmpty) return custom;
    return '${env['HOME'] ?? ''}/.claude';
  }

  /// Folder name Claude Code gives the project at [cwd]: every character
  /// that is not a letter or a digit becomes `-`.
  static String encodeCwd(String cwd) =>
      cwd.replaceAll(RegExp('[^a-zA-Z0-9]'), '-');

  /// The transcript of session [externalId] run in [cwd]; when it is not
  /// in the project's folder (the session ran in another directory), the
  /// first `<externalId>.jsonl` of any project. Null = none.
  Future<File?> find(String externalId, {String? cwd}) async {
    if (externalId.isEmpty || externalId.contains('/')) return null;
    final projects = Directory('$configDir/projects');
    if (cwd != null) {
      final f = File('${projects.path}/${encodeCwd(cwd)}/$externalId.jsonl');
      if (await f.exists()) return f;
    }
    try {
      if (!await projects.exists()) return null;
      await for (final d in projects.list(followLinks: false)) {
        if (d is! Directory) continue;
        final f = File('${d.path}/$externalId.jsonl');
        if (await f.exists()) return f;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  /// `tool_use_id` → `toolUseResult.originalFile` of the edits in the
  /// transcript of [externalId]. Invalid lines are skipped.
  Future<Map<String, String>> originalFiles(
    String externalId, {
    String? cwd,
  }) async {
    final file = await find(externalId, cwd: cwd);
    if (file == null) return const {};
    final out = <String, String>{};
    try {
      final lines = file
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      await for (final line in lines) {
        // Cheap filter: most lines carry no originalFile.
        if (!line.contains('"originalFile"')) continue;
        _collect(line, out);
      }
    } on FileSystemException {
      return out;
    }
    return out;
  }

  static void _collect(String line, Map<String, String> out) {
    final Object? j;
    try {
      j = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (j is! Map<String, dynamic>) return;
    final result = j['toolUseResult'];
    if (result is! Map) return;
    final original = result['originalFile'];
    if (original is! String) return;
    final content = j['message'] is Map ? j['message']['content'] : null;
    if (content is! List) return;
    for (final b in content) {
      if (b is Map &&
          b['type'] == 'tool_result' &&
          b['tool_use_id'] is String) {
        out[b['tool_use_id'] as String] = original;
      }
    }
  }
}
