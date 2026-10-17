import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/widgets/step_trace_panel.dart';

void main() {
  test('criteriaOfStep keeps the lines that cite the step', () {
    const text = '''
## Requisitos
- R1 · a
- R2 · b

## Critérios de aceite
- [ ] Testes passam [R1] · verificar: flutter test
- [x] Texto parcial em 300 ms [R2]
- [ ] Resume não duplica [R2][R1]
- [ ] Sem requisito
''';
    expect(criteriaOfStep(text, 'R2').map((c) => c.text), [
      'Texto parcial em 300 ms [R2]',
      'Resume não duplica [R2][R1]',
    ]);
    expect(criteriaOfStep(text, 'R2').first.checkedInFile, isTrue);
    expect(criteriaOfStep(text, 'R3'), isEmpty);
  });

  test('designExcerpt prefers paragraphs that mention the step', () {
    const design =
        'Um DeltaBuffer por sessão.\n\nR2 lê o buffer por StreamProvider.\n\n'
        'R3 cobre com testes.';
    expect(designExcerpt(design, 'R2'), 'R2 lê o buffer por StreamProvider.');
    expect(designExcerpt(design, 'R9'), design);
    expect(designExcerpt('x' * 400, 'R1')!.length, 321);
    expect(designExcerpt(null, 'R1'), isNull);
    expect(designExcerpt('  ', 'R1'), isNull);
  });
}
