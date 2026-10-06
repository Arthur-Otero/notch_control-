# NotchControl

Aplicativo nativo para macOS que acompanha sessões locais de **Claude Code, Codex CLI e Cursor Agent** no iTerm2. Um notch na lateral da tela reúne as sessões, mostra seus estados e dá acesso a um leitor de Markdown.

> **Em desenvolvimento (alpha).** O projeto já pode ser compilado e usado localmente, mas a integração completa, a acessibilidade e o comportamento em diferentes monitores ainda estão em validação. Não há uma distribuição estável ou notarizada.

Inspirado no [CodeNotch, de vinzdg](https://github.com/vinzdg/codenotch), especialmente no controle lateral, nas curvas de união à borda e na apresentação das sessões.

## O que funciona hoje

- Descoberta de agentes abertos normalmente em abas do iTerm2.
- Uma bolinha por sessão, com o logo do provedor e indicação de trabalho, resultado ou decisão pendente.
- Clique na bolinha para abrir a aba correspondente no iTerm2.
- Balão com nome, projeto, estado e limites de uso quando o rodapé do CLI fornece essa informação.
- Barra fina abaixo da bolinha com o contexto ocupado pela sessão, quando o rodapé o informa.
- Notch nas bordas esquerda ou direita, com posição, monitor, aliases e ordem das sessões persistidos.
- Painel de Markdown somente leitura, com abas de trabalho e histórico, seleção, cópia e atualização automática.
- Modo opcional com uma bolinha por sessão do arquivo de trabalho, retomando no iTerm2 as sessões com terminal fechado. Entradas que dividem uma sessão ficam numa bolinha só.
- Preferências em português e inglês, sons e notificações configuráveis.
- Diagnóstico da integração e reconexão automática quando o iTerm2 fica disponível.

Os agentes continuam rodando quando o painel é fechado ou o NotchControl é encerrado. O aplicativo acompanha sessões existentes; você abre e utiliza cada CLI como de costume.

## Requisitos

| Requisito | Detalhe |
|---|---|
| macOS | 15 ou superior |
| Xcode | Instalado e selecionado como ambiente de desenvolvimento, com Swift 6 ou superior |
| Python | 3.9 ou superior, com `venv` e `pip` |
| iTerm2 | Instalado, aberto e com a Python API habilitada |
| Agente | Pelo menos um dos CLIs: Claude Code, Codex ou Cursor Agent |
| Internet | Necessária na primeira execução para instalar as dependências Python |

O helper utiliza o SDK oficial `iterm2==2.25`, instalado em um ambiente virtual dentro do projeto. Os CLIs e seus logins devem estar configurados separadamente.

O ambiente usado durante o desenvolvimento foi macOS 26.2, Xcode 26.2, Swift 6.2.3 e iTerm2 3.7.3 em Apple Silicon. O build Intel é suportado pelo script; a execução em hardware Intel ainda precisa ser validada.

## Como executar agora

1. Baixe ou clone este repositório em uma pasta chamada `notch_control`.
2. Abra o iTerm2 e habilite **Settings → General → Magic → Enable Python API**.
3. Na pasta do projeto, execute:

   ```bash
   cd notch_control
   bash scripts/run-app.sh
   ```

4. Autorize o helper quando o iTerm2 apresentar o diálogo de acesso.
5. Abra uma aba do iTerm2 e inicie `claude`, `codex` ou `agent`, conforme os CLIs instalados.

Também é possível abrir **Iniciar NotchControl.command** pelo Finder.

O script prepara `.venv`, instala o SDK, compila o app para a arquitetura do Mac, cria o bundle e aplica uma assinatura local. O app usa o helper e o Python dessa pasta: mantenha o projeto disponível e execute o launcher novamente se mudar sua localização. Copiar apenas o `.app` para outro Mac ainda não é suficiente.

Os bundles ficam em:

```text
build/arm64/NotchControl.app
build/x86_64/NotchControl.app
```

Para detalhes sobre a autorização de scripts, consulte a [documentação oficial do iTerm2](https://iterm2.com/python-api/tutorial/running.html).

## Como usar

Passe o mouse sobre o notch para expandir. Clique na bolinha de uma sessão para acessar sua aba no iTerm2; perguntas e aprovações são respondidas no próprio terminal.

| Indicador | Significado |
|---|---|
| Anel verde girando | Agente trabalhando, inclusive esperando agentes em segundo plano |
| Anel verde parado | Turno concluído; resultado ainda não visto |
| `!` vermelho | Pergunta ou aprovação pendente |
| Sem anel de atividade | Sessão parada e já vista |
| Logo apagado | Estado não reconhecido |

O resultado é considerado visto quando você clica na bolinha ou quando o iTerm2 está em primeiro plano com essa aba ativa. Abrir a aba não apaga uma aprovação que continua pendente. O comportamento detalhado está em [docs/status.md](docs/status.md).

Arraste a área preta para mover o notch pela lateral, trocar de borda ou de monitor. O clique secundário abre Preferências. O menu de contexto de cada bolinha permite renomear e mudar a ordem da sessão. Preferências também oferece posição e monitor como alternativas ao arraste.

### Ler arquivos Markdown

Clique no ícone de documento e escolha um arquivo de trabalho. Você pode usar qualquer Markdown UTF-8; `work.md` e `history.md` são as convenções sugeridas para trabalho e histórico.

O painel renderiza títulos, listas, checklists, citações, código, tabelas e links. Mudanças feitas por outro editor aparecem automaticamente. O leitor preserva a posição de leitura e permite selecionar e copiar texto.

Feche pelo ícone de documento, botão de fechar, `⌘W` ou arrastando a borda interna. Clicar fora mantém o painel aberto. Comandos escritos no Markdown são exibidos como texto; retomada de conversas pelo painel ainda não está disponível.

### Entradas do arquivo de trabalho no notch

Com um arquivo de trabalho escolhido, ligue **Preferências → Relatório → Mostrar entradas do arquivo de trabalho no notch**. O notch passa a mostrar uma bolinha por sessão do arquivo, na ordem das entradas `##`. Cada entrada lista suas sessões com o comando de retomada, a mais recente primeiro:

```markdown
## 2026-10-06 08:00 — #123 Paywall novo
- Sessões:
  - 2026-10-06 · Opus 5.5
    cd /caminho/do/projeto && claude -r 00000000-0000-0000-0000-000000000001
- Status: Lib pronta; falta integrar no app.
```

| Entrada | Bolinha | Clique |
|---|---|---|
| Uma das sessões está aberta no iTerm2 | Igual à da sessão, com estado, `!` e alertas | Traz a aba para a frente |
| Nenhuma sessão aberta | Logo do agente na cor da trilha | Retoma a sessão mais recente numa aba nova |
| Sem sessões | Documento na cor da trilha | Abre o painel do arquivo de trabalho |

Uma sessão pode cobrir vários repositórios, e então várias entradas listam a mesma conversa. Cada entrada é representada por uma sessão: a aberta no iTerm2 ou, se nenhuma estiver aberta, a mais recente. Entradas representadas pela mesma sessão dividem uma única bolinha, então cada sessão, aberta ou fechada, aparece uma só vez. A bolinha usa o título e o `Status` da primeira dessas entradas na ordem do arquivo, e o balão acrescenta `+N na mesma sessão` com os títulos das demais. Uma sessão antiga de uma entrada que já tem outra sessão aberta ou mais recente não ganha bolinha própria. Se a mesma conversa estiver aberta em duas abas, a segunda continua visível entre as sessões fora do arquivo.

O notch agrupa as bolinhas, separadas por divisórias: primeiro as entradas com terminal aberto, depois as sessões abertas que nenhuma entrada mostra e, por último, as entradas sem terminal aberto. Dentro de cada grupo vale a ordem do arquivo. O balão de uma entrada mostra o título, o `Status`, os títulos das entradas que dividem a sessão, o estado e a pasta. Para ligar a sessão aberta à entrada, o app usa o registro de sessões do Claude Code e, nos outros CLIs, o ID passado na retomada (`codex resume <id>`, `agent --resume <id>`).

### Hooks opcionais

A leitura do estado pela tela funciona sem instalar hooks. Para experimentar eventos estruturados de Claude Code ou Codex:

1. Abra **Preferências → Integração** e escolha o provedor.
2. Clique em **Preparar configuração** e selecione o arquivo de configuração do CLI.
3. Revise o plano criado em `.notchcontrol/`.
4. Use **Instalar hooks** e siga o fluxo de confiança oferecido pelo CLI.

O instalador preserva entradas de terceiros e recusa alterações concorrentes. Para remover, prepare a configuração atual e use **Remover hooks do NotchControl**. Se mover a pasta do projeto, remova os hooks antes e prepare a instalação novamente no novo caminho.

A associação dos hooks às sessões, especialmente em processos compartilhados, segue experimental. Hooks do Cursor Agent não estão disponíveis.

## Desenvolvimento

```bash
bash scripts/test.sh
bash scripts/build-app.sh arm64
bash scripts/build-app.sh x86_64
python3 scripts/generate-design.py --check
```

A suíte cobre o núcleo Swift, componentes nativos e helpers Python. Os testes de integração usam fixtures e alguns tipos do SDK instalado; a aprovação de funcionamento com sessões reais é uma verificação separada.

O harness de integração pode ser aberto com `bash scripts/run-proof.sh` ou **Iniciar Prova.command**. Use abas de teste descartáveis para exercitar tela, input e resize.

### Estrutura

```text
Sources/
  NotchControl/                 Aplicação, janelas e preferências
  NotchControlCore/             Sessões, estados, geometria e arquivos
  NotchControlUI/               Componentes nativos e gateway do iTerm2
  NotchControlProof/            Harness de integração
helper/                        Ponte Python, descoberta e estados
scripts/                       Ambiente, execução, build e validação
Tests/                         Testes Swift e Python
docs/                          Arquitetura, design, status e atribuições
```

Leia [arquitetura](docs/architecture.md) para os limites entre componentes e [design](docs/DESIGN.md) para os tokens e a intenção visual. Mudanças devem manter o destino exato de cada sessão, preservar agentes e arquivos do usuário e atualizar a documentação correspondente.

## Diagnóstico

Em Preferências, **Verificar integração** confere iTerm2, API, SDK e CLIs. **Reconectar** inicia uma nova tentativa de conexão.

Também é possível executar:

```bash
.venv/bin/python3 scripts/diagnose.py --root "$PWD"
```

- **Nenhuma sessão aparece:** confirme que o CLI está em uma aba local do iTerm2, que a API está habilitada e que o helper foi autorizado.
- **Uso indisponível no balão:** o formato do rodapé pode não fornecer limites reconhecíveis. O app não estima uma porcentagem. No Claude Code, a statusline precisa escrever `5h 42%` e `7d 13%` ou, para incluir a renovação, `18:00 42%` e `13/10 13%` no começo da linha ou logo depois de `·` ou `|`. O contexto vem de `ctx 12%` ou `ctx:12%`; no Codex, de `Context 14% used` ou `86% context left`.
- **Erro de compilação:** confira a seleção do Xcode e a versão do Swift.
- **Falha após mover o projeto:** encerre o app e execute novamente `bash scripts/run-app.sh`. Se o cache ainda apontar para o caminho antigo, remova `.build/` e compile novamente.
- **Falha ao abrir o bundle pelo Finder:** use o launcher ou `scripts/run-app.sh`, que prepara o ambiente e inicia o executável diretamente.

Diagnósticos locais ficam em `.proof/diagnostics.jsonl`; preferências, aliases e planos de hooks ficam em `.notchcontrol/`. Essas pastas, os builds, o ambiente Python e os caches são ignorados pelo Git. Antes de compartilhar um diagnóstico, revise seus dados locais.

## Limitações e próximos passos

- Suporte inicial a sessões locais no iTerm2; outros terminais, terminal integrado do Cursor IDE e SSH não estão contemplados.
- Classificação de estado e limites depende do formato da tela de cada versão do CLI. Listas muito longas de agentes em segundo plano podem esconder o compositor.
- Validação completa de associação entre múltiplas sessões, hooks, foco, VoiceOver, Spaces e monitores ainda está pendente.
- O terminal interativo dentro do painel permanece como experimento no harness; o fluxo atual abre a sessão no iTerm2.
- No modo do arquivo de trabalho, uma sessão de Codex ou Cursor Agent aberta sem `resume` só é ligada à entrada pelos hooks. O registro de sessões do Claude Code é um formato interno e pode mudar entre versões.
- Não há instalador, DMG, notarização ou atualização automática.

## Créditos e atribuições

O [CodeNotch](https://github.com/vinzdg/codenotch), de **vinzdg**, inspirou o produto e a geometria do notch lateral. Sua licença MIT está preservada nos recursos do aplicativo.

Os logos dos provedores vêm de [Lobe Icons](https://github.com/lobehub/lobe-icons). A integração usa a [Python API do iTerm2](https://iterm2.com/python-api/).

As dependências e respectivas atribuições estão em [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
