import '../../specs/spec_file.dart' show foldText;
import '../board_screen.dart';

/// Cards whose number or title has [query], without telling upper case or
/// accents apart (SPEC-036 R7). The order of [cards] is kept.
List<SpecCardData> searchFolder(List<SpecCardData> cards, String query) {
  final needle = foldText(query.trim());
  if (needle.isEmpty) return cards;
  return [
    for (final d in cards)
      if (foldText('${d.spec.code} ${d.spec.title}').contains(needle)) d,
  ];
}
