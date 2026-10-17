import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_root.dart'
    show InvalidWorkspaceFolder, expandHome;
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../sessions/widgets/session_style.dart';
import '../new_project_dialog.dart' show defaultProjectParent, tildePath;
import '../project_service.dart';
import '../project_templates.dart';

/// "Começar" (UX v2, U7; docs/mockups/v2/NovoProjeto.dc.html): the three
/// ways a workspace comes in (an existing folder, a new project, a clone),
/// in one screen instead of dialogs. Planning is optional.
///
/// Shown by the Projeto screen when there is no workspace, or on demand
/// ("Novo projeto" of the title bar / workspace picker; [startScreenProvider]).
class StartScreenController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) => state = on;
}

final startScreenProvider = NotifierProvider<StartScreenController, bool>(
  StartScreenController.new,
);

enum _Origin { open, create, clone }

class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key, this.canClose = false});

  /// Whether a workspace exists (shows "Voltar").
  final bool canClose;

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  _Origin _origin = _Origin.create;
  final _name = TextEditingController();
  final _parent = TextEditingController(
    text: tildePath(defaultProjectParent()),
  );
  final _remote = TextEditingController();
  final _open = TextEditingController();
  final _cloneUrl = TextEditingController();
  final _cloneInto = TextEditingController(
    text: tildePath(defaultProjectParent()),
  );
  String _template = 'empty';
  bool _withRemote = false;
  bool _busy = false;
  String? _error;

  /// Loaded once (a stream subscription here would outlive the screen in
  /// tests; the list only feeds "Recentes").
  List<Workspace> _recent = const [];

  @override
  void initState() {
    super.initState();
    ref.read(workspacesRepoProvider).getAll().then((list) {
      if (mounted) setState(() => _recent = list);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _parent, _remote, _open, _cloneUrl, _cloneInto]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _target => [
    _parent.text.trim().replaceAll(RegExp(r'/+$'), ''),
    _name.text.trim(),
  ].where((p) => p.isNotEmpty).join('/');

  Future<void> _browse(TextEditingController into) async {
    final start = expandHome(into.text.trim());
    final picked = await ref.read(directoryPickerProvider)(
      initialDirectory: Directory(start).existsSync()
          ? start
          : Platform.environment['HOME'],
    );
    if (picked != null && mounted) {
      setState(() => into.text = tildePath(picked));
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
      if (mounted) ref.read(startScreenProvider.notifier).set(false);
    } on InvalidWorkspaceFolder catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create({required bool plan}) => _run(() async {
    if (_withRemote && _remote.text.trim().isEmpty) {
      throw const ProjectException('Informe a URL do repositório remoto.');
    }
    await ref
        .read(projectServiceProvider)
        .createProject(
          parent: _parent.text,
          name: _name.text,
          remoteUrl: _withRemote ? _remote.text : null,
          template: templateById(_template),
          plan: plan,
        );
    ref.read(navigationProvider.notifier).go(AppSection.project);
  });

  Future<void> _openFolder() => _run(() async {
    final p = expandHome(_open.text.trim());
    if (p.isEmpty) throw const ProjectException('Informe a pasta.');
    await ref.read(workspaceActionsProvider).addFolder(p);
    ref.read(navigationProvider.notifier).go(AppSection.project);
  });

  Future<void> _clone() => _run(() async {
    final url = _cloneUrl.text.trim();
    if (url.isEmpty) throw const ProjectException('Informe a URL.');
    final into = expandHome(_cloneInto.text.trim());
    await ref.read(workspaceActionsProvider).cloneInto(into, url);
    ref.read(navigationProvider.notifier).go(AppSection.project);
  });

  @override
  Widget build(BuildContext context) {
    final workspaces = _recent;
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        key: const ValueKey('start-screen'),
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Começar',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.canClose)
                        SmallButton(
                          key: const ValueKey('start-back'),
                          label: 'Voltar',
                          onTap: () =>
                              ref.read(startScreenProvider.notifier).set(false),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Escolha de onde vem o código. Planejar com o planner é '
                    'opcional e pode ser feito depois, na tela Projeto.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _card(
                          _Origin.open,
                          AppIcons.folder,
                          AppColors.blue,
                          'Abrir pasta existente',
                          'Repositório que já tem código. Depois, "Analisar '
                              'repositório" na aba Saúde detecta a stack e os '
                              'comandos.',
                        ),
                        const SizedBox(width: 12),
                        _card(
                          _Origin.create,
                          AppIcons.plus,
                          AppColors.amber,
                          'Criar projeto novo',
                          'Pasta nova com git init. Depois, uma ideia num '
                              'parágrafo e o planner propõe visão, stack e '
                              'roadmap de uma vez.',
                        ),
                        const SizedBox(width: 12),
                        _card(
                          _Origin.clone,
                          AppIcons.code,
                          AppColors.lilac,
                          'Clonar de uma URL',
                          'git clone para uma pasta local e segue como pasta '
                              'existente.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: switch (_origin) {
                            _Origin.open => _openForm(),
                            _Origin.create => _createForm(),
                            _Origin.clone => _cloneForm(),
                          },
                        ),
                        const SizedBox(width: 22),
                        SizedBox(width: 280, child: _side(workspaces)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    _Origin o,
    AppIconData icon,
    Color color,
    String title,
    String text,
  ) {
    final on = _origin == o;
    return Expanded(
      child: Material(
        key: ValueKey('start-origin-${o.name}'),
        color: on ? const Color(0xFF1A1710) : AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: on ? AppColors.amber : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _origin = o;
            _error = null;
          }),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    color: AppColors.text,
  );

  InputDecoration _field({String? hint}) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textMuted),
    border: const OutlineInputBorder(),
  );

  Widget _pathRow(
    TextEditingController c,
    String key, {
    String? hint,
    bool browse = true,
  }) => Row(
    children: [
      Expanded(
        child: TextField(
          key: ValueKey(key),
          controller: c,
          enabled: !_busy,
          style: _mono,
          decoration: _field(hint: hint),
          onChanged: (_) => setState(() {}),
        ),
      ),
      if (browse) ...[
        const SizedBox(width: 8),
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            key: ValueKey('$key-browse'),
            onPressed: _busy ? null : () => _browse(c),
            icon: AppIcon(AppIcons.folder, size: 14),
            label: const Text('Procurar…'),
          ),
        ),
      ],
    ],
  );

  Widget _errorLine() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _error!,
            key: const ValueKey('start-error'),
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        );

  Widget _createForm() {
    final t = templateById(_template);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nome da pasta', style: _label),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('start-name'),
                    controller: _name,
                    enabled: !_busy,
                    style: _mono,
                    decoration: _field(hint: 'meu-projeto'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Criar dentro de', style: _label),
                  const SizedBox(height: 6),
                  _pathRow(_parent, 'start-parent'),
                ],
              ),
            ),
          ],
        ),
        if (_name.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Será criada: $_target · branch main · commit inicial',
            key: const ValueKey('start-target'),
            style: _mono.copyWith(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 14),
        const Text('Ponto de partida', style: _label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tp in projectTemplates)
              Material(
                key: ValueKey('start-template-${tp.id}'),
                color: tp.id == _template
                    ? AppColors.amberTint
                    : Colors.transparent,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: tp.id == _template
                        ? AppColors.amber
                        : AppColors.border,
                  ),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _busy ? null : () => setState(() => _template = tp.id),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: Text(
                      tp.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: tp.id == _template
                            ? AppColors.amber
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          t.isEmpty
              ? '"Vazio" deixa tudo para o planner.'
              : 'O modelo preenche ${t.summary}; o planner só ajusta.',
          key: const ValueKey('start-template-summary'),
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        const Text('Repositório remoto', style: _label),
        RadioGroup<bool>(
          groupValue: _withRemote,
          onChanged: (v) {
            if (!_busy && v != null) setState(() => _withRemote = v);
          },
          child: Row(
            children: [
              const Radio<bool>(value: false),
              const Text(
                'Só local por enquanto',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 16),
              const Radio<bool>(value: true),
              const Text('Conectar a', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('start-remote'),
                  controller: _remote,
                  enabled: !_busy && _withRemote,
                  style: _mono,
                  decoration: _field(hint: 'git@github.com:org/projeto.git'),
                ),
              ),
            ],
          ),
        ),
        _errorLine(),
        const SizedBox(height: 14),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AmberButton(
              key: const ValueKey('start-create-plan'),
              label: _busy ? 'Criando…' : 'Criar e planejar com o planner',
              height: 34,
              onTap: _busy || _name.text.trim().isEmpty
                  ? null
                  : () => _create(plan: true),
            ),
            SmallButton(
              key: const ValueKey('start-create'),
              label: 'Criar sem planejar',
              height: 34,
              onTap: _busy || _name.text.trim().isEmpty
                  ? null
                  : () => _create(plan: false),
            ),
            const Text(
              'Nada é enviado ao planner até você escrever a ideia.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _openForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Pasta do repositório', style: _label),
      const SizedBox(height: 6),
      _pathRow(_open, 'start-open-path', hint: '~/workspace/projeto'),
      const SizedBox(height: 6),
      const Text(
        'Precisa ser um repositório git. Uma pasta sem git pode ser iniciada '
        'em "Adicionar pasta…" do seletor de workspace.',
        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      _errorLine(),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: AmberButton(
          key: const ValueKey('start-open'),
          label: _busy ? 'Abrindo…' : 'Abrir',
          height: 34,
          onTap: _busy || _open.text.trim().isEmpty ? null : _openFolder,
        ),
      ),
    ],
  );

  Widget _cloneForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('URL do repositório', style: _label),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('start-clone-url'),
        controller: _cloneUrl,
        enabled: !_busy,
        style: _mono,
        decoration: _field(hint: 'git@github.com:org/projeto.git'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      const Text('Clonar dentro de', style: _label),
      const SizedBox(height: 6),
      _pathRow(_cloneInto, 'start-clone-into'),
      _errorLine(),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: AmberButton(
          key: const ValueKey('start-clone'),
          label: _busy ? 'Clonando…' : 'Clonar',
          height: 34,
          onTap: _busy || _cloneUrl.text.trim().isEmpty ? null : _clone,
        ),
      ),
    ],
  );

  Widget _side(List<Workspace> workspaces) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('O QUE ACONTECE', style: sectionTitleStyle),
      const SizedBox(height: 8),
      for (final (i, line) in const [
        'Pasta, git init e commit inicial · 1 s',
        'Ideia num parágrafo → o planner propõe visão, stack e roadmap de '
            'uma vez · ~US\$ 0,30 · opcional',
        'Revisar e criar: CLAUDE.md, specs e Quadro',
      ].indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${i + 1}. $line',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      if (workspaces.isNotEmpty) ...[
        const SizedBox(height: 14),
        const Text('RECENTES', style: sectionTitleStyle),
        const SizedBox(height: 8),
        for (final w in workspaces.take(5))
          InkWell(
            key: ValueKey('start-recent-${w.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await ref.read(workspaceActionsProvider).select(w.id);
              ref.read(startScreenProvider.notifier).set(false);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    tildePath(w.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ],
  );
}
