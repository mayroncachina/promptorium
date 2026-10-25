import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../core/claude/readonly_run.dart';
import '../../../core/fs/dir_watcher.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../spec_file.dart';
import 'prototype_files.dart';
import 'prototype_thumbnails.dart';

/// Built-in tools of a prototype run (R2): reading plus Write/Edit, no Bash.
const prototypeTools = ['Read', 'Glob', 'Grep', 'Write', 'Edit'];

/// Tools refused outright (besides not being in [prototypeTools]).
const prototypeDisallowedTools = [
  'Bash',
  'NotebookEdit',
  'Monitor',
  'EnterWorktree',
];

/// Limit and budget of one prototype run.
const prototypeTimeout = Duration(minutes: 15);
const prototypeBudgetUsd = 3.0;

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Promptorium look (lib/ui/theme/tokens.dart) for the generated HTML.
String prototypeTokens() =>
    'fundo ${_hex(AppColors.background)}, painéis ${_hex(AppColors.panel)}, '
    'controles elevados ${_hex(AppColors.surfaceRaised)}, bordas '
    '${_hex(AppColors.border)}, texto ${_hex(AppColors.text)}, texto '
    'secundário ${_hex(AppColors.textSecondary)}, texto apagado '
    '${_hex(AppColors.textMuted)}, âmbar ${_hex(AppColors.amber)} (ações '
    'primárias e seleção; texto sobre âmbar ${_hex(AppColors.onAmber)}; '
    'fundo âmbar suave ${_hex(AppColors.amberTint)}), verde-água '
    '${_hex(AppColors.teal)} (sucesso, em execução), azul '
    '${_hex(AppColors.blue)} (informação), vermelho ${_hex(AppColors.red)} '
    '(erro), lilás ${_hex(AppColors.lilac)} (ações de IA); fonte '
    '"${AppFonts.sans}" para texto e "${AppFonts.mono}" para código e '
    'caminhos (com fallback sans-serif / monospace), texto de 12–13 px, '
    'títulos de 16 px, cantos de 6 px';

/// Instructions of every prototype run (R2, R7): where to write and how.
String prototypeSystemPrompt(String dir) =>
    '''
Você é o designer de telas do Promptorium. Você cria protótipos de tela como
arquivos HTML autocontidos: um arquivo por tela, CSS dentro de <style>, sem
JavaScript, imagens, fontes ou CDN externos (o arquivo abre offline).

Escreva SOMENTE dentro de `$dir/`, com a ferramenta Write. Não edite nenhum
outro arquivo do repositório: escritas fora dessa pasta são negadas. Nunca
sobrescreva um arquivo que já existe na pasta.

Visual do Promptorium (tema escuro): ${prototypeTokens()}. Janela de
referência: 1440×900; a tela deve caber também em 1100×700. Como referência
visual você pode LER `docs/mockups/Specs.dc.html` (não o altere).

Ao terminar, responda no JSON pedido: cada arquivo criado (só o nome), o
requisito dele e uma descrição curta (até 8 palavras) do que a tela mostra ou
do que mudou na variação; e uma resposta curta ao usuário.''';

final prototypeSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['telas', 'resposta'],
  'properties': {
    'telas': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['arquivo', 'requisito', 'descricao'],
        'properties': {
          'arquivo': {'type': 'string'},
          'requisito': {'type': 'string'},
          'descricao': {'type': 'string'},
        },
      },
    },
    'resposta': {'type': 'string'},
  },
};

/// Options of a prototype run: writing allowed only in [dir] (relative to
/// the workspace, the run's cwd) by the `Edit(<dir>/**)` rule — it covers
/// Write and Edit; everything else asks and is denied (R2).
ClaudeOptions prototypeOptions(String dir) => ClaudeOptions(
  permissionMode: ClaudePermissionMode.defaultMode,
  tools: prototypeTools,
  allowedTools: ['Edit($dir/**)'],
  disallowedTools: prototypeDisallowedTools,
  appendSystemPrompt: prototypeSystemPrompt(dir),
  jsonSchema: jsonEncode(prototypeSchema),
  maxBudgetUsd: prototypeBudgetUsd,
  includePartialMessages: false,
);

