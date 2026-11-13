import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/readonly_run.dart';
import '../../core/git/git_service.dart';
import '../../core/providers/agent_registry.dart' show ClaudeCodeProvider;
import '../../data/providers.dart';
import '../project/project_config.dart';

/// The protections of a VIBE (SPEC-069 R5, R6, R8): its size against the
/// cap, the question when a request seems to be another subject, and
/// whether the diff touches a screen.

/// Changed files and lines (added + removed) of a VIBE against its base.
@immutable
class VibeSize {
  const VibeSize({this.files = 0, this.lines = 0, this.paths = const []});

  final int files;
  final int lines;

  /// The changed paths (the VIBE's own file left out).
  final List<String> paths;

  /// The largest of files / maxFiles and lines / maxLines.
  double ratio(VibeConfig cap) => [
    files / cap.maxFiles,
    lines / cap.maxLines,
  ].reduce((a, b) => a > b ? a : b);

  bool over(VibeConfig cap, {double threshold = 1}) =>
      files > cap.maxFiles * threshold || lines > cap.maxLines * threshold;

  /// "2/15 arquivos · 13/400 linhas" (R6).
  String label(VibeConfig cap) =>
      '$files/${cap.maxFiles} arquivos · $lines/${cap.maxLines} linhas';
}

/// `git diff --numstat` of the worktree against the merge base with [base],
/// plus the untracked files, without [ownFile] (the VIBE's file).
Future<VibeSize> vibeSize(
  GitService wt, {
  required String base,
  String? ownFile,
}) async {
  String from;
  try {
    from = (await wt.git(['merge-base', base, 'HEAD'])).trim();
  } on GitException {
    from = base;
  }
  final byPath = <String, int>{};
  for (final line in (await wt.git([
    'diff',
    '--numstat',
    '--no-renames',
    from,
  ])).split('\n')) {
    final p = line.split('\t');
    if (p.length < 3) continue;
    final n = (int.tryParse(p[0]) ?? 0) + (int.tryParse(p[1]) ?? 0);
    byPath[p.sublist(2).join('\t')] = n;
  }
  for (final rel in (await wt.git([
    'ls-files',
    '--others',
    '--exclude-standard',
  ])).split('\n')) {
    final r = rel.trim();
    if (r.isEmpty) continue;
    try {
      byPath[r] = (await File('${wt.repoRoot}/$r').readAsLines()).length;
    } catch (_) {
      // Unreadable or binary (a print): a file, no lines.
      byPath[r] = 0;
    }
  }
  if (ownFile != null) byPath.remove(ownFile);
  final paths = byPath.keys.toList()..sort();
  return VibeSize(
    files: paths.length,
    lines: byPath.values.fold(0, (a, b) => a + b),
    paths: paths,
  );
}

/// The size of the VIBE [specId] now; `tick` changes when the agent answers
/// (the conversation's message count), so the meter follows it.
final vibeSizeProvider = FutureProvider.autoDispose
    .family<VibeSize?, (int, int)>((ref, key) async {
      final spec = await ref.read(specsRepoProvider).getById(key.$1);
      final wt = spec?.worktreePath;
      if (spec == null || wt == null || !Directory(wt).existsSync()) {
        return null;
      }
      try {
        return await vibeSize(
          ref.read(gitServiceFactoryProvider)(wt),
          base: spec.baseBranch ?? 'main',
          ownFile: spec.path,
        );
      } on GitException catch (e) {
        debugPrint('vibe ${spec.code}: tamanho — $e');
        return null;
      }
    });

/// The cap asks at 100%, and after each "Continuar como VIBE" 50% later
/// (R8). Stored per VIBE.
String vibeCapKey(int specId) => 'vibe.teto.$specId';

/// Where the prints of a VIBE go (R6): `docs/mockups/vibe-007/`.
String vibePrintsDir(String code) => 'docs/mockups/${code.toLowerCase()}';

