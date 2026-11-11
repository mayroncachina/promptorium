---
id: SPEC-065
status: aprovada
issue: 184
---

# A barra do card mostra o estado de cada etapa

## Objetivo

No Quadro, cada card tem uma barra com um segmento por etapa. Hoje as cores se repetem: "rodando" e "verificando" são âmbar, e "aguardando você" e "verificação falhou" são vermelhos. Olhando o Quadro, não dá para saber se uma spec está trabalhando, sendo testada ou parada esperando alguém, nem qual etapa está ativa.

Esta spec dá **uma cor por estado**, com "verificando" em roxo, e faz o segmento da etapa ativa **pulsar** enquanto uma sessão ou o gate trabalha nele.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/QUeph8T2owT52iAVMAWYWv) (no canvas o pulso aparece animado). Capturas em `docs/mockups/spec-065/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: rodando e verificando iguais; aguardando você e falha iguais | — |
| `2-cores.png` | Uma cor por estado, a legenda e o pulso | R1, R2 |
| `3-pulso.png` | O pulso quadro a quadro e a tabela dos estados | R2, R3 |
| `4-reduzido.png` | Movimento reduzido: as cores ficam, o pulso não | R4 |

## Requisitos

- R1 · Cada segmento da barra do card tem a cor do estado da etapa:
  - pendente: cinza (a borda de hoje);
  - rodando: âmbar;
  - verificando: roxo (`AppColors.lilac`);
  - aguardando você (pergunta ou aprovação): âmbar-claro (`AppColors.amberLight`);
  - verificação falhou: vermelho;
  - concluída: teal.
- R2 · Os segmentos **rodando** e **verificando** pulsam: a opacidade vai de 100% a 40% e volta, em 1,2 s, sem parar, enquanto o estado durar. Os outros estados ficam parados.
- R3 · A troca de cor continua suave (a transição de hoje, `StepColorTransition`). O pulso começa quando a etapa entra num estado ativo e para na hora em que sai, terminando na cor nova com opacidade cheia.
- R4 · Com movimento reduzido (o ajuste do sistema ou "Reduzir animações" do app), as cores valem e o pulso não acontece.
- R5 · Os pontos das etapas no Grafo e no Foco usam as mesmas cores e o mesmo pulso.
- R6 · A cor nunca é o único sinal: a dica do segmento continua com "R2 · verificando", e a linha do card continua com o texto do estado ("R2 verificando", "R2 aguardando você").

## Fora do escopo

- Mudar as cores das colunas, das bordas dos cards ou do texto de estado.
- O tremor de atenção dos cards (SPEC-054).
- Novos estados de etapa.

## Design

### O que já existe

- `lib/features/board/board_screen.dart`: `stepSegmentColor(StepView)` (as cores de hoje) e `_Progress`, que desenha os segmentos com `StepColorTransition`.
- `lib/features/board/widgets/step_live_dialog.dart` e `spec_canvas.dart`: os pontos das etapas no Grafo e no Foco.
- `AppMotion.animate(context)` e a preferência "Reduzir animações".

### Componentes

- **`stepSegmentColor`** com as cores do R1.
- **`StepPulse`** (novo): envolve o segmento; com um estado ativo e movimento permitido, anima a opacidade (100% → 40% → 100%, 1,2 s, `Curves.easeInOut`, repetindo); fora disso, opacidade 1 e nenhum `Ticker` rodando.
- **`isStepActive(StepView)`**: rodando ou verificando (e não `gateFailed`).
- Os pontos do Grafo e do Foco usam `stepSegmentColor` e `StepPulse`.

### Testes

- Cor de cada estado (incluindo `gateFailed` e aguardando você).
- Pulso: com rodando e verificando a opacidade muda ao longo de 1,2 s; parado nos outros; ao sair do estado ativo, opacidade 1 e sem ticker.
- Movimento reduzido: cor certa, opacidade 1 o tempo todo.
- A dica do segmento com o estado; Grafo e Foco com as mesmas cores.

## Decisões

- **Roxo para verificar.** O roxo já é a cor de "verificando" no texto do card ("R2 verificando" em lilás); a barra passa a combinar.
- **Âmbar-claro para aguardando você.** É atenção, mas diferente de "rodando": a etapa parou e espera a pessoa. O vermelho fica só para a falha do gate.
- **Pulso só no que está trabalhando.** Pulsar o que espera a pessoa competiria com o tremor de atenção (SPEC-054); o pulso diz "está andando", não "olhe aqui".
- **Opacidade, não tamanho.** Só a opacidade muda: nada se mexe no layout e o custo é baixo com muitos cards.

## Plano

1. **t1 · Cores e pulso** (R1–R6): as cores, `StepPulse`, o Grafo e o Foco, o movimento reduzido e os testes.

## Critérios de aceite

- [ ] Cada estado da etapa tem a sua cor na barra do card, com "verificando" em roxo.
- [ ] Os segmentos rodando e verificando pulsam enquanto o estado durar.
- [ ] Com movimento reduzido, as cores valem e nada pulsa.
- [ ] O Grafo e o Foco usam as mesmas cores e o mesmo pulso.
