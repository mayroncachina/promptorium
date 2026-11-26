import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/prompt/compare/compare_handoff.dart';
import 'package:promptorium/features/sessions/timeline.dart';

/// SPEC-108 R4: the starting context built by the app.
void main() {
  ToolItem read(String path) =>
      ToolItem(id: path, name: 'Read', input: {'file_path': path});

  test('last messages, files cited, plan and git, relative to the root', () {
    final h = buildCompareHandoff(
      title: 'Cupons expirados',
      provider: 'claude',
      root: '/work/repo',
      branch: 'main',
      changed: 0,
      items: [
        for (var i = 0; i < 4; i++) ...[
          UserItem('pergunta $i @lib/cupons/a$i.dart?'),
          AssistantTextItem('resposta $i'),
        ],
        read('/work/repo/lib/checkout.dart'),
        read('/etc/passwd'),
        ToolItem(
          id: 'p',
          name: 'ExitPlanMode',
          input: const {'plan': '1. Trocar o filtro'},
        ),
      ],
    )!;
    expect(h.messages, handoffMessages);
    expect(h.text, isNot(contains('pergunta 0')));
    expect(h.text, contains('Pessoa: pergunta 3'));
    expect(h.text, contains('Resposta: resposta 3'));
    expect(h.text, contains('Plano vigente:\n1. Trocar o filtro'));
    expect(h.files, contains('lib/checkout.dart'));
    // Without the question mark of the sentence.
    expect(h.files, contains('lib/cupons/a3.dart'));
    // Nothing outside of the project.
    expect(h.text, isNot(contains('/etc/passwd')));
    expect(h.git, 'main · limpo');
    expect(h.text, contains('Estado do git: main · limpo'));
    expect(h.hasPlan, isTrue);
  });

  test('a conversation without messages has no package', () {
    expect(
      buildCompareHandoff(title: 't', provider: 'claude', items: const []),
      isNull,
    );
  });

  test('secrets are masked, a private key goes whole, also in the edited '
      'text', () {
    const key = 'ghp_1234567890abcdefghijklmnopqrstuvwxyzAB';
    final h = buildCompareHandoff(
      title: 't',
      provider: 'codex',
      items: [
        UserItem(
          'usei $key e\n-----BEGIN RSA PRIVATE KEY-----\nMIIEcorpo\n'
          '-----END RSA PRIVATE KEY-----\nfim',
        ),
      ],
    )!;
    expect(h.text, isNot(contains(key)));
    expect(h.text, isNot(contains('MIIEcorpo')));
    expect(h.text, contains('fim'));
    expect(h.withText('token $key').text, isNot(contains(key)));
    expect(h.withText('x').edited, isTrue);
  });

  test('handoffPrompt keeps the question whole', () {
    expect(
      handoffPrompt(const CompareHandoff(text: 'resumo'), 'e agora?'),
      'resumo\n\nPergunta atual:\ne agora?',
    );
  });
}
