import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/widgets/session_style.dart';
import 'spec_service.dart';

/// "Nova spec" (title bar of the Specs screen): asks the title, writes
/// `specs/SPEC-NNN-<slug>.md` from the template and selects it.
Future<Spec?> showNewSpecDialog(BuildContext context) => showDialog<Spec>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const NewSpecDialog(),
);

class NewSpecDialog extends ConsumerStatefulWidget {
  const NewSpecDialog({super.key});

  @override
  ConsumerState<NewSpecDialog> createState() => _NewSpecDialogState();
}

class _NewSpecDialogState extends ConsumerState<NewSpecDialog> {
  final _title = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ws = ref.read(activeWorkspaceProvider);
    if (ws == null) {
      setState(() => _error = 'Selecione um workspace na barra de título.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final spec = await ref
          .read(specServiceProvider)
          .create(ws, title: _title.text);
      ref.read(selectedSpecProvider.notifier).select(spec.id);
      if (mounted) Navigator.of(context).pop(spec);
    } on SpecException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        key: const ValueKey('new-spec-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nova spec',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cria specs/SPEC-NNN-<titulo>.md com status rascunho.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('new-spec-title'),
                  controller: _title,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ex.: Kanban de tarefas',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      label: 'Cancelar',
                      onTap: _busy ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AmberButton(
                      key: const ValueKey('new-spec-submit'),
                      label: _busy ? 'Criando…' : 'Criar spec',
                      onTap: _busy ? null : _submit,
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
