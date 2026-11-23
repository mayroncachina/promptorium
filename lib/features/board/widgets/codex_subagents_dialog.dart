import 'package:flutter/material.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../spec_run_provider.dart' show codexSubagentsNotice;

/// Choice of [CodexSubagentsDialog] (SPEC-106 R9).
enum CodexSubagentsChoice {
  /// "Executar sem os subagentes": the Codex, the main session does it all.
  withoutSubagents,

  /// "Executar com o Claude Code": this run only.
  claude,
}

/// Before a spec with subagents starts on the Codex (R9, mock 3): run
/// without them or with the Claude Code. The choice holds for this run
/// only, and the provider never changes in the middle (decision 4).
class CodexSubagentsDialog extends StatelessWidget {
  const CodexSubagentsDialog({
    super.key,
    required this.spec,
    required this.subagents,
    this.agentLabel,
  });

  final Spec spec;
  final List<String> subagents;

  /// "flutter-dev · adaptado" (null = no agent).
  final String? agentLabel;

  @override
  Widget build(BuildContext context) {
    Widget fact(String k, Widget v) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: v),
        ],
      ),
    );
    return Dialog(
      key: const ValueKey('codex-subagents-dialog'),
      backgroundColor: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lilac,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'EXECUTAR SPEC',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.onAmber,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${spec.code} · ${spec.title}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Subagentes não rodam no Codex',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SessionColors.approvalBg,
                  border: Border.all(color: SessionColors.approvalBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  codexSubagentsNotice(subagents),
                  key: const ValueKey('codex-subagents-notice'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.amberLight,
                  ),
                ),
              ),
              if (agentLabel != null)
                fact(
                  'Agente da spec',
                  Text(
                    agentLabel!,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: AppColors.text,
                    ),
                  ),
                ),
              fact(
                'Provedor',
                const Text(
                  'Codex · fixo até o fim desta execução',
                  style: TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  SmallButton(
                    key: const ValueKey('codex-subagents-claude'),
                    label: 'Executar com o Claude Code',
                    height: 34,
                    onTap: () =>
                        Navigator.of(context).pop(CodexSubagentsChoice.claude),
                  ),
                  AmberButton(
                    key: const ValueKey('codex-subagents-without'),
                    label: 'Executar sem os subagentes',
                    height: 34,
                    onTap: () =>
                        Navigator.of(context)
                            .pop(CodexSubagentsChoice.withoutSubagents),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
