import 'package:flutter/widgets.dart';

import '../../ui/widgets/placeholder_screen.dart';

class CodeScreen extends StatelessWidget {
  const CodeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Código', editorKey: 'code');
}
