import json
import os
from pathlib import Path
import select
import subprocess
import sys
import shlex
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent


class Bridge:
    def __init__(self, scenario=None, real_screen=False):
        environment = dict(os.environ)
        environment["PYTHONPATH"] = str(ROOT / "Tests/BridgeFixtures")
        environment.update(scenario or {})
        command = [sys.executable, str(ROOT / "helper/proof_bridge.py"), "--serve"]
        if real_screen:
            environment.pop("PYTHONPATH", None)
            command = [str(ROOT / ".venv/bin/python3"), "-I", str(ROOT / "Tests/BridgeFixtures/real_sdk_bridge.py")]
        self.process = subprocess.Popen(command,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        env=environment, bufsize=0)
        self.effects = []
        self.screens = []
        self.diagnostics = []
        self.sequence = 0
        self.connection = self.read()["connection"]
        inventory = self.request("inventory")
        self.terminals = [row["identity"] for row in inventory["terminals"]]

    def read(self):
        if not select.select([self.process.stdout], [], [], 15)[0]:
            raise AssertionError("Ponte não respondeu no prazo")
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError("Ponte encerrou sem resposta")
        return json.loads(line)

    def request(self, kind, **values):
        self.sequence += 1
        identity = str(self.sequence)
        command = {"version": 1, "requestID": identity, "type": kind, **values}
        self.process.stdin.write((json.dumps(command) + "\n").encode())
        self.process.stdin.flush()
        while True:
            result = self.read()
            if result["type"] == "fixture_effect":
                self.effects.append(result)
            if result["type"] == "screen":
                self.screens.append(result)
            if result["type"] == "diagnostic":
                self.diagnostics.append(result)
            if result.get("requestID") == identity:
                return result

    def target(self, index, selection):
        return {"connection": self.connection, "terminal": self.terminals[index], "selection": selection}

    def close(self):
        try:
            if self.process.poll() is None:
                self.request("shutdown")
        finally:
            try:
                self.process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.communicate(timeout=5)


