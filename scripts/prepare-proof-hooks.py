import json
from pathlib import Path
import shlex


def main():
    root = Path(__file__).resolve().parent.parent
    folder = root / ".proof/hook-fragments"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    shared = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
              "PostToolUse", "Stop", "SubagentStart", "SubagentStop"]
    for provider in ("claude", "codex"):
        events = shared + (["Notification"] if provider == "claude" else ["Interrupt"])
        command = "python3 " + shlex.quote(str(root / "helper/proof_hook.py")) + " --provider " + provider + \
            " --output " + shlex.quote(str(root / ".proof/hook-events"))
        data = {"hooks": {event: [{"hooks": [{"type": "command", "command": command, "timeout": 3}]}]
                          for event in events}}
        (folder / (provider + ".json")).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print("Fragmentos preparados em .proof/hook-fragments. Nenhuma configuração externa foi alterada.")


if __name__ == "__main__":
    main()
