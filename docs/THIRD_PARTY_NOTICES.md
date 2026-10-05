# Referências e dependências

Inventário verificado em 2026-10-03. O bundle contém executável Swift, catálogos, três vetores de provedores e licenças de atribuição; o launcher instala dependências Python em `.venv`, separadamente.

| Componente | Versão/licença declarada | Uso |
|---|---|---|
| [CodeNotch](https://github.com/vinzdg/codenotch) | [MIT, Copyright (c) 2026 Vinz](https://github.com/vinzdg/codenotch/blob/main/LICENSE) | Referência de produto e adaptação das proporções/contorno lateral em SideNotchShape. Licença incluída no bundle. |
| [Lobe Icons](https://github.com/lobehub/lobe-icons) | [MIT, Copyright (c) 2023 LobeHub](https://github.com/lobehub/lobe-icons/blob/master/LICENSE) | Paths de [Claude](https://github.com/lobehub/lobe-icons/blob/master/src/Claude/components/Mono.tsx) e [OpenAI](https://github.com/lobehub/lobe-icons/blob/master/src/OpenAI/components/Mono.tsx), obtidos em 2026-10-03, e de [Cursor](https://github.com/lobehub/lobe-icons/blob/master/src/Cursor/components/Mono.tsx) (pacote `@lobehub/icons-static-svg` 1.95.1), obtido em 2026-10-04; geometria 24 × 24 preservada e fill branco. Recursos claude.svg/openai.svg/cursor.svg e licença no bundle. Representações de marca por terceiros. |
| [iTerm2 Python SDK](https://github.com/gnachman/iTerm2/tree/master/api/library/python/iterm2) | 2.25, GPLv2 | API de sessões, tela, histórico, input, perfil e abas. Instalado localmente pelo pip; fontes/licença pertencem à distribuição do SDK. |
| [protobuf](https://github.com/protocolbuffers/protobuf) | 6.33.6, BSD de três cláusulas | Dependência transitiva instalada do SDK. |
| [websockets](https://github.com/python-websockets/websockets) | 15.0.1, BSD de três cláusulas | Dependência transitiva instalada do SDK. |
| Swift/AppKit/SwiftUI/Foundation/ServiceManagement/UserNotifications | SDK Xcode 26.2 | Frameworks nativos do sistema. |
| SF Symbols | Recursos do sistema Apple | Ícones de ações do aplicativo. |

As versões transitivas descrevem o ambiente demonstrado; `helper/requirements.txt` fixa o SDK principal. O ambiente instalado mantém seus próprios arquivos de licença. Recursos locais incluem CodeNotch-LICENSE.txt e LobeIcons-LICENSE.txt, copiados ao bundle. O projeto não empacota Python/iTerm2, DMG, notarização ou atualização automática.
