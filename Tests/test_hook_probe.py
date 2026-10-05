import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class HookProbeBehaviorTests(unittest.TestCase):
    def test_probe_records_association_candidates_without_conversation_or_permission_decision(self):
        with tempfile.TemporaryDirectory() as folder:
            payload = {"hook_event_name": "PermissionRequest", "session_id": "test-session-1",
                       "turn_id": "test-turn-1", "tool_name": "Bash",
                       "tool_input": {"command": "PRIVATE-COMMAND"}, "prompt": "PRIVATE-PROMPT",
                       "transcript_path": "/private/PRIVATE-TRANSCRIPT"}
            result = subprocess.run([sys.executable, str(ROOT / "helper/proof_hook.py"),
                                     "--provider", "codex", "--output", folder],
                                    input=json.dumps(payload), text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            files = list(Path(folder).glob("*.json"))
            self.assertEqual(len(files), 1)
            text = files[0].read_text()
            data = json.loads(text)
            self.assertEqual(data["provider"], "codex")
            self.assertEqual(data["event"], "PermissionRequest")
            self.assertEqual(data["conversation"], "test-session-1")
            self.assertFalse(data["associationProven"])
            self.assertNotIn("PRIVATE", text)
            self.assertEqual(files[0].stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
