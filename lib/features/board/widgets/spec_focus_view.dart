import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../board_screen.dart';
import 'spec_folder.dart';

/// The Foco view of the Quadro (SPEC-036): the folder of specs on the left and
/// the stage on the rest of the screen.
class SpecFocusView extends StatefulWidget {
  const SpecFocusView({
    super.key,
    required this.cards,
    required this.attention,
  });

  /// Cards that pass the filters of the Quadro.
  final List<SpecCardData> cards;
  final bool Function(SpecCardData) attention;

  @override
  State<SpecFocusView> createState() => SpecFocusViewState();
}

class SpecFocusViewState extends State<SpecFocusView> {
  final _focus = FocusNode(debugLabel: 'spec-focus-view');
  final _folder = GlobalKey<SpecFolderState>();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Focuses the search of the folder (R6).
  void focusSearch() => _folder.currentState?.focusSearch();

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    child: ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpecFolder(
            key: _folder,
            cards: widget.cards,
            attention: widget.attention,
            onOpen: (_) {},
            onSearchDone: _focus.requestFocus,
          ),
          const Expanded(child: _StageHint()),
        ],
      ),
    ),
  );
}

class _StageHint extends StatelessWidget {
  const _StageHint();

  @override
  Widget build(BuildContext context) => const Center(
    key: ValueKey('stage-hint'),
    child: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Escolha uma spec na pasta',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Passe o mouse para ver os detalhes. Clique para abrir, com as '
            'specs que dependem dela.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}
