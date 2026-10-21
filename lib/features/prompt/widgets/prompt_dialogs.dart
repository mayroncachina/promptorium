import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../core/providers/agent_provider.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/widgets/session_style.dart';
import '../prompt_actions.dart';

InputDecoration _deco(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
  isDense: true,
  filled: true,
  fillColor: AppColors.background,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AppColors.border),
  ),
);

Widget _label(String t) => Padding(
  padding: const EdgeInsets.only(top: 12, bottom: 6),
  child: Text(
    t,
    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
  ),
);

/// Dialog frame shared by the Prompt dialogs.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.dialogKey,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.error,
    required this.busy,
    required this.submitLabel,
    required this.submitKey,
    required this.onSubmit,
  });

  final Key dialogKey;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final String? error;
  final bool busy;
  final String submitLabel;
  final Key submitKey;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        key: dialogKey,
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                ...children,
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      label: 'Cancelar',
                      onTap: busy ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AmberButton(
                      key: submitKey,
                      label: submitLabel,
                      onTap: busy ? null : onSubmit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Salvar como prompt / Novo ---------------------------------------------------

Future<SavedPrompt?> showSavePromptDialog(
  BuildContext context, {
  String body = '',
}) => showDialog<SavedPrompt>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => SavePromptDialog(body: body),
);

class SavePromptDialog extends ConsumerStatefulWidget {
  const SavePromptDialog({super.key, this.body = ''});

  final String body;

  @override
  ConsumerState<SavePromptDialog> createState() => _SavePromptDialogState();
}

class _SavePromptDialogState extends ConsumerState<SavePromptDialog> {
  final _command = TextEditingController();
  final _description = TextEditingController();
  late final _body = TextEditingController(text: widget.body);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _command.dispose();
    _description.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = validateCommand(_command.text);
    if (err != null) return setState(() => _error = err);
    if (_body.text.trim().isEmpty) {
      return setState(() => _error = 'O corpo não pode ficar vazio.');
    }
    final cmd = _command.text.trim().replaceFirst(RegExp(r'^/'), '');
    final repo = ref.read(savedPromptsRepoProvider);
    setState(() => _busy = true);
    try {
      if (await repo.getByCommand(cmd) != null) {
        setState(() {
          _busy = false;
          _error = 'Já existe um prompt /$cmd.';
        });
        return;
      }
      final p = await repo.upsert(
        command: cmd,
        body: _body.text.trim(),
        description: _description.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(p);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Frame(
      dialogKey: const ValueKey('save-prompt-dialog'),
      title: 'Salvar como prompt',
      subtitle: 'Fica disponível com /comando no composer e na lista lateral.',
      error: _error,
      busy: _busy,
      submitLabel: _busy ? 'Salvando…' : 'Salvar',
      submitKey: const ValueKey('save-prompt-submit'),
      onSubmit: _save,
      children: [
        _label('Comando'),
        TextField(
          key: const ValueKey('save-prompt-command'),
          controller: _command,
          autofocus: true,
          style: const TextStyle(fontSize: 13, fontFamily: AppFonts.mono),
          decoration: _deco('revisar-testes'),
        ),
        _label('Descrição'),
        TextField(
          key: const ValueKey('save-prompt-description'),
          controller: _description,
          style: const TextStyle(fontSize: 13),
          decoration: _deco('O que este prompt faz'),
        ),
        _label('Corpo'),
        TextField(
          key: const ValueKey('save-prompt-body'),
          controller: _body,
          minLines: 5,
          maxLines: 12,
          style: const TextStyle(fontSize: 13),
          decoration: _deco('Texto inserido ao usar o comando'),
        ),
      ],
    );
  }
}

// --- Continuar como sessão ---------------------------------------------------------

/// Permission mode of the session created from a conversation in [mode].
ClaudePermissionMode sessionModeFor(PromptMode mode) => switch (mode) {
  PromptMode.ask => ClaudePermissionMode.defaultMode,
  PromptMode.plan => ClaudePermissionMode.plan,
  PromptMode.edit => ClaudePermissionMode.acceptEdits,
  PromptMode.refine => ClaudePermissionMode.defaultMode,
};

const continueSessionPrompt =
    'Esta sessão continua a conversa que tivemos no Prompt, agora num '
    'worktree isolado. Resuma em poucas linhas o que foi decidido e o '
    'próximo passo, e aguarde minhas instruções antes de alterar arquivos.';

/// Creates the session (new worktree, `--resume <conversa> --fork-session`)
/// and goes to Sessões. Returns the new session id.
Future<String?> showContinueSessionDialog(
  BuildContext context,
  Conversation conversation,
) => showDialog<String>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => ContinueSessionDialog(conversation: conversation),
);

class ContinueSessionDialog extends ConsumerStatefulWidget {
  const ContinueSessionDialog({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ContinueSessionDialog> createState() =>
      _ContinueSessionDialogState();
}

class _ContinueSessionDialogState extends ConsumerState<ContinueSessionDialog> {
  late final _title = TextEditingController(text: widget.conversation.title);
  final _prompt = TextEditingController(text: continueSessionPrompt);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = widget.conversation;
    final sid = c.claudeSessionId;
    if (sid == null) {
      return setState(
        () => _error = 'A conversa ainda não tem uma sessão do Claude.',
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ws = await ref.read(workspacesRepoProvider).getById(c.workspaceId);
      if (ws == null) throw const SessionException('Workspace não encontrado.');
      final id = await ref
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              provider: c.provider,
              title: _title.text,
              prompt: _prompt.text,
              model: c.model,
              permissionMode: sessionModeFor(PromptMode.fromName(c.mode)),
              resumeFrom: sid,
              origin:
                  'Continuação da conversa "${c.title}" do Prompt '
                  '(--resume ${sid.substring(0, 8)}… --fork-session)',
            ),
          );
      await ref.read(conversationsRepoProvider).linkSession(c.id, id);
      ref.read(selectedSessionProvider.notifier).select(id);
      ref.read(navigationProvider.notifier).go(AppSection.sessions);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Frame(
      dialogKey: const ValueKey('continue-session-dialog'),
      title: 'Continuar como sessão',
      subtitle:
          'Cria uma sessão num worktree novo (branch pr/<slug>) levando o '
          'histórico desta conversa como contexto (--resume --fork-session). '
          'A conversa continua disponível aqui.',
      error: _error,
      busy: _busy,
      submitLabel: _busy ? 'Criando…' : 'Criar sessão',
      submitKey: const ValueKey('continue-session-submit'),
      onSubmit: _submit,
      children: [
        _label('Título da sessão'),
        TextField(
          key: const ValueKey('continue-session-title'),
          controller: _title,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: _deco('Título'),
        ),
        _label('Primeira mensagem'),
        TextField(
          key: const ValueKey('continue-session-prompt'),
          controller: _prompt,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontSize: 13),
          decoration: _deco('O que a sessão deve fazer?'),
        ),
      ],
    );
  }
}
