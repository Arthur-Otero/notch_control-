# Status da bolinha

A bolinha mostra o que dá para concluir olhando o fim da tela do iTerm2, uma vez por segundo. O texto da conversa, acima do compositor, não muda o status. Uma frase como "do you want to proceed" no meio da resposta não é um pedido.

Clicar na bolinha traz a aba dessa sessão para a frente. O painel não copia o terminal.

## O que aparece

| O que você vê | Significado | O notch |
|---|---|---|
| Anel verde girando | O agente está executando. | Fica aberto. |
| Anel verde parado | O turno terminou e essa aba ainda não foi vista. | Fica aberto. |
| `!` vermelho | O compositor pede uma decisão. | Fica aberto. |
| Nada | Parado no prompt, e você já clicou na bolinha ou o iTerm2 está na frente nessa aba. | Pode recolher. |
| Logo apagado | A tela não foi reconhecida. O app não inventa um estado. | Pode recolher. |

Abaixo da bolinha, uma barra fina mostra quanto do contexto a sessão ocupa: verde abaixo de 30%, amarela abaixo de 70% e vermelha a partir de 70%. Ela só aparece quando o rodapé do CLI informa o contexto, e o balão repete o percentual.

Com **Mostrar entradas do arquivo de trabalho no notch** ligado, cada bolinha é uma entrada do `work.md`:

| O que você vê | Significado | Clique |
|---|---|---|
| Qualquer indicador acima | A sessão mais recente da entrada que está aberta no iTerm2. | Traz a aba para a frente. |
| Logo na cor da trilha, sem anel | Nenhuma sessão da entrada tem terminal aberto. | Retoma a sessão mais recente numa aba nova. |
| Documento na cor da trilha | A entrada não lista sessões. | Abre o arquivo de trabalho. |
| Linha entre grupos | Separa, nesta ordem: entradas com terminal aberto, sessões abertas fora do arquivo e entradas sem terminal aberto. | — |

O tooltip em inglês chama o `!` de "Waiting for input" e o motivo de "Approval requested" ou "Question pending". Em português: "Esperando resposta", "Aprovação pendente" ou "Pergunta pendente". Isso só aparece junto com o `!`.

## Como o Claude Code é lido

O Claude Code desenha o compositor (`❯`) entre duas linhas horizontais, e o app lê essa estrutura, não o fim da tela:

| Na tela | Estado |
|---|---|
| Linha de spinner logo acima do compositor, como `✻ Deciphering… (33s · ↓ 3.2k tokens)` ou `· Considering… (running PreToolUse hook · 7s)` | Trabalhando |
| Linha `✻ Waiting for 2 background agents to finish` logo acima do compositor (sem `…`; a lista de agentes pode vir expandida abaixo dele) | Trabalhando |
| Linha `✻ Worked for 10s · done 2:48` (o verbo muda a cada turno) logo acima do compositor | Parado, resultado ainda não visto |
| Compositor sem spinner nem linha de fim de turno, inclusive com a sugestão `Try "…"` ou texto digitado | Parado |
| Sem compositor e com lista numerada com cursor, `❯ 1. Yes … 3. No` (permissão de Bash, criação/edição de arquivo, aprovação de plano) | `!` Aprovação pendente |
| Sem compositor e com lista numerada com cursor da pergunta do agente (`Chat about this`, `Enter to select`) | `!` Pergunta pendente |

Uma sessão com nome (`/rename`, `--name`) desenha o nome dentro da linha superior do compositor (`──────── ccid-shared-session-fix ─`). Essa linha continua sendo a borda do compositor; a inferior segue como régua pura. A estrutura foi exercitada com Claude Code 2.1.289.

Enquanto o compositor está na tela, nada acima dele vira `!`, mesmo que o agente cite "Do you want to proceed?" na resposta. Um menu numerado que não é decisão (como o `/model`) não gera `!`. As frases da seção "Quando aparece o `!`" continuam valendo para o Codex e versões antigas do Claude Code. Formato exercitado com Claude Code 2.1.289.

## Como o Cursor Agent é lido

O compositor do Cursor Agent é uma caixa (`▄▄▄` em cima, `→ …` no meio, `▀▀▀` embaixo), e o app lê essa estrutura:

| Na tela | Estado |
|---|---|
| `ctrl+c to stop` na linha do compositor, ou spinner em braille logo acima (`⠠⠜ Working`, `⠘⠆ Running  49 tokens`) | Trabalhando |
| Compositor sem essas marcas, inclusive com `→ Plan, search, build anything`, `→ Add a follow-up` ou texto digitado | Parado |
| Caixa de pergunta (`Question 1 of 1`, `Space select · Enter next/submit · Esc to skip`) no lugar do compositor | `!` Pergunta pendente |
| Caixa do plano com `Ready to build?` (`Yes, build locally (b)`, `No, propose changes (p or Esc)`) | `!` Aprovação pendente |
| `Waiting for approval...` na linha da ferramenta, ou opções `Run (once) (y)` / `Proceed (y)` junto com `Skip (esc or n)` | `!` Aprovação pendente |

O Cursor Agent não escreve nada quando o turno termina. O verde de resultado vem da transição trabalhando → parado e fica até a aba ser vista, como no Claude Code. As opções de aprovação de comando vêm do código do agente e ainda precisam de validação em execução real. O formato do compositor foi exercitado com Cursor Agent 2026.10.01.

## Quando fica verde parado

O turno acabou e o compositor só espera outro prompt. A tela traz algo como `Worked for`, `Brewed for`, `Churned for` ou `· done`, ou o agente saiu de "executando" / de um `!` e voltou ao prompt.

O anel verde parado permanece até uma destas coisas:

- você clica na bolinha;
- o iTerm2 é o aplicativo na frente e essa sessão é a aba ativa.

Uma aba só selecionada dentro do iTerm2, com outro aplicativo na frente, não conta. O notch continua aberto.

Depois disso a bolinha fica parada, sem anel. Trocar para outra aba não reacende o verde do turno que você já viu.

## Quando aparece o `!`

Só se o próprio compositor, nas últimas linhas, pede uma decisão. As frases reconhecidas são:

- `Do you want to proceed`
- `Yes, and don't ask again`
- `No, and tell`
- `waiting for your permission`
- `approve this`
- `permission required`

`Esc to cancel` sozinho não é decisão. "Approve for me" no rodapé do Codex é um modo, não um pedido.

O `!` sai quando esse pedido sai do compositor. Abrir a aba não apaga um pedido que ainda está na tela.

## Quando o verde gira

O agente ainda está executando. Nas últimas linhas aparece `esc to interrupt`, `ctrl+c to stop`, `ctrl+c to interrupt`, `orchestrating`, ou `Running` junto com `tokens`.

## O que não classifica

Silêncio, CPU baixa e uma tela que não casa com nenhuma frase ficam sem estado. A leitura anterior é mantida até a próxima frase reconhecida. A primeira leitura ao abrir o app não dispara alerta.

Hooks de Claude e Codex, se forem instalados, também podem marcar execução, conclusão e decisão. Sem eles, vale a leitura da tela descrita aqui.

## Codex

O parser localiza o compositor e examina a região anterior. `esc to interrupt` continua indicando trabalho quando barras extras o empurram para fora das últimas linhas. Um marcador mais recente de fim de turno prevalece sobre atividade antiga.

## Limitações

Os parsers dependem do formato da tela do CLI. No Claude Code, uma lista longa de agentes abaixo do compositor pode tirá-lo da janela de reconhecimento. Versões e layouts novos precisam de validação antes de ampliar as regras.
