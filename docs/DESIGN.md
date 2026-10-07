---
version: alpha
name: NotchControl
description: Controle lateral macOS para sessões de agentes e relatório de trabalho.
colors:
  primary: "#B4C9F5"
  background: "#101114"
  surface: "#1B1D22"
  hover: "#292C33"
  border: "#454954"
  text: "#F3F4F6"
  muted: "#B6BAC4"
  danger: "#FF6B73"
  warning: "#FFC94D"
  unknown: "#969CAA"
  focus: "#88B8FF"
  notch: "#000000"
  ringTrack: "#303030"
  contextTrack: "#4A4A4A"
  notchInk: "#FFFFFF"
  activity: "#00FF88"
typography:
  sans:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    lineHeight: "18px"
  mono:
    fontFamily: "SFMono-Regular, Menlo, monospace"
    fontSize: "13px"
    lineHeight: "18px"
rounded:
  DEFAULT: "10px"
  control: "6px"
  notch: "30px"
spacing:
  compact: "6px"
  regular: "10px"
  content: "16px"
  notchFlare: "39px"
  notchTopPadding: "26px"
  notchBottomPadding: "19px"
  notchCellSpacing: "22px"
  notchTrackStroke: "6px"
  notchActivityStroke: "3px"
  notchGlyphSize: "18px"
  tooltipTail: "14px"
components:
  sessionIcon:
    width: "44px"
    height: "44px"
    backgroundColor: "{colors.notch}"
    textColor: "{colors.notchInk}"
  sessionIconTrack:
    backgroundColor: "{colors.ringTrack}"
  sessionIconWorking:
    backgroundColor: "{colors.activity}"
  sessionIconWaiting:
    backgroundColor: "{colors.danger}"
    textColor: "{colors.notch}"
  sessionIconUnknown:
    textColor: "{colors.unknown}"
  sessionIconHover:
    backgroundColor: "{colors.background}"
  tooltip:
    width: "300px"
    backgroundColor: "{colors.notch}"
    textColor: "{colors.notchInk}"
  notchRail:
    width: "70px"
    backgroundColor: "{colors.notch}"
    textColor: "{colors.notchInk}"
  notchPill:
    width: "10px"
    height: "79px"
    backgroundColor: "{colors.notch}"
  panelHeader:
    height: "56px"
    backgroundColor: "{colors.notch}"
    textColor: "{colors.text}"
  panelHeaderAction:
    textColor: "{colors.muted}"
  statePill:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.notch}"
  statePillWaiting:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.danger}"
  terminalCard:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text}"
    rounded: "{rounded.DEFAULT}"
  terminalCardEdge:
    backgroundColor: "{colors.border}"
  focusRing:
    textColor: "{colors.focus}"
  controlHover:
    backgroundColor: "{colors.hover}"
    textColor: "{colors.primary}"
---

# Design do NotchControl

## Overview