/// The diff touches a screen (R6): the prints of before and after go to the
/// Review. A heuristic by path.
bool touchesScreen(Iterable<String> paths) => paths.any((p) {
  final l = p.toLowerCase();
  final name = l.split('/').last;
  return RegExp(
        r'\.(html|css|scss|sass|less|tsx|jsx|vue|svelte|xaml|storyboard|xib)$',
      ).hasMatch(name) ||
      RegExp(r'(_screen|_page|_view|_dialog|_widget)\.dart$').hasMatch(name) ||
      RegExp(r'(^|/)(widgets|screens|pages|views|ui|components)/').hasMatch(l);
});

// --- another subject (R5) ----------------------------------------------------

/// What the light check of the Claude says about a new request.
@immutable
class UnrelatedVerdict {
  const UnrelatedVerdict({
    required this.unrelated,
    required this.confidence,
    this.reason = '',
  });

  final bool unrelated;

  /// 0–1.
  final double confidence;
  final String reason;

  /// Only asks with high confidence (R5).
  static const askAt = 0.8;

  bool get ask => unrelated && confidence >= askAt;
}

const _unrelatedSchema = {
  'type': 'object',
  'required': ['outro_assunto', 'confianca'],
  'properties': {
    'outro_assunto': {'type': 'boolean'},
    'confianca': {'type': 'number'},
    'motivo': {'type': 'string'},
  },
};

/// The input of the check: only the title of the VIBE, the summary of the
/// diff, what was already accepted in it and the request.
String unrelatedPrompt({
  required String title,
  required List<String> changed,
  required List<String> accepted,
  required String request,
}) => [
  'Uma tarefa pequena (VIBE) está em andamento: "$title".',
  if (changed.isNotEmpty)
    'Arquivos já mudados: ${changed.take(30).join(', ')}.',
  if (accepted.isNotEmpty)
    'Pedidos já aceitos como parte dela:\n'
        '${accepted.map((a) => '- $a').join('\n')}',
  'Pedido novo: "$request"',
  'O pedido novo é outro assunto, sem relação com a tarefa (algo que '
      'faria sentido num PR separado)? Ajustes, correções e refinamentos '
      'da mesma tarefa NÃO são outro assunto. Responda com outro_assunto, '
      'confianca (0 a 1) e motivo (uma frase curta, em português).',
].join('\n\n');

/// Runs the check (Haiku). Tests answer in its place.
typedef UnrelatedCheck = Future<UnrelatedVerdict> Function({
  required Spec vibe,
  required List<String> changed,
  required List<String> accepted,
  required String request,
});

final unrelatedRequestProvider = Provider<UnrelatedCheck>(
  (ref) =>
      ({
        required vibe,
        required changed,
        required accepted,
        required request,
      }) async {
        final r = await runReadOnlyClaude(
          ref,
          cwd: vibe.worktreePath ?? Directory.systemTemp.path,
          workspaceId: vibe.workspaceId,
          providerId: 'claude',
          timeout: const Duration(seconds: 60),
          options: ClaudeOptions(
            model: 'haiku',
            effort: 'low',
            permissionMode: ClaudePermissionMode.defaultMode,
            disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
            jsonSchema: jsonEncode(_unrelatedSchema),
            maxBudgetUsd: 0.05,
            includePartialMessages: false,
          ),
          prompt: unrelatedPrompt(
            title: vibe.title,
            changed: changed,
            accepted: accepted,
            request: request,
          ),
          denyMessage: 'A checagem de outro assunto é somente leitura.',
        );
        final data = structuredOutput(r);
        if (data is! Map) {
          return const UnrelatedVerdict(unrelated: false, confidence: 0);
        }
        final c = data['confianca'];
        return UnrelatedVerdict(
          unrelated: data['outro_assunto'] == true,
          confidence: c is num ? c.toDouble().clamp(0, 1) : 0,
          reason: '${data['motivo'] ?? ''}'.trim(),
        );
      },
);