/// "Gerar telas da spec" (R2).
String prototypeGeneratePrompt({
  required String code,
  required String dir,
  required String specText,
  required List<MockupScreen> existing,
}) {
  final doc = SpecDocument.parse(specText);
  final b = StringBuffer()
    ..writeln(
      'Gere as telas da spec $code em `$dir/`: um arquivo HTML autocontido '
      'por requisito que tenha interface (pule os requisitos sem tela, como '
      'análise estática ou desempenho), com o nome `R<n>-<slug>.html` (slug '
      'curto, minúsculo, sem acentos, com hífens; ex.: '
      '`R1-lista-de-prompts.html`).',
    )
    ..writeln()
    ..writeln('Requisitos:');
  for (final r in doc.requirements) {
    b.writeln('- ${r.id} · ${r.text}');
  }
  if (existing.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Já existem (não sobrescreva e pule esses requisitos): '
        '${existing.map((s) => s.file).join(', ')}.',
      );
  }
  b
    ..writeln()
    ..writeln('Spec:')
    ..writeln('<spec>')
    ..writeln(specText.trimRight())
    ..writeln('</spec>');
  return b.toString().trimRight();
}

/// A new variation of [base] in [target] (R7).
typedef VariationTarget = ({MockupScreen base, String target});

/// "Enviar" of "Pedir ao Claude" (R7).
String prototypeVariationPrompt({
  required String code,
  required String dir,
  required String specText,
  required String request,
  required List<VariationTarget> targets,
}) {
  final b = StringBuffer()
    ..writeln('Pedido do usuário para as telas selecionadas da spec $code:')
    ..writeln('<pedido>')
    ..writeln(request.trim())
    ..writeln('</pedido>')
    ..writeln()
    ..writeln(
      'Crie uma nova variação de cada tela abaixo: leia a tela base, aplique '
      'o pedido e grave exatamente no arquivo novo indicado. Não altere os '
      'arquivos existentes.',
    );
  for (final t in targets) {
    b.writeln(
      '- ${t.base.requirement}: base `$dir/${t.base.file}` → novo '
      '`$dir/${t.target}`',
    );
  }
  b
    ..writeln()
    ..writeln('Spec:')
    ..writeln('<spec>')
    ..writeln(specText.trimRight())
    ..writeln('</spec>');
  return b.toString().trimRight();
}

/// Runs the agent once and returns its structured answer. Injected so tests
/// fake the CLI.
typedef PrototypeAgent = Future<Object?> Function({
  required String cwd,
  required ClaudeOptions options,
  required String prompt,
});

final prototypeAgentProvider = Provider<PrototypeAgent>(
  (ref) =>
      ({required cwd, required options, required prompt}) async =>
          structuredOutput(
            await runReadOnlyClaude(
              ref,
              cwd: cwd,
              options: options,
              prompt: prompt,
              timeout: prototypeTimeout,
              // Write rules are Claude's (other providers run read-only).
              providerId: 'claude',
              denyMessage:
                  'O protótipo só pode gravar arquivos novos na pasta de '
                  'mockups da spec.',
            ),
          ),
);

/// A run in progress for a spec (R3: its screens show as being generated).
@immutable
class PrototypeJob {
  const PrototypeJob({required this.requirements, this.targets = const []});

  /// Requirements being generated (empty = the whole spec).
  final List<String> requirements;

  /// Variation files being created (R7).
  final List<String> targets;

  bool get isVariation => targets.isNotEmpty;
}

class PrototypeJobs extends Notifier<Map<int, PrototypeJob>> {
  @override
  Map<int, PrototypeJob> build() => const {};

  void start(int specId, PrototypeJob job) => state = {...state, specId: job};

  void finish(int specId) => state = {...state}..remove(specId);
}

final prototypeJobsProvider =
    NotifierProvider<PrototypeJobs, Map<int, PrototypeJob>>(PrototypeJobs.new);

/// What one run produced.
@immutable
class PrototypeOutcome {
  const PrototypeOutcome({
    required this.created,
    this.restored = const [],
    this.answer,
  });

  final List<String> created;

  /// Existing screens the agent changed and the app put back.
  final List<String> restored;
  final String? answer;
}

class PrototypeException implements Exception {
  const PrototypeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// "Gerar telas da spec" and "Pedir ao Claude" (R2, R7).
class PrototypeService {
  PrototypeService(this._ref);

  final Ref _ref;

  Future<PrototypeOutcome> generate(
    Workspace ws,
    Spec spec,
    String specText,
  ) async {
    final dir = mockupDir(spec.code);
    final existing = await listScreens('${ws.path}/$dir');
    return _run(
      ws,
      spec,
      job: const PrototypeJob(requirements: []),
      request: 'Gerar telas da spec',
      requirements: const [],
      prompt: prototypeGeneratePrompt(
        code: spec.code,
        dir: dir,
        specText: specText,
        existing: existing,
      ),
    );
  }

