import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../core/providers/agent_provider.dart' show PromptMode;
import '../../core/git/worktree_setup.dart';
import '../../core/process/shell_runner.dart';
import '../../data/providers.dart';
import '../board/spec_runner.dart' show gateNote, gateRunningProvider;
import '../board/step_gate.dart';
import '../project/project_config.dart';
import '../prompt/conversation_manager.dart';
import '../sessions/session_manager.dart'
    show slugify, sessionIdGeneratorProvider, vibeSessionPrefix;
import '../specs/spec_service.dart';

/// The modo vibe code (SPEC-069): "Fazer como tarefa" asks the agent
/// directly, with no spec written. The app writes a VIBE (a minimal spec,
/// [newVibeMarkdown]) in a worktree and branch of its own, and the VIBE goes
/// through the Quadro, the gate and the Review like any spec.

class VibeException implements Exception {
  const VibeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the "Fazer como tarefa" dialog shows before the VIBE is born (R1).
@immutable
class VibePreview {
  const VibePreview({
    required this.code,
    required this.title,
    required this.branch,
    required this.base,
  });

  final String code;
  final String title;
  final String branch;
  final String base;
}

/// Title of a VIBE: the first line of the request, short.
String vibeTitle(String request) => conversationTitle(request, max: 60);

/// `007-botao-comprar-verde` for `VIBE-007` (the branch is `vibe/<slug>`).
String vibeSlug(String code, String title) {
  final n = code.substring(code.indexOf('-') + 1);
  final s = slugify(title, maxLength: 28);
  return s.isEmpty ? n : '$n-$s';
}

bool isVibeSession(String sessionId) => sessionId.startsWith(vibeSessionPrefix);

class VibeService {
  VibeService(this._ref);

  final Ref _ref;

  GitService _git(String root) => _ref.read(gitServiceFactoryProvider)(root);

  Future<String> _base(Workspace ws) async {
    final config = ProjectConfig.loadSync(ws.path);
    return config.baseBranch ?? await _git(ws.path).currentBranch() ?? 'main';
  }

  /// The number, branch and base "Começar VIBE" would use now (R1).
  Future<VibePreview> preview(Workspace ws, String request) async {
    final code = await nextSpecCode(
      _ref.read(specsRepoProvider),
      ws,
      kind: SpecKind.vibe,
    );
    final title = vibeTitle(request);
    String base;
    try {
      base = await _base(ws);
    } catch (_) {
      base = 'main';
    }
    return VibePreview(
      code: code,
      title: title,
      branch: 'vibe/${vibeSlug(code, title)}',
      base: base,
    );
  }

  /// "Começar VIBE" (R1, R3, R4, R12): reserves the number, creates the
  /// worktree and the branch `vibe/NNN-<slug>`, writes the VIBE there,
  /// puts the card in Em execução and opens the conversation in edit mode
  /// with the agent in the worktree. Returns the conversation id.
  Future<({Spec spec, int conversationId})> start(
    Workspace ws,
    String request, {
    String? model,
    String? providerId,
  }) async {
    final text = request.trim();
    if (text.isEmpty) throw const VibeException('Diga o que fazer.');
    final repo = _ref.read(specsRepoProvider);
    final config = ProjectConfig.loadSync(ws.path);
    final title = vibeTitle(text);
    final code = await nextSpecCode(repo, ws, kind: SpecKind.vibe);
    final rel =
        '${config.vibeDir}/$code${slugify(title, maxLength: 40).isEmpty ? '' : '-${slugify(title, maxLength: 40)}'}.md';
    // R12: the number is reserved in the database the moment it is born.
    await repo.reserve(ws.id, code);
    var spec = await repo.insert(
      workspaceId: ws.id,
      code: code,
      title: title,
      path: rel,
      status: SpecStatus.approved,
      requirements: [
        (id: 'R1', text: text.replaceAll(RegExp(r'\s*\n\s*'), ' ')),
      ],
      kind: SpecKind.vibe,
      stage: SpecStage.running,
    );
    final main = _git(ws.path);
    final CreatedWorktree wt;
    final String base;
    try {
      base = await _base(ws);
      wt = await main.addWorktree(
        vibeSlug(code, title),
        baseBranch: base,
        prefix: 'vibe',
      );
    } on GitException catch (e) {
      await repo.delete(spec.id);
      throw VibeException('Falha ao criar o worktree da VIBE: $e');
    }
    final others = await repo.watchByWorkspace(ws.id).first;
    await repo.setWorktree(
      spec.id,
      path: wt.path,
      branch: wt.branch,
      baseBranch: base,
      index: nextWorktreeIndex([
        for (final o in others)
          if (o.id != spec.id && o.worktreePath != null) o.worktreeIndex,
      ]),
    );
    // The VIBE goes into the PR: its file is the first commit of the branch.
    final file = File('${wt.path}/$rel');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      newVibeMarkdown(code: code, title: title, request: text),
    );
    final git = _git(wt.path);
    try {
      await git.git(['add', '--', rel]);
      await git.git(['commit', '-q', '-m', '$code: $title', '--', rel]);
    } on GitException catch (e) {
      // A hook refused it: the gate commits it with the work.
      debugPrint('vibe $code: commit do arquivo — $e');
    }
    await _prepare(ws, spec.id, wt.path, config, code);
    spec = (await repo.getById(spec.id))!;
    final conv = await _ref
        .read(conversationManagerProvider.notifier)
        .create(
          workspace: ws,
          text: text,
          mode: PromptMode.edit,
          model: model,
          providerId: providerId,
          specId: spec.id,
          title: title,
        );
    return (spec: spec, conversationId: conv);
  }

