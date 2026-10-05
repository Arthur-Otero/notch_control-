"""Identifica qual CLI de agente roda em primeiro plano em uma sessão do iTerm2.

O nome do job do iTerm2 não basta: Claude Code é instalado como binário nomeado pela
versão (`jobName` = "2.1.288") e o Cursor Agent roda como `node`. Por isso a decisão usa
a linha de comando completa do processo, além de `jobName` e do título do processo.
"""
import os
import re
import shlex

CLAUDE, CODEX, CURSOR = "claude", "codex", "cursor"

# Subcomandos e flags que encerram sozinhos ou apenas configuram: não são conversas.
_ONE_SHOT = {
    CLAUDE: {"mcp", "config", "doctor", "update", "install", "migrate-installer", "setup-token",
             "plugin", "plugins", "api-key", "--version", "-v", "--help", "-h", "-p", "--print"},
    CODEX: {"exec", "e", "login", "logout", "mcp", "mcp-server", "app-server", "completion", "apply",
            "a", "cloud", "features", "help", "sandbox", "proto", "debug", "--version", "-V", "--help", "-h"},
    CURSOR: {"status", "login", "logout", "about", "update", "install-shell-integration",
             "uninstall-shell-integration", "mcp", "models", "whoami", "generate-rule",
             "--version", "-v", "--help", "-h", "-p", "--print"},
}
_RUNTIMES = {"node", "bun", "bunx", "deno", "npx", "python", "python3", "env", "sh", "bash", "zsh"}
_VERSIONED_CODEX = re.compile(r"^codex-(aarch64|x86_64)-")


def _tokens(command):
    if not command:
        return []
    try:
        return shlex.split(command)
    except ValueError:
        return command.split()


def _marker(token):
    """Provedor indicado por um único token da linha de comando, ou None."""
    name = os.path.basename(token).lstrip("-")
    if name in ("claude", "claude-code") or "/@anthropic-ai/claude-code/" in token or "/.claude/local/" in token:
        return CLAUDE
    if "/claude/versions/" in token:
        return CLAUDE
    if name == "codex" or _VERSIONED_CODEX.match(name) or "/@openai/codex/" in token:
        return CODEX
    if name == "cursor-agent" or "/cursor-agent/" in token:
        return CURSOR
    return None


def detect_provider(job_name="", command_line="", process_title="", command=""):
    """Retorna "claude", "codex", "cursor" ou None para uma sessão com CLI interativo."""
    argv = _tokens(command) or _tokens(command_line)
    if not argv:
        argv = [str(job_name or process_title or "")]
    if argv and not argv[0]:
        return None
    first = os.path.basename(argv[0].lstrip("-"))
    provider = None
    start = 0
    for index, token in enumerate(argv[:6]):
        provider = _marker(token)
        if provider:
            start = index
            break
        if index == 0 and first not in _RUNTIMES and first != "agent":
            break
    if provider is None and first == "agent" and any("cursor-agent" in token for token in argv[1:]):
        provider, start = CURSOR, 0
    if provider is None and first == "agent":
        try:
            if "cursor-agent" in os.path.realpath(argv[0]):
                provider, start = CURSOR, 0
        except OSError:
            pass
    if provider is None:
        # Último recurso: o título do processo identifica o CLI quando a linha de comando foi reescrita.
        title = os.path.basename(str(process_title or "").strip())
        if title in ("claude", "codex") and str(job_name or "") not in ("zsh", "bash", "fish", "sh"):
            provider = title
        else:
            return None
    for token in argv[start + 1:]:
        if token.startswith("-"):
            if token in _ONE_SHOT[provider]:
                return None
            continue
        if "/" in token or token.endswith(".js"):
            continue
        if token in _ONE_SHOT[provider]:
            return None
        break
    return provider