  /// One new variation of each of [selected] (one per requirement).
  Future<PrototypeOutcome> vary(
    Workspace ws,
    Spec spec,
    String specText, {
    required List<MockupScreen> selected,
    required String request,
  }) async {
    if (request.trim().isEmpty) {
      throw const PrototypeException('Escreva o pedido.');
    }
    final dir = mockupDir(spec.code);
    final all = await listScreens('${ws.path}/$dir');
    final seen = <String>{};
    final targets = <VariationTarget>[
      for (final s in selected)
        if (seen.add(s.requirement))
          (base: s, target: nextVariationName(all, s.requirement)),
    ];
    if (targets.isEmpty) {
      throw const PrototypeException('Selecione uma tela.');
    }
    return _run(
      ws,
      spec,
      job: PrototypeJob(
        requirements: [for (final t in targets) t.base.requirement],
        targets: [for (final t in targets) t.target],
      ),
      request: request.trim(),
      requirements: [for (final t in targets) t.base.requirement],
      prompt: prototypeVariationPrompt(
        code: spec.code,
        dir: dir,
        specText: specText,
        request: request,
        targets: targets,
      ),
    );
  }

  Future<PrototypeOutcome> _run(
    Workspace ws,
    Spec spec, {
    required PrototypeJob job,
    required String request,
    required List<String> requirements,
    required String prompt,
  }) async {
    final jobs = _ref.read(prototypeJobsProvider.notifier);
    if (_ref.read(prototypeJobsProvider).containsKey(spec.id)) {
      throw const PrototypeException('Já há um pedido em andamento.');
    }
    final rel = mockupDir(spec.code);
    final dir = '${ws.path}/$rel';
    await Directory(dir).create(recursive: true);
    // The agent may only add files: what exists is put back afterwards.
    final before = <String, List<int>>{
      for (final s in await listScreens(dir))
        s.file: await File('$dir/${s.file}').readAsBytes(),
    };
    jobs.start(spec.id, job);
    final at = DateTime.now();
    try {
      Object? data;
      try {
        data = await _ref.read(prototypeAgentProvider)(
          cwd: ws.path,
          options: prototypeOptions(rel),
          prompt: prompt,
        );
      } catch (e) {
        await _record(
          dir,
          PrototypeRequest(
            request: request,
            at: at,
            requirements: requirements,
            answer: '$e',
            failed: true,
          ),
          const {},
        );
        rethrow;
      }
      final restored = <String>[];
      for (final MapEntry(:key, :value) in before.entries) {
        final f = File('$dir/$key');
        if (!await f.exists() || !listEquals(await f.readAsBytes(), value)) {
          await f.writeAsBytes(value, flush: true);
          restored.add(key);
        }
      }
      final now = await listScreens(dir);
      final created = [
        for (final s in now)
          if (!before.containsKey(s.file)) s.file,
      ];
      final described = <String, String>{};
      String? answer;
      if (data is Map) {
        answer = '${data['resposta'] ?? ''}'.trim();
        for (final t in data['telas'] as List? ?? const []) {
          if (t is! Map) continue;
          final name = '${t['arquivo'] ?? ''}'.split('/').last.trim();
          final d = '${t['descricao'] ?? ''}'.trim();
          if (name.isNotEmpty && d.isNotEmpty) described[name] = d;
        }
      }
      await _record(
        dir,
        PrototypeRequest(
          request: request,
          at: at,
          requirements: requirements,
          answer: answer == null || answer.isEmpty ? null : answer,
          files: created,
        ),
        {
          for (final f in created)
            f: ScreenMeta(description: described[f], createdAt: DateTime.now()),
        },
      );
      _reload(ws, spec);
      return PrototypeOutcome(
        created: created,
        restored: restored,
        answer: answer,
      );
    } finally {
      jobs.finish(spec.id);
    }
  }

  Future<void> _record(
    String dir,
    PrototypeRequest request,
    Map<String, ScreenMeta> screens,
  ) async {
    final index = await PrototypeIndex.read(dir);
    await index
        .copyWith(
          screens: {...index.screens, ...screens},
          history: [...index.history, request],
        )
        .write(dir);
  }

  void _reload(Workspace ws, Spec spec) {
    final key = (root: ws.path, code: spec.code);
    if (_ref.exists(prototypeScreensProvider(key))) {
      unawaited(_ref.read(prototypeScreensProvider(key).notifier).reload());
    }
  }