class ProofBridgeBehaviorTests(unittest.TestCase):
    def bridge(self, scenario=None):
        bridge = Bridge(scenario)
        self.addCleanup(bridge.close)
        return bridge

    def test_input_after_switch_is_rejected_and_valid_input_suppresses_broadcast(self):
        bridge = self.bridge()
        first = bridge.target(0, 1)
        second = bridge.target(1, 2)
        self.assertEqual(bridge.request("select", **first)["type"], "ack")
        self.assertEqual(bridge.request("input", **first, text="á\t\x1b[A\x03", suppressBroadcast=True)["type"], "ack")
        self.assertEqual(bridge.request("select", **second)["type"], "ack")
        self.assertEqual(bridge.request("input", **first, text="obsolete", suppressBroadcast=True)["code"], "stale_selection")
        self.assertEqual(bridge.request("input", **second, text="new", suppressBroadcast=False)["code"], "broadcast_suppression_required")
        self.assertEqual(bridge.request("input", **second, text="isolated", suppressBroadcast=True)["type"], "ack")
        effects = [effect for effect in bridge.effects if effect["method"] == "send_text"]
        self.assertEqual([(effect["terminal"], effect["text"], effect["suppressBroadcast"]) for effect in effects],
                         [("t1", "á\t\x1b[A\x03", True), ("t2", "isolated", True)])

    def test_inventory_recognizes_claude_code_cursor_agent_and_ignores_shells(self):
        bridge = self.bridge({"NOTCH_CONTROL_FIXTURE_AGENTS": "1"})
        rows = {row["identity"]["id"]: row for row in bridge.request("inventory")["terminals"]}
        self.assertEqual(rows["t1"]["provider"], "claude")
        self.assertEqual(rows["t2"]["provider"], "cursor")
        self.assertIsNone(rows["t3"]["provider"])
        self.assertEqual(rows["t1"]["processStart"], None)  # sem processo real no fixture; nada é inventado

    def test_inventory_reports_the_conversation_from_the_claude_registry_before_the_command_line(self):
        started = "aaaaaaaa-0000-4000-8000-000000000001"
        current = "bbbbbbbb-0000-4000-8000-000000000002"
        with tempfile.TemporaryDirectory() as home:
            scenario = {"NOTCH_CONTROL_FIXTURE_AGENTS": "1", "HOME": home,
                        "NOTCH_CONTROL_FIXTURE_CLAUDE_COMMAND": "claude -r " + started}
            rows = {row["identity"]["id"]: row for row in self.bridge(scenario).request("inventory")["terminals"]}
            self.assertEqual(rows["t1"]["conversation"], started)
            self.assertIsNone(rows["t2"]["conversation"])
            self.assertIsNone(rows["t3"]["conversation"])
            # A real process stands in for Claude Code so `ps` can prove the registry belongs to it.
            pid = os.getpid()
            start = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "lstart="], capture_output=True, text=True,
                                   env={**os.environ, "LC_ALL": "C", "TZ": "UTC"}).stdout.strip()
            registry = Path(home) / ".claude/sessions"
            registry.mkdir(parents=True)
            (registry / (str(pid) + ".json")).write_text(json.dumps({"pid": pid, "sessionId": current, "procStart": start}))
            scenario["NOTCH_CONTROL_FIXTURE_CLAUDE_PID"] = str(pid)
            rows = {row["identity"]["id"]: row for row in self.bridge(scenario).request("inventory")["terminals"]}
            self.assertEqual(rows["t1"]["conversation"], current)

    def test_session_closing_during_inventory_is_dropped_without_failing_the_listing(self):
        bridge = Bridge({"NOTCH_CONTROL_FIXTURE_CLOSING_SESSION": "1"})
        self.addCleanup(bridge.close)
        self.assertEqual([row["identity"]["id"] for row in bridge.request("inventory")["terminals"]], ["t1"])

    def test_reveal_activates_the_iterm_session_without_opening_a_mirror(self):
        bridge = self.bridge()
        result = bridge.request("reveal", connection=bridge.connection, terminal=bridge.terminals[0])
        self.assertEqual(result["type"], "ack")
        self.assertEqual([item["method"] for item in bridge.effects if item["method"] == "activate"], ["activate"])
        self.assertEqual(bridge.screens, [])

    def test_dock_moves_the_session_into_a_borderless_window_and_undock_returns_it(self):
        bridge = self.bridge()
        target = bridge.target(0, 1)
        bridge.request("select", **target)
        docked = bridge.request("dock", **target, frameX=120, frameY=80, frameWidth=640, frameHeight=500)
        self.assertEqual(docked["type"], "ack")
        self.assertTrue(docked["docked"])
        bridge.request("place", **target, frameX=140, frameY=90, frameWidth=700, frameHeight=520)
        bridge.request("focus", **target)
        bridge.request("unselect", **target)
        methods = [(item["method"], item.get("identifier"), item.get("x")) for item in bridge.effects]
        self.assertIn(("move_to_new_window", None, None), methods)
        self.assertIn(("menu", "Window Style.No Title Bar", None), methods)
        self.assertIn(("set_frame", None, 140), methods)
        self.assertIn(("menu", "Window Style.Normal", None), methods)
        self.assertIn(("move_to_new_tab", None, None), methods)

    def test_blank_cells_are_trimmed_and_styles_are_shared_between_neighbours(self):
        bridge = self.bridge()
        line = bridge.request("select", **bridge.target(0, 1)) and bridge.screens[0]["lines"][0]
        self.assertEqual(line["runs"], [{"t": ["x"]}])

    def test_resize_restores_when_switching_and_closing_without_closing_terminal(self):
        bridge = self.bridge()
        first = bridge.target(0, 1)
        second = bridge.target(1, 2)
        bridge.request("select", **first)
        self.assertEqual(bridge.request("resize", **first, columns=100, rows=30)["type"], "ack")
        bridge.request("select", **second)
        self.assertEqual(bridge.request("resize", **second, columns=110, rows=35)["type"], "ack")
        bridge.request("shutdown")
        self.assertEqual([(item["terminal"], item["columns"], item["rows"]) for item in bridge.effects],
                         [("t1", 100, 30), ("t1", 80, 24), ("t2", 110, 35), ("t2", 80, 24)])
        self.assertEqual(bridge.process.wait(timeout=5), 0)

    def test_restore_preserves_a_later_manual_resize(self):
        bridge = self.bridge({"NOTCH_CONTROL_FIXTURE_MANUAL_RESIZE": "1"})
        target = bridge.target(0, 1)
        bridge.request("select", **target)
        bridge.request("resize", **target, columns=100, rows=30)
        restored = bridge.request("restore", **target)
        self.assertFalse(restored["restored"])
        self.assertEqual(restored["reason"], "manual_resize")
        self.assertEqual(len(bridge.effects), 1)

    def test_split_and_fullscreen_preserve_grid(self):
        for scenario, code in [("NOTCH_CONTROL_FIXTURE_SPLIT", "resize_split_unavailable"),
                               ("NOTCH_CONTROL_FIXTURE_FULLSCREEN", "resize_fullscreen_unavailable")]:
            with self.subTest(scenario=scenario):
                bridge = self.bridge({scenario: "1"})
                target = bridge.target(0, 1)
                bridge.request("select", **target)
                self.assertEqual(bridge.request("resize", **target, columns=100, rows=30)["code"], code)
                self.assertEqual(bridge.effects, [])

    def test_external_failure_is_sanitized_and_input_is_not_retried(self):
        bridge = self.bridge({"NOTCH_CONTROL_FIXTURE_INPUT_FAIL": "1"})
        target = bridge.target(0, 1)
        bridge.request("select", **target)
        result = bridge.request("input", **target, text="private", suppressBroadcast=True)
        self.assertEqual(result["code"], "api_operation_failed")
        self.assertTrue(result["ambiguous"])
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertEqual(bridge.effects, [])

    def test_input_without_reply_times_out_without_resending_and_inventory_recovers(self):
        bridge = self.bridge({"NOTCH_CONTROL_FIXTURE_INPUT_STALL": "1"})
        target = bridge.target(0, 1)
        bridge.request("select", **target)
        result = bridge.request("input", **target, text="once", suppressBroadcast=True)
        self.assertEqual(result["code"], "operation_timeout")
        self.assertTrue(result["ambiguous"])
        self.assertEqual(bridge.request("inventory")["type"], "inventory")
        sends = [effect for effect in bridge.effects if effect["method"] == "send_text"]
        self.assertEqual(len(sends), 1)

    def test_shutdown_before_inventory_cancels_hook_monitor_without_error(self):
        with tempfile.TemporaryDirectory() as folder:
            environment = dict(os.environ, PYTHONPATH=str(ROOT / "Tests/BridgeFixtures"), NOTCH_CONTROL_EVENT_DIR=folder)
            result = subprocess.run([sys.executable, str(ROOT / "helper/proof_bridge.py"), "--serve"],
                                    input=json.dumps({"version": 1, "requestID": "close", "type": "shutdown"}) + "\n",
                                    capture_output=True, text=True, env=environment, timeout=5)
            messages = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(any(message.get("requestID") == "close" and message["type"] == "ack" for message in messages))

    def diagnostics_until_exit(self, bridge):
        codes = []
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                message = bridge.read()
            except AssertionError:
                break
            if message["type"] == "diagnostic":
                codes.append(message.get("code"))
        self.assertEqual(bridge.process.wait(timeout=5), 0)
        return codes

    def test_bridge_exits_when_iterm_closes_the_connection(self):
        bridge = self.bridge({"NOTCH_CONTROL_FIXTURE_CONNECTION_DROP": "0.5"})
        self.assertIn("connection_unavailable", self.diagnostics_until_exit(bridge))

    def test_bridge_exits_even_when_cleanup_waits_on_the_gone_iterm(self):
        bridge = self.bridge({"NOTCH_CONTROL_FIXTURE_CONNECTION_DROP": "1.5", "NOTCH_CONTROL_FIXTURE_CLEANUP_HANG": "1"})
        self.assertEqual(bridge.request("select", **bridge.target(0, 1))["type"], "ack")
        self.assertIn("connection_unavailable", self.diagnostics_until_exit(bridge))

    def test_history_belongs_to_selected_terminal_and_stale_target_is_rejected(self):
        bridge = self.bridge()
        target = bridge.target(0, 1)
        bridge.request("select", **target)
        result = bridge.request("history", **target)
        self.assertEqual(result["type"], "history")
        self.assertEqual(result["terminal"]["id"], "t1")
        self.assertEqual(result["lines"][0]["runs"][0]["t"][0], "x")
        bridge.request("select", **bridge.target(1, 2))
        self.assertEqual(bridge.request("history", **target)["code"], "stale_selection")

    def test_earlier_history_is_bounded_and_reaches_the_oldest_available_line(self):
        bridge = self.bridge({'NOTCH_CONTROL_FIXTURE_BIG_HISTORY': '1'})
        target = bridge.target(0, 1)
        bridge.request('select', **target)
        latest = bridge.request('history', **target)
        self.assertEqual((latest['firstLine'], len(latest['lines']), latest['hasMore']), (750, 500, True))
        earlier = bridge.request('history', **target, before=750)
        self.assertEqual((earlier['firstLine'], len(earlier['lines']), earlier['hasMore']), (250, 500, True))
        oldest = bridge.request('history', **target, before=250)
        self.assertEqual((oldest['firstLine'], len(oldest['lines']), oldest['hasMore']), (50, 200, False))

    def test_large_messages_over_the_unix_socket_arrive_intact_even_when_the_reader_is_slow(self):
        # Regressão: asyncio deixa o socket não-bloqueante e print() produzia escritas parciais, que corrompiam
        # mensagens grandes (histórico/tela) e derrubavam a ponte.
        import socket
        import time
        folder = tempfile.mkdtemp(prefix="ncs-", dir="/private/tmp")
        path = folder + "/bridge"
        environment = dict(os.environ, PYTHONPATH=str(ROOT / "Tests/BridgeFixtures"), NOTCH_CONTROL_FIXTURE_STYLED="1",
                           NOTCH_CONTROL_FIXTURE_BIG_HISTORY="1")
        process = subprocess.Popen([sys.executable, str(ROOT / "helper/proof_bridge.py"), "--serve", "--socket", path],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment, text=True)
        self.addCleanup(lambda: (process.kill(), process.communicate()))
        self.assertEqual(json.loads(process.stdout.readline())["type"], "socket_ready")
        client = socket.socket(socket.AF_UNIX)
        client.settimeout(15)
        client.connect(path)
        stream = client.makefile("rw", encoding="utf-8")
        self.addCleanup(client.close)
        self.addCleanup(stream.close)

        def send(**values):
            stream.write(json.dumps({"version": 1, **values}) + "\n")
            stream.flush()

        connection = json.loads(stream.readline())["connection"]
        send(type="inventory", requestID="inventory")
        terminal = json.loads(stream.readline())["terminals"][0]["identity"]
        target = {"connection": connection, "terminal": terminal, "selection": 1}
        send(type="select", requestID="select", **target)
        for _ in range(3):
            send(type="history", requestID="history", **target)
        time.sleep(1.0)  # leitor parado: o buffer do socket enche enquanto a ponte ainda tem mensagens a enviar
        messages = []
        while not any(item.get("requestID") == "history" and item["type"] == "history" for item in messages[-1:]) or \
                len([item for item in messages if item["type"] == "history"]) < 3:
            line = stream.readline()
            self.assertTrue(line, "A ponte encerrou a conexão")
            messages.append(json.loads(line))  # JSON inválido (mensagem truncada/intercalada) falha aqui
        self.assertIsNone(process.poll())
        history = next(item for item in messages if item["type"] == "history")
        self.assertEqual(len(history["lines"]), 500)
        self.assertGreater(len(json.dumps(history)), 200_000)
        send(type="shutdown", requestID="shutdown")
        self.assertEqual(process.wait(timeout=10), 0)

    @unittest.skipUnless((ROOT / ".venv/bin/python3").exists(), "SDK real não instalado")
    def test_resume_uses_sdk_profile_with_quoted_directory_and_background_tab(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.build', prefix="Project 'quoted' ") as folder:
            binary = Path(folder) / 'codex'
            binary.write_text('exit 0\n')
            binary.chmod(0o700)
            bridge = Bridge({'PATH': folder + os.pathsep + os.environ.get('PATH', '')}, real_screen=True)
            self.addCleanup(bridge.close)
            conversation = '00000000-0000-0000-0000-000000000002'
            result = bridge.request('resume', connection=bridge.connection,
                                    resume={'provider': 'codex', 'conversation': conversation, 'directory': folder})
            self.assertEqual(result['type'], 'ack')
            created = next(effect for effect in bridge.effects if effect['method'] == 'create_tab')
            self.assertFalse(created['select'])
            self.assertEqual(created['profile']['Working Directory'], folder)
            self.assertEqual(created['profile']['Custom Directory'], 'Yes')
            invocation = shlex.split(created['profile']['Command'])
            self.assertEqual(invocation[:2], ['/bin/zsh', '-lic'])
            self.assertEqual(shlex.split(invocation[2]), ['cd', '--', folder, '&&', 'exec', str(binary), 'resume', conversation])

    @unittest.skipUnless((ROOT / ".venv/bin/python3").exists(), "SDK real não instalado")
    def test_resume_without_iterm_window_opens_one(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.build') as folder:
            binary = Path(folder) / 'codex'; binary.write_text('exit 0\n'); binary.chmod(0o700)
            bridge = Bridge({'PATH': folder + os.pathsep + os.environ.get('PATH', ''), 'NOTCH_CONTROL_FIXTURE_NO_WINDOWS': '1'}, real_screen=True)
            self.addCleanup(bridge.close)
            result = bridge.request('resume', connection=bridge.connection,
                                    resume={'provider': 'codex', 'conversation': '00000000-0000-0000-0000-000000000002', 'directory': folder})
            self.assertEqual(result['type'], 'ack')
            self.assertEqual(result['createdTerminal'], 't3')
            created = next(effect for effect in bridge.effects if effect['method'] == 'create_window')
            self.assertEqual(shlex.split(created['profile']['Command'])[:2], ['/bin/zsh', '-lic'])
            self.assertEqual(created['profile']['Working Directory'], folder)

    @unittest.skipUnless((ROOT / ".venv/bin/python3").exists(), "SDK real não instalado")
    def test_resume_without_terminal_receipt_keeps_result_ambiguous(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.build') as folder:
            binary = Path(folder) / 'codex'; binary.write_text('exit 0\n'); binary.chmod(0o700)
            bridge = Bridge({'PATH': folder + os.pathsep + os.environ.get('PATH', ''), 'NOTCH_CONTROL_FIXTURE_EMPTY_TAB_RECEIPT': '1'}, real_screen=True)
            self.addCleanup(bridge.close)
            result = bridge.request('resume', connection=bridge.connection,
                                    resume={'provider': 'codex', 'conversation': '00000000-0000-0000-0000-000000000002', 'directory': folder})
            self.assertEqual(result['type'], 'error')
            self.assertTrue(result['ambiguous'])
            self.assertEqual(len([effect for effect in bridge.effects if effect['method'] == 'create_tab']), 1)

    @unittest.skipUnless((ROOT / ".venv/bin/python3").exists(), "SDK real não instalado")
    def test_styled_screen_from_installed_sdk_is_delivered_for_selected_terminal(self):
        bridge = Bridge(real_screen=True)
        self.addCleanup(bridge.close)
        result = bridge.request("select", **bridge.target(0, 1))
        self.assertEqual(result["type"], "ack", (result, bridge.diagnostics))
        self.assertEqual(len(bridge.screens), 1)
        self.assertEqual(bridge.screens[0]["terminal"]["id"], "t1")
        self.assertEqual(bridge.screens[0]["lines"][0]["runs"][0]["t"][0], "A")


if __name__ == "__main__":
    unittest.main()
