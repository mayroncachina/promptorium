import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../data/repos/snippets_repo.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../sessions/widgets/session_style.dart';
import '../snippet_naming.dart';
import '../snippet_scope.dart';
import 'snippet_preview.dart';
import 'snippets_dialog.dart';

/// Anchored, nonmodal save form: the answer stays visible behind it.
class SaveSnippetButton extends ConsumerStatefulWidget {
  const SaveSnippetButton({
    super.key,
    required this.origin,
    required this.code,
    this.language,
  });

  final SnippetOrigin origin;
  final String code;
  final String? language;

  @override
  ConsumerState<SaveSnippetButton> createState() => _SaveSnippetButtonState();
}

class _SaveSnippetButtonState extends ConsumerState<SaveSnippetButton> {
  final _menu = MenuController();
  final _focus = FocusNode(debugLabel: 'save snippet');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openSaved() async {
    final origin = widget.origin;
    final s = await ref
        .read(snippetsRepoProvider)
        .byBody(origin.workspaceId, widget.code);
    if (!mounted || s == null) return;
    final ws = await ref
        .read(workspacesRepoProvider)
        .getById(origin.workspaceId);
    if (!mounted || ws == null) return;
    // Use the origin workspace even if another workspace became active.
    await showAppDialog<void>(
      context: context,
      builder: (_) => SnippetsDialog(workspace: ws, initialId: s.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved =
        ref
            .watch(snippetHashesProvider(widget.origin.workspaceId))
            .value
            ?.contains(snippetHash(widget.code)) ??
        false;
    final color = saved ? AppColors.teal : AppColors.textSecondary;
    return MenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      consumeOutsideTap: true,
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.panelSolid),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        SaveSnippetForm(
          key: ValueKey((widget.code, widget.origin.label)),
          origin: widget.origin,
          code: widget.code,
          language: widget.language,
          onClose: _menu.close,
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: saved
            ? 'Abrir snippet salvo'
            : 'Salvar como snippet do projeto',
        child: Semantics(
          button: true,
          label: saved
              ? 'Abrir snippet salvo'
              : 'Salvar código ${widget.language?.toUpperCase() ?? 'texto'} como snippet',
          child: TextButton.icon(
            key: const ValueKey('code-save-snippet'),
            focusNode: _focus,
            onPressed: saved
                ? _openSaved
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
            style: TextButton.styleFrom(
              foregroundColor: color,
              backgroundColor: saved
                  ? AppColors.teal.withValues(alpha: .10)
                  : null,
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            icon: Icon(saved ? Icons.check : Icons.bookmark_border, size: 13),
            label: Text(saved ? 'Salvo' : 'Salvar'),
          ),
        ),
      ),
    );
  }
}

class SaveSnippetForm extends ConsumerStatefulWidget {
  const SaveSnippetForm({
    super.key,
    required this.origin,
    required this.code,
    this.language,
    required this.onClose,
  });

  final SnippetOrigin origin;
  final String code;
  final String? language;
  final VoidCallback onClose;

  @override
  ConsumerState<SaveSnippetForm> createState() => _SaveSnippetFormState();
}

class _SaveSnippetFormState extends ConsumerState<SaveSnippetForm> {
  late final _name = TextEditingController(
    text: suggestSnippetName(widget.code, widget.language, widget.origin.label),
  );
  final _description = TextEditingController();
  final _nameFocus = FocusNode();
  late String? _language = widget.language;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save(bool replace) async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(
        () => _error = name.isEmpty
            ? 'Informe um nome.'
            : 'Use até 80 caracteres.',
      );
      _nameFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(snippetsRepoProvider)
          .save(
            workspaceId: widget.origin.workspaceId,
            name: name,
            language: _language,
            description: _description.text,
            body: widget.code,
            originConversationId: widget.origin.conversationId,
            originSessionId: widget.origin.sessionId,
            originLabel: widget.origin.label,
            replace: replace,
          );
      if (!mounted) return;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Snippet salvo',
          Directionality.of(context),
        ),
      );
      widget.onClose();
    } on SnippetNameTaken {
      if (mounted) {
        setState(() => _error = 'Já existe um snippet com esse nome.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível salvar o snippet. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all =
        ref.watch(snippetsProvider(widget.origin.workspaceId)).value ??
        const <Snippet>[];
    final duplicate = all.any((s) => s.nameKey == snippetNameKey(_name.text));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => _save(duplicate),
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: SizedBox(
        width: 400,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height - 48,
          ),
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.all(16),
            child: Column(
              key: const ValueKey('save-snippet-form'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 16,
                      color: AppColors.amber,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Salvar snippet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('snippet-save-name'),
                  controller: _name,
                  focusNode: _nameFocus,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: 'Nome',
                    counterText: '',
                    errorText:
                        _error ??
                        (duplicate
                            ? 'Já existe um snippet com esse nome.'
                            : null),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<String>(
                        initialValue: _language ?? 'texto',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Linguagem',
                        ),
                        items: [
                          for (final word in snippetLanguageOptions(_language))
                            DropdownMenuItem(value: word, child: Text(word)),
                        ],
                        onChanged: (v) => setState(
                          () => _language = snippetLanguageOf(v ?? 'texto'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _description,
                        decoration: const InputDecoration(
                          labelText: 'Descrição (opcional)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SnippetCodePreview(
                  code: widget.code,
                  language: _language,
                  maxLines: 12,
                ),
                const SizedBox(height: 10),
                Text(
                  'da ${widget.origin.conversationId != null ? 'conversa' : 'sessão'} ${widget.origin.label}${widget.origin.at == null ? '' : ' · ${formatClock(widget.origin.at)}'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('snippet-save-confirm'),
                      onPressed: _saving ? null : () => _save(duplicate),
                      child: Text(duplicate ? 'Substituir' : 'Salvar'),
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