  /// "Remover" of "Versões" (R11): the file and its `index.json` entry.
  Future<void> remove(Workspace ws, Spec spec, MockupScreen screen) async {
    final dir = '${ws.path}/${mockupDir(spec.code)}';
    final f = File('$dir/${screen.file}');
    if (await f.exists()) await f.delete();
    final index = await PrototypeIndex.read(dir);
    if (index.screens.containsKey(screen.file)) {
      await index
          .copyWith(screens: {...index.screens}..remove(screen.file))
          .write(dir);
    }
    _reload(ws, spec);
  }
}

final prototypeServiceProvider = Provider(PrototypeService.new);

/// Key of a spec's prototype folder.
typedef PrototypeKey = ({String root, String code});

/// What the canvas shows (R3, R4, R5).
@immutable
class PrototypeState {
  const PrototypeState({
    this.screens = const [],
    this.index = const PrototypeIndex(),
    this.thumbs = const {},
    this.browserMissing = false,
    this.loaded = false,
  });

  final List<MockupScreen> screens;
  final PrototypeIndex index;

  /// File → cached PNG (1440×900).
  final Map<String, String> thumbs;
  final bool browserMissing;
  final bool loaded;

  PrototypeState copyWith({
    List<MockupScreen>? screens,
    PrototypeIndex? index,
    Map<String, String>? thumbs,
    bool? browserMissing,
    bool? loaded,
  }) => PrototypeState(
    screens: screens ?? this.screens,
    index: index ?? this.index,
    thumbs: thumbs ?? this.thumbs,
    browserMissing: browserMissing ?? this.browserMissing,
    loaded: loaded ?? this.loaded,
  );

  List<MockupScreen> variationsOf(String requirement) => [
    for (final s in screens)
      if (s.requirement == requirement) s,
  ];
}

/// Whether the folder is watched (off in widget tests: no real FS events
/// under FakeAsync).
final prototypeWatchProvider = Provider<bool>((ref) => true);

/// Screens of `docs/mockups/<code>/`, their `index.json` and thumbnails,
/// kept up to date by a [DirWatcher] while the Protótipo mode is open.
class PrototypeScreens extends Notifier<PrototypeState> {
  PrototypeScreens(this.key);

  final PrototypeKey key;

  DirWatcher? _watcher;
  bool _thumbing = false;
  bool _again = false;

  String get dir => '${key.root}/${mockupDir(key.code)}';

  List<String> get _dirs => [
    dir,
    '${key.root}/docs/mockups',
    '${key.root}/docs',
  ];

  @override
  PrototypeState build() {
    if (ref.read(prototypeWatchProvider)) {
      _watcher = DirWatcher(_dirs, onChange: _changed);
    }
    ref.onDispose(() => _watcher?.close());
    unawaited(Future.microtask(reload));
    return const PrototypeState();
  }

  void _changed(Set<String> paths) {
    _watcher?.update(_dirs);
    if (paths.any((p) => p.startsWith(dir))) unawaited(reload());
  }

  /// Lists the folder again and generates the missing thumbnails (R4).
  Future<void> reload() async {
    final screens = await listScreens(dir);
    final index = await PrototypeIndex.read(dir);
    if (!ref.mounted) return;
    final thumbs = ref.read(prototypeThumbnailsProvider);
    final known = <String, String>{};
    for (final s in screens) {
      final png = await thumbs.cached('$dir/${s.file}');
      if (png != null) known[s.file] = png;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      screens: screens,
      index: index,
      thumbs: known,
      loaded: true,
    );
    await _thumbnails();
  }

  Future<void> _thumbnails() async {
    if (_thumbing) {
      _again = true;
      return;
    }
    _thumbing = true;
    try {
      do {
        _again = false;
        final thumbs = ref.read(prototypeThumbnailsProvider);
        for (final s in state.screens) {
          if (!ref.mounted) return;
          if (state.thumbs.containsKey(s.file)) continue;
          if (await thumbs.findBrowser() == null) {
            if (ref.mounted) state = state.copyWith(browserMissing: true);
            return;
          }
          final png = await thumbs.thumbnail('$dir/${s.file}');
          if (!ref.mounted) return;
          if (png != null) {
            state = state.copyWith(thumbs: {...state.thumbs, s.file: png});
          }
        }
      } while (_again && ref.mounted);
    } finally {
      _thumbing = false;
    }
  }
}

final prototypeScreensProvider = NotifierProvider.autoDispose
    .family<PrototypeScreens, PrototypeState, PrototypeKey>(
      PrototypeScreens.new,
    );
