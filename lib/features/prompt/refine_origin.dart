/// Screen a refine conversation was opened from (SPEC-021).
enum RefineSource {
  /// "Refinar com IA" on the Specs screen.
  specs,

  /// "Aplicar" on a suggestion of a board card.
  board;

  /// Null for unknown values and old conversations (null column).
  static RefineSource? fromName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Spec and screen a refine conversation came from (stored in
/// `conversations.refine_spec_code` / `refine_origin`).
typedef RefineOrigin = ({String specCode, RefineSource source});
