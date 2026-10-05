# NotchControl

## Antes de alterar

- Leia `README.md` para o uso e as limitações atuais.
- Integração, transporte, persistência ou configuração: leia `docs/architecture.md`.
- Interface, geometria ou tokens: leia `docs/DESIGN.md`.
- Estados e indicadores das sessões: leia `docs/status.md`.

## Contrato do produto

- Sessões locais comuns no iTerm2 são o alvo atual. As bolinhas abrem a aba correspondente; o painel lê Markdown.
- Preserve os agentes ao fechar painel ou app e mantenha arquivos do usuário somente leitura.
- Valide terminal, geração e conexão antes de qualquer efeito. Identidade ambígua, input em outra sessão ou aprovação na bolinha errada impedem a entrega.
- Configuração de hooks preserva terceiros, detecta concorrência e usa a confiança oficial do CLI.
- Launcher obrigatório de agentes, tmux ou mudança de terminal exigem uma decisão explícita do usuário.
- A sessão principal implementa e valida diretamente. Delegação depende de novo pedido do usuário.

## Implementação e validação

- Mantenha o núcleo independente de AppKit e os protocolos externos no gateway/helper.
- Gere tokens com `scripts/generate-design.py`; o arquivo gerado deve corresponder a `docs/DESIGN.md`.
- Execute `bash scripts/test.sh` para mudanças de código e `bash scripts/build-app.sh arm64` para mudanças no app ou bundle.
- Separe resultados de fixtures, build e execução real; testes automatizados não encerram a validação da integração.
- Atualize o README ou documento canônico quando mudar comportamento. A documentação de referência fica em `docs/`; planos, diários e evidências temporárias ficam fora do repositório.
- Ao encontrar bloqueio real, informe causa, resultado observado e ação necessária; continue o trabalho independente.

