import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';

/// `há 2 min`, `há 3 h`, `ontem`.
String noteAge(DateTime at, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays == 1) return 'ontem';
  return 'há ${d.inDays} dias';
}

String _hour(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// The newest progress note of the agent on the card of the Quadro, below
/// the step (SPEC-052 R7). Nothing when the spec has none.
class SpecNoteLine extends ConsumerWidget {
  const SpecNoteLine({super.key, required this.spec});

  final Spec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref
        .watch(latestSpecNotesProvider(spec.workspaceId))
        .value?[spec.id];
    if (note == null) return const SizedBox.shrink();
    return Container(
      key: ValueKey('board-note-${spec.code}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.edit_outlined, size: 12, color: AppColors.lilac),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${note.note} · ${noteAge(note.createdAt)}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Andamento": every note of the spec, newest first, with the hour and
/// the session's steps (SPEC-052 R7).
class SpecNotesHistory extends ConsumerWidget {
  const SpecNotesHistory({super.key, required this.spec});

  final Spec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(specNotesProvider(spec.id)).value ?? const [];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('spec-notes-history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const Text(
          'Andamento',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: notes.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) {
              final n = notes[i];
              return Padding(
                key: ValueKey('spec-note-${n.id}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              spec.code,
                              if (n.steps?.isNotEmpty ?? false)
                                n.steps!.replaceAll(',', ', '),
                            ].join(' · '),
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          _hour(n.createdAt),
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(n.note, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'As notas vêm de anotar_andamento. Elas não concluem a etapa: isso '
          'continua com o marcador e o gate.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