O [CodeNotch](https://github.com/vinzdg/codenotch) é a referência visual: controle preto compacto na borda do desktop, curvas inversas de união e bolinhas com logo branco e estado. O público usa vários agentes junto a IDEs e ao iTerm2; precisão de sessão e leitura rápida têm prioridade.

As bolinhas abrem a aba do iTerm2. O painel lateral é um leitor Markdown nativo somente leitura, com abas de trabalho e histórico. A interface oferece PT-BR e inglês e mantém os dados do usuário no idioma original.

Este documento define intenção visual e tokens. O frontmatter alimenta `scripts/generate-design.py`, que gera `Sources/NotchControlUI/DesignTokens.swift`; `--check` detecta drift. Os donos dos componentes e contratos de interação estão em [architecture.md](architecture.md).

## Colors

Notch e balão usam preto puro, logos brancos e trilha neutra `ringTrack`. `activity` é trabalho ou resultado não visto; `danger` acompanha `!` para decisão; `unknown` reduz a presença da sessão sem inventar estado. O significado completo está em [status.md](status.md).

A barra de contexto, abaixo da bolinha e com a largura do anel, usa `activity` abaixo de 30%, `warning` abaixo de 70% e `danger` a partir de 70% do contexto da sessão, sobre a trilha `contextTrack`, um grau mais clara que `ringTrack` para a barra fina não sumir no preto. O anel continua dizendo o que o agente faz; a barra, quanto do contexto ele ocupa.

Texto principal usa `text`, contexto usa `muted` e foco usa `focus`. Forma, texto e nome acessível complementam as cores. A aparência atual é escura; contraste e transparência seguem os recursos do macOS.

## Typography

Controles usam fonte de sistema de 13 pt; valores numéricos usam dígitos tabulares. Nome/projeto têm hierarquia distinta e truncamento central quando necessário. Os tokens expressos em `px` representam pontos lógicos no adapter nativo.

O Markdown usa corpo de 13 pt, títulos de 26/21/17/15/14/13 pt e código monoespaçado de 12 pt. Foundation e AppKit renderizam listas, citações, tabelas e links, com seleção e cópia nativas.

## Layout

O notch tem corpo de 70 pt e ícones de 44 pt: documento, divisor e sessões sem números. O documento fica fixo; a lista rola apenas quando excede a altura disponível, limitada a 864 pt (dez sessões). Tooltips flutuam sem alterar a lista. Uma aba de 14 × 60 pt, no meio da lateral interna, abre e fecha uma coluna de 230 pt com o título de cada bolinha na mesma linha dela; a coluna rola junto com as bolinhas, e o notch não recolhe enquanto ela está aberta. Recolhido, o notch mostra uma aba menor, de 40 pt, que abre o notch já com os títulos; ela fica fora da área de hover da pílula para não expandir o notch antes do clique.

O painel ocupa a altura útil e revela o conteúdo lateralmente, com o notch na borda interna. A largura do conteúdo fica estável durante a transição. O leitor preserva a posição ao receber atualização; trocar de arquivo volta ao topo. A zona de resize de 5 pt é transparente.

## Elevation & Depth

Barra, painel e balão usam `hasShadow = false`; a sombra do macOS acrescenta um contorno claro indesejado à forma preta. As bolinhas não possuem sombra individual.

O painel é persistente e não modal. Clique fora mantém aberto. Hover e alertas não tomam foco; seleção explícita ativa o conteúdo.

## Shapes

Bolinhas circulares usam logo central, anel verde para trabalho/resultado e `!` vermelho no canto superior direito. Não há número abaixo do logo. O relatório conserva área clicável de 44 pt e realce fino quando selecionado, sem anel decorativo.

Curvas e faixas pretas são áreas de arraste, sem ícones permanentes. A pílula recolhida conserva a união à borda. Preferências oferece posicionamento sem arraste.

## Components

`RailView`, `SessionButton`, `SessionDetails`, `WindowCoordinator`, `ReportPanel` e `SettingsView` compartilham tokens e catálogos. Pickers, diálogos de arquivo, campos, scrollbars e seleção são nativos. Erros e estados vazio/carregando ocupam regiões estáveis, com instrução e recuperação localizada.

O balão tem 300 pt, incluindo ponta de 14 pt voltada à sessão. Apresenta provedor, estado, limites disponíveis, nome e projeto. Barras de limite usam `activity` abaixo de 50%, `warning` abaixo de 80% e `danger` a partir de 80%; percentuais aparecem também em texto. Uso ausente tem mensagem própria; a duração de uma janela só é informada quando a fonte a fornece.

O hover aguarda 400 ms e detalhes equivalentes podem ser abertos pelo foco/menu de contexto. Renomear e mover antes/depois são ações do menu da bolinha. Fechar painel está disponível no documento, botão, `⌘W` e gesto da borda interna.

Abertura/fechamento usa 320 ms. Entrada, saída e ordem de sessões usam 280 ms, curva 0.22/1/0.36/1, opacidade, escala 0.86 e deslocamento de 8 pt. `NotchMotion` centraliza a receita. Movimento reduzido e arraste desativam essas animações; posição é persistida ao soltar.

O terminal espelhado pertence ao harness experimental. Sua paleta vem do perfil iTerm2; ela não recebe as cores semânticas dos controles do aplicativo.

## Do's and Don'ts

- Preserve a silhueta lateral do CodeNotch e o fluxo atual de sessão no iTerm2.
- Use os tokens gerados e os controles nativos existentes.
- Mantenha dimensões e posição das ações entre estados; exponha foco e nomes acessíveis.
- Mantenha preto puro, curvas livres e informações técnicas no diagnóstico.
- Distinga resultado não visto de pergunta/aprovação pendente.
- Mantenha o leitor somente leitura e comandos do Markdown como texto.
- Valide janela real, mouse, VoiceOver, Spaces e monitores separadamente das prévias e fixtures.
