# Prompt

Conversas livres na raiz do workspace, sem worktree.

## Modos

- **Perguntar**: somente leitura.
- **Planejar**: modo `plan`. O plano pronto aparece num cartão com "Implementar como sessão", "Transformar em spec" e "Continuar planejando", e é salvo em `.promptorium/planos/`. O app nunca aprova o plano pelo agente.
- **Editar**: `acceptEdits`.

O menu do provedor lista Claude Code, Codex e os agentes ACP cadastrados. Trocar de modelo vale a partir da próxima mensagem.

Com o **Codex**:

- Perguntar e Planejar rodam em somente leitura, imposta pelo sandbox. Editar pede a sua confirmação.
- O Codex não tem modo `plan`: no fim do turno, **Executar plano** abre um turno em Editar com o plano, na mesma conversa.
- Trocar de provedor numa conversa com histórico abre uma conversa nova.
- Sem o sandbox na máquina, o Codex fica bloqueado aqui, com "Sandbox do Codex indisponível" ([Provedores](como-funciona.md#provedores)).

## Composer

- `@arquivo` e `/prompt-salvo`, com ↑/↓, Enter/Tab e Esc.
- Anexos: arraste ou use "Anexar arquivos". Imagens vão como imagem; arquivos de fora do workspace são copiados para `.promptorium/attachments/<data>/`.
- Ctrl+Enter envia.

Prompts salvos de fábrica: `/explicar`, `/testes`, `/revisar-seguranca`, `/spec`, `/commit`. "Salvar como prompt" numa resposta, ou "Novo" no painel Prompts salvos, cria outros.

## Da conversa para o trabalho

- **Transformar em spec**: cria uma spec em rascunho com o resumo da conversa.
- **Continuar como sessão**: continua a conversa (`--resume --fork-session`) numa sessão com worktree próprio.
- **Spec detectada nesta resposta**: quando o agente escreve uma spec na resposta, uma faixa oferece "Salvar como SPEC-NNN", "Aplicar na SPEC-x" (só em spec no Backlog), "Salvar como nova", "Prévia" (diff, renderizado ou Markdown), "Copiar" e "Abrir em Specs". O app avisa se o arquivo mudou desde o início da conversa.

## Refinar uma spec

"Refinar com IA" (em Specs) e "Aplicar" numa sugestão do cartão (no Quadro) abrem uma conversa de refino: cada edição do agente na spec pede a sua aprovação.

O botão **Voltar à spec SPEC-x** leva você de volta para a tela de origem (Specs ou o cartão no Quadro), com o arquivo recarregado. Se houver edição esperando aprovação, o app avisa antes ("Voltar mesmo assim" ou "Ficar na conversa"). A conversa continua na lista e pode ser retomada.
