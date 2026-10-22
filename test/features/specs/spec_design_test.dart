import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/spec_design.dart';

void main() {
  test('"Gerar design" asks for "O que já existe" and at least one file per '
      'step (SPEC-017 R3)', () {
    expect(designPrompt, contains('### O que já existe'));
    expect(designPrompt, contains('ao menos um arquivo'));
    final etapa =
        ((designSchema['properties'] as Map)['etapas'] as Map)['items'] as Map;
    final arquivos = (etapa['properties'] as Map)['arquivos'] as Map;
    expect(arquivos['minItems'], 1);
  });
}