  /// `copiar:` and `preparar:` of the config in the new worktree, as a spec's.
  Future<void> _prepare(
    Workspace ws,
    int specId,
    String worktree,
    ProjectConfig config,
    String code,
  ) async {
    final wc = config.worktree;
    if (wc.copy.isNotEmpty || wc.prepare != null) {
      final r =
          await WorktreeSetup(
            root: _git(ws.path),
            shell: _ref.read(shellRunnerProvider),
          ).run(
            worktree,
            copy: wc.copy,
            prepare: wc.prepare,
            timeout: config.gate.timeout,
            environment: worktreeEnvironment(
              root: ws.path,
              worktree: worktree,
              specCode: code,
            ),
          );
      if (!r.ok) {
        debugPrint('vibe $code: preparar falhou — ${r.prepare?.output}');
        return;
      }
    }
    await _ref.read(specsRepoProvider).setPrepared(specId, DateTime.now());
  }

  /// "Enviar para Review" (R6, R7): commits what is pending in the
  /// worktree, runs the gate as in a spec and, when it passes, moves the card
  /// to Review. Returns the gate's report (a failure keeps the card in Em
  /// execução, with the report in the conversation).
  Future<GateReport> sendToReview(int specId) async {
    final repo = _ref.read(specsRepoProvider);
    final spec = await repo.getById(specId);
    if (spec == null) throw const VibeException('VIBE não encontrada.');
    final ws = await _ref
        .read(workspacesRepoProvider)
        .getById(spec.workspaceId);
    final wt = spec.worktreePath;
    if (ws == null || wt == null || !Directory(wt).existsSync()) {
      throw VibeException('${spec.code} não tem worktree.');
    }
    if (spec.stage == SpecStage.done) {
      throw VibeException('${spec.code} já foi mergeada.');
    }
    final conv = await repo.conversationOf(specId);
    final manager = _ref.read(conversationManagerProvider.notifier);
    if (conv != null &&
        _ref.read(conversationManagerProvider).isBusy(conv.id)) {
      throw const VibeException('Espere o agente terminar a resposta.');
    }
    final gates = _ref.read(gateRunningProvider.notifier);
    if (!gates.add(specId)) {
      throw VibeException('${spec.code} já está em verificação.');
    }
    try {
      final config = ProjectConfig.loadSync(ws.path);
      final git = _git(wt);
      await git.commitAll('${spec.code} R1: ${spec.title}');
      final base = spec.baseBranch ?? await _base(ws);
      String? start;
      try {
        start = (await git.git(['merge-base', base, 'HEAD'])).trim();
      } on GitException {
        start = null;
      }
      if (conv != null) {
        await manager.note(conv.id, 'Verificando ${spec.code}…');
      }
      final report =
          await StepGate(git: git, shell: _ref.read(shellRunnerProvider)).run(
            specCode: spec.code,
            steps: const ['R1'],
            startSha: start,
            config: config,
            environment: worktreeEnvironment(
              root: ws.path,
              worktree: wt,
              specCode: spec.code,
            ),
          );
      if (conv != null) {
        await manager.note(conv.id, gateNote(report), error: !report.ok);
      }
      final steps = _ref.read(specStepsRepoProvider);
      if (!report.ok) {
        await steps.set(specId, 'R1', StepStatus.needsInput);
        return report;
      }
      final session = await _reviewSession(spec, ws, conv);
      await steps.set(specId, 'R1', StepStatus.done, sessionId: session);
      await repo.setStage(specId, SpecStage.review);
      if (conv != null) {
        await manager.note(
          conv.id,
          '${spec.code} foi para o Review. Um pedido novo aqui a traz de volta '
          'para Em execução.',
        );
      }
      return report;
    } finally {
      gates.remove(specId);
    }
  }

  /// The session row the Review works with (its queue, diff and merge are
  /// by session): one per VIBE, reused at each "Enviar para Review".
  Future<String> _reviewSession(
    Spec spec,
    Workspace ws,
    Conversation? conv,
  ) async {
    final sessions = _ref.read(sessionsRepoProvider);
    for (final s in await sessions.bySpec(spec.id)) {
      if (isVibeSession(s.id)) {
        await sessions.setStatus(s.id, SessionStatus.completed);
        return s.id;
      }
    }
    final id = '$vibeSessionPrefix${_ref.read(sessionIdGeneratorProvider)()}';
    await sessions.insert(
      id: id,
      workspaceId: ws.id,
      worktreePath: spec.worktreePath!,
      branch: spec.branch!,
      baseBranch: spec.baseBranch,
      model: conv?.model ?? 'inherit',
      provider: conv?.provider ?? 'claude',
      specId: spec.id,
      steps: 'R1',
      title: '${spec.code} · ${spec.title}',
      status: SessionStatus.completed,
    );
    return id;
  }
}

final vibeServiceProvider = Provider((ref) => VibeService(ref));

/// The spec (VIBE) a conversation works on, live.
final vibeSpecProvider = StreamProvider.family<Spec?, int>(
  (ref, specId) => ref.watch(specsRepoProvider).watchById(specId),
);
