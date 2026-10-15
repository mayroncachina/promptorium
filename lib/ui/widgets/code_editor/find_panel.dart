import 'dart:math';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../theme/tokens.dart';

// Adapted from re_editor 0.10.0 `example/lib/find.dart` (plano, tabela 0.4):
// same layout and controller calls, app colors and Portuguese tooltips.

const EdgeInsetsGeometry _kFindMargin = EdgeInsets.only(right: 10, top: 4);
const double _kFindPanelWidth = 380;
const double _kFindPanelHeight = 36;
const double _kReplacePanelHeight = _kFindPanelHeight * 2;
const double _kFindIconSize = 16;
const double _kFindIconWidth = 30;
const double _kFindIconHeight = 30;
const double _kFindInputFontSize = 13;
const double _kFindResultFontSize = 12;
const EdgeInsetsGeometry _kFindPadding = EdgeInsets.only(
  left: 5,
  right: 5,
  top: 2.5,
  bottom: 2.5,
);
const EdgeInsetsGeometry _kFindInputContentPadding = EdgeInsets.only(
  left: 6,
  right: 6,
);

/// Find / replace panel shown at the top right of [AppCodeEditor]
/// (Ctrl+F opens find, Ctrl+H opens replace, Esc closes).
class CodeFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const CodeFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  final CodeFindController controller;
  final bool readOnly;

  static const _decoration = InputDecoration(
    filled: true,
    fillColor: AppColors.background,
    isDense: true,
    contentPadding: _kFindInputContentPadding,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: AppColors.border),
      gapPadding: 0,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: AppColors.border),
      gapPadding: 0,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: AppColors.amber),
      gapPadding: 0,
    ),
  );

  @override
  Size get preferredSize => Size(
    double.infinity,
    controller.value == null
        ? 0
        : ((controller.value!.replaceMode
                  ? _kReplacePanelHeight
                  : _kFindPanelHeight) +
              _kFindMargin.vertical),
  );

  @override
  Widget build(BuildContext context) {
    if (controller.value == null) {
      return const SizedBox(width: 0, height: 0);
    }
    return Container(
      margin: _kFindMargin,
      alignment: Alignment.topRight,
      height: preferredSize.height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: _kFindPanelWidth,
          decoration: BoxDecoration(
            color: AppColors.panel,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              _buildFindInputView(context),
              if (controller.value!.replaceMode && !readOnly)
                _buildReplaceInputView(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFindInputView(BuildContext context) {
    final CodeFindValue value = controller.value!;
    final String result;
    if (value.result == null) {
      result = 'nenhum';
    } else {
      result = '${value.result!.index + 1}/${value.result!.matches.length}';
    }
    return Row(
      children: [
        SizedBox(
          width: _kFindPanelWidth / 1.75,
          height: _kFindPanelHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildTextField(
                key: const ValueKey('code-find-input'),
                controller: controller.findInputController,
                focusNode: controller.findInputFocusNode,
                hint: 'Buscar',
                iconsWidth: _kFindIconWidth * 1.5,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildCheckText(
                    text: 'Aa',
                    tooltip: 'Diferenciar maiúsculas',
                    checked: value.option.caseSensitive,
                    onPressed: controller.toggleCaseSensitive,
                  ),
                  _buildCheckText(
                    text: '.*',
                    tooltip: 'Expressão regular',
                    checked: value.option.regex,
                    onPressed: controller.toggleRegex,
                  ),
                ],
              ),
            ],
          ),
        ),
        Text(
          result,
          key: const ValueKey('code-find-result'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: _kFindResultFontSize,
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildIconButton(
                onPressed: value.result == null
                    ? null
                    : controller.previousMatch,
                icon: Icons.arrow_upward,
                tooltip: 'Anterior',
              ),
              _buildIconButton(
                onPressed: value.result == null ? null : controller.nextMatch,
                icon: Icons.arrow_downward,
                tooltip: 'Próximo',
              ),
              _buildIconButton(
                onPressed: controller.close,
                icon: Icons.close,
                tooltip: 'Fechar (Esc)',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReplaceInputView(BuildContext context) {
    final CodeFindValue value = controller.value!;
    return Row(
      children: [
        SizedBox(
          width: _kFindPanelWidth / 1.75,
          height: _kFindPanelHeight,
          child: _buildTextField(
            key: const ValueKey('code-replace-input'),
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
            hint: 'Substituir',
          ),
        ),
        _buildIconButton(
          key: const ValueKey('code-replace-one'),
          onPressed: value.result == null ? null : controller.replaceMatch,
          icon: Icons.done,
          tooltip: 'Substituir',
        ),
        _buildIconButton(
          key: const ValueKey('code-replace-all'),
          onPressed: value.result == null ? null : controller.replaceAllMatches,
          icon: Icons.done_all,
          tooltip: 'Substituir todos',
        ),
      ],
    );
  }

  Widget _buildTextField({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    double iconsWidth = 0,
  }) {
    return Padding(
      padding: _kFindPadding,
      child: TextField(
        key: key,
        maxLines: 1,
        focusNode: focusNode,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: _kFindInputFontSize,
        ),
        decoration: _decoration.copyWith(
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppColors.textMuted,
            fontSize: _kFindInputFontSize,
          ),
          contentPadding: (_decoration.contentPadding ?? EdgeInsets.zero).add(
            EdgeInsets.only(right: iconsWidth),
          ),
        ),
        controller: controller,
      ),
    );
  }

  Widget _buildCheckText({
    required String text,
    required String tooltip,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: _kFindIconWidth * 0.75,
            child: Text(
              text,
              style: TextStyle(
                color: checked ? AppColors.amber : AppColors.textSecondary,
                fontSize: _kFindInputFontSize,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    Key? key,
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return IconButton(
      key: key,
      onPressed: onPressed,
      color: AppColors.textSecondary,
      disabledColor: AppColors.border,
      icon: Icon(icon, size: _kFindIconSize),
      constraints: const BoxConstraints(
        maxWidth: _kFindIconWidth,
        maxHeight: _kFindIconHeight,
      ),
      tooltip: tooltip,
      splashRadius: max(_kFindIconWidth, _kFindIconHeight) / 2,
    );
  }
}
