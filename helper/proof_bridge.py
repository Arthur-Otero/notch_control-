import argparse
import asyncio
import contextlib
import importlib.metadata
import json
import os
import socket
import shlex
import shutil
import subprocess
from pathlib import Path
import time
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from agent_detect import detect_provider

PROTOCOL = 1
PROTOCOL_OUTPUT = sys.stdout
# Em modo socket as mensagens saem por um transporte assíncrono. O socket fica não-bloqueante
# (asyncio exige isso para ler); escrever nele com print() produz escritas parciais que
# corrompem mensagens grandes, então toda saída passa pelo buffer do transporte.
WIRE_WRITER = None
SHELLS = {"zsh", "bash", "fish", "sh", "dash", "tcsh", "ksh", "login"}
VARIABLES = ("jobPid", "tty", "jobName", "path", "creationTimeString", "tmuxRole", "hostname",
             "commandLine", "processTitle")
# Acima disto, quadros de tela intermediários são descartados; o mais recente é reenviado depois.
SCREEN_BACKLOG_LIMIT = 1_500_000
RESUME_COMMANDS = {"claude": (("claude",), ["-r"]), "codex": (("codex",), ["resume"]),
                   "cursor": (("agent", "cursor-agent"), ["--resume"])}


class BridgeError(ValueError):
    pass


def emit(message_type, **payload):
    line = json.dumps({"version": PROTOCOL, "type": message_type, **payload}, ensure_ascii=False) + "\n"
    data = line.encode("utf-8", errors="replace")
    if WIRE_WRITER is not None:
        WIRE_WRITER.write(data)
    else:
        try:
            print(data.decode("utf-8"), end="", file=PROTOCOL_OUTPUT, flush=True)
        except (OSError, ValueError):
            pass


def backlog():
    transport = WIRE_WRITER.transport if WIRE_WRITER is not None else None
    return transport.get_write_buffer_size() if transport is not None else 0


def collapse(value):
    return " ".join(str(value or "").split())


def diagnose():
    try:
        version = importlib.metadata.version("iterm2")
    except importlib.metadata.PackageNotFoundError:
        emit("diagnostic", code="sdk_missing", python=sys.executable,
             message="Instale helper/requirements.txt em um ambiente Python local ao projeto.")
        return 2
    suite = os.environ.get("IT2_SUITE", "iTerm2")
    path = os.path.expanduser(f"~/Library/Application Support/{suite}/private/socket")
    local = os.path.exists(path)
    with socket.socket(socket.AF_UNIX if local else socket.AF_INET) as endpoint:
        endpoint.settimeout(2)
        result = endpoint.connect_ex(path if local else ("127.0.0.1", 1912))
    emit("diagnostic", code="endpoint_available" if result == 0 else "endpoint_unavailable",
         sdk=version, errno=result, transport="unix" if local else "tcp", python=sys.executable)
    return 0 if result == 0 else 3


class ProofBridge:
    def __init__(self, iterm2, connection):
        self.iterm2 = iterm2
        self.api = connection
        self.connection = str(uuid.uuid4())
        self.selected = None
        self.selection = 0
        self.stream = None
        self.identities = {}
        self.resize_records = {}
        self.inventory_lock = asyncio.Lock()
        self.inventory_ready = asyncio.Event()
        self.event_files = set()
        self.started_at = time.time()
        self.palettes = {}
        self.inventory_cache = None
        self.process_cache = {}
        self.screen_retry = None
        self.embedded = None
        self.status_seen = {}

    async def inventory(self, max_age=0.0):
        """Inventário completo; `max_age` reaproveita uma leitura recente (usado fora de caminhos de entrada)."""
        async with self.inventory_lock:
            cached = self.inventory_cache
            if max_age and cached and time.monotonic() - cached[0] < max_age:
                return cached[1], cached[2]
            app, rows = await self.read_inventory()
            self.inventory_cache = (time.monotonic(), app, rows)
            return app, rows

    async def process_info(self, pid, generation):
        """Início e linha de comando do processo em primeiro plano; cache por geração do terminal."""
        if generation in self.process_cache:
            return self.process_cache[generation]
        info = (None, "")
        try:
            result = await asyncio.to_thread(subprocess.run, ["/bin/ps", "-ww", "-p", str(pid), "-o", "lstart=,command="],
                                             capture_output=True, text=True, timeout=0.5)
            parts = result.stdout.strip().split(None, 5) if result.returncode == 0 else []
            if len(parts) >= 5:
                info = (collapse(" ".join(parts[:5])), parts[5] if len(parts) == 6 else "")
        except (OSError, subprocess.TimeoutExpired):
            pass
        if info[0]:
            self.process_cache[generation] = info
        return info

    async def describe(self, session, tab, fullscreen):
        values = dict(zip(VARIABLES, await asyncio.gather(*(session.async_get_variable(name) for name in VARIABLES))))
        generation = f'{values["creationTimeString"]}:{values["jobPid"]}:{values["tty"]}'
        identity = {"id": session.session_id, "generation": generation}
        job = str(values["jobName"] or "").rsplit("/", 1)[-1]
        try:
            valid_pid = int(values["jobPid"] or 0) > 0
        except (TypeError, ValueError):
            valid_pid = False
        title, command_line = str(values["processTitle"] or ""), str(values["commandLine"] or "")
        provider = detect_provider(job, command_line, title, "")
        process_start, command = None, ""
        idle_shell = job in SHELLS and provider is None
        if valid_pid and not idle_shell:
            process_start, command = await self.process_info(values["jobPid"], generation)
            provider = detect_provider(job, command_line, title, command)
        confirmed = bool(values["creationTimeString"] and valid_pid and str(values["tty"] or "").startswith("/dev/"))
        host = str(values["hostname"] or "")
        remote = job in ("ssh", "mosh", "mosh-client") or collapse(command).split(" ")[0].rsplit("/", 1)[-1] in ("ssh", "mosh", "mosh-client")
        local = (not bool(values["tmuxRole"]) and not remote and
                 host in ("", socket.gethostname(), socket.gethostname().split(".")[0]))
        return identity, {
            "identity": identity, "name": session.name, "provider": provider,
            "pid": str(values["jobPid"]), "processStart": process_start if provider else None, "tty": str(values["tty"]),
            "project": str(values["path"]), "tab": str(tab.tab_id),
            "columns": session.grid_size.width, "rows": session.grid_size.height,
            "singlePane": len(tab.sessions) == 1, "local": local,
            "identityConfirmed": confirmed, "fullscreen": fullscreen,
            "state": "unknown"
        }

    async def read_inventory(self):
        app = await self.iterm2.async_get_app(self.api)
        await app.async_refresh()
        pending = []
        for window in app.windows:
            fullscreen = await window.async_get_fullscreen()
            for tab in window.tabs:
                for session in tab.sessions:
                    pending.append(self.describe(session, tab, fullscreen))
        # Uma sessão que fecha durante a leitura falha ou demora: ela sai do inventário em vez de derrubá-lo.
        async def bounded(task):
            try:
                return await asyncio.wait_for(task, timeout=3)
            except Exception:
                return None
        described = [item for item in await asyncio.gather(*(bounded(task) for task in pending)) if item]
        self.identities = {identity["id"]: identity for identity, _ in described}
        rows = [row for _, row in described]
        live = {identity["generation"] for identity, _ in described}
        self.process_cache = {key: value for key, value in self.process_cache.items() if key in live}
        return app, rows

    async def watch_events(self):
        folder = os.environ.get("NOTCH_CONTROL_EVENT_DIR")
        if not folder:
            return
        from session_events import associate, read_record, transition
        await self.inventory_ready.wait()
        while True:
            try:
                _, rows = await asyncio.wait_for(self.inventory(max_age=1.0), timeout=10)
                paths = sorted(Path(folder).glob("*.json"), key=lambda path: path.stat().st_mtime)[-1000:]
                for path in paths:
                    if path.name in self.event_files:
                        continue
                    record = read_record(path)
                    if record is None:
                        continue
                    row = associate(record, rows)
                    change = transition(record)
                    if row and change and isinstance(record.get("sequence"), int):
                        emit("evidence", connection=self.connection, terminal=row["identity"], provider=row["provider"],
                             conversation=record.get("conversation"), sequence=record["sequence"], kind=change[0],
                             reason=change[1], associationProven=True, observedAt=record["recordedAt"], source="hook",
                             baseline=path.stat().st_mtime < self.started_at)
                        self.event_files.add(path.name)
                if len(self.event_files) > 2000:
                    self.event_files.intersection_update(path.name for path in paths)
            except asyncio.CancelledError:
                return
            except Exception:
                emit("diagnostic", code="state_source_unavailable")
            await asyncio.sleep(1)

    async def screen_text(self, session):
        contents = await session.async_get_screen_contents()
        width = min(220, contents.windowed_coord_range.columnRange.length or session.grid_size.width)
        rows = []
        for y in range(contents.number_of_lines):
            line = contents.line(y)
            chars = []
            for x in range(width):
                try:
                    chars.append(line.string_at(x) or " ")
                except Exception:
                    chars.append(" ")
            rows.append("".join(chars))
        return "\n".join(rows)

    def iterm_is_frontmost(self):
        """True only when iTerm2 itself is the application in front. A selected tab behind another app does not count."""
        try:
            result = subprocess.run(
                ["/usr/bin/osascript", "-e",
                 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'],
                capture_output=True, text=True, timeout=1)
        except (OSError, subprocess.TimeoutExpired):
            return False
        return result.returncode == 0 and result.stdout.strip() == "com.googlecode.iterm2"

    def focused_session(self, app):
        """Active session, and only if iTerm2 is the frontmost app. Otherwise the notch stays up."""
        if not self.iterm_is_frontmost():
            return None
        window = getattr(app, "current_window", None)
        tab = window.current_tab if window is not None else None
        session = tab.current_session if tab is not None else None
        return session.session_id if session is not None else None

    async def watch_status(self):
        """Read the visible screen of each agent once a second and publish working, waiting or idle."""
        from datetime import datetime, timezone
        from screen_status import classify, present
        from account_usage import read_usage, UsageTracker
        usage = UsageTracker()
        await self.inventory_ready.wait()
        while True:
            try:
                app, rows = await self.inventory(max_age=1.0)
                focused = self.focused_session(app)
                live = set()
                for row in rows:
                    if not row.get("provider") or not row.get("local") or not row.get("identityConfirmed"):
                        continue
                    identity = row["identity"]["id"]
                    live.add(identity)
                    session = app.get_session_by_id(identity)
                    if session is None:
                        continue
                    previous = self.status_seen.get(identity)
                    text = await self.screen_text(session)
                    windows = usage.update(row["identity"], read_usage(text, row["provider"]), time.monotonic())
                    if windows is not None:
                        emit("usage", connection=self.connection, terminal=row["identity"], windows=windows)
                    found = present(classify(text, row["provider"]), previous, identity == focused)
                    if found is None:
                        continue
                    self.status_seen[identity] = found
                    kind, reason = found
                    emit("evidence", connection=self.connection, terminal=row["identity"], provider=row["provider"],
                         sequence=time.time_ns(), kind="completed" if kind == "idle" else kind, reason=reason,
                         associationProven=True, observedAt=datetime.now(timezone.utc).isoformat(), source="screen",
                         baseline=previous is None)
                self.status_seen = {key: value for key, value in self.status_seen.items() if key in live}
                usage.retain([row["identity"] for row in rows if row["identity"]["id"] in live])
            except asyncio.CancelledError:
                return
            except Exception:
                emit("diagnostic", code="state_source_unavailable")
            await asyncio.sleep(1)

    async def history(self, request):
        session = await self.resolve(request)
        async with self.iterm2.Transaction(self.api):
            info = await session.async_get_line_info()
            end = info.overflow + info.scrollback_buffer_height
            before = request.get("before")
            if before is not None:
                if not isinstance(before, int) or isinstance(before, bool):
                    raise BridgeError("invalid_history_range")
                end = min(end, max(info.overflow, before))
            count = min(500, max(0, end - info.overflow))
            start = end - count
            lines = await session.async_get_contents(start, count) if count else []
        await self.resolve(request)
        emit("history", requestID=request.get("requestID"), connection=self.connection, terminal=self.selected,
             selection=self.selection, columns=session.grid_size.width,
             firstLine=start, hasMore=start > info.overflow,
             lines=[self.line(line, session.grid_size.width) for line in lines])

    async def resume(self, request):
        data = request.get("resume")
        if request.get("connection") != self.connection or not isinstance(data, dict):
            raise BridgeError("stale_connection")
        provider, conversation, directory = (data.get(key) for key in ("provider", "conversation", "directory"))
        if provider not in RESUME_COMMANDS or not isinstance(conversation, str):
            raise BridgeError("invalid_resume")
        try:
            conversation = str(uuid.UUID(conversation))
        except (ValueError, AttributeError):
            raise BridgeError("invalid_resume")
        if not isinstance(directory, str) or not os.path.isabs(directory) or any(c in directory for c in ("\0", "\n", "\r")) or not os.path.isdir(directory):
            raise BridgeError("directory_unavailable")
        names, arguments = RESUME_COMMANDS[provider]
        paths = ["/opt/homebrew/bin", "/usr/local/bin", str(Path.home() / ".local/bin"), str(Path.home() / ".npm-global/bin")]
        executable = next((found for found in (shutil.which(name) for name in names) if found), None)
        if not executable:
            executable = next((str(Path(path) / name) for name in names for path in paths
                               if os.path.isfile(Path(path) / name) and os.access(Path(path) / name, os.X_OK)), None)
        if not executable:
            raise BridgeError("executable_unavailable")
        app, _ = await self.inventory()
        if not app.windows:
            raise BridgeError("iterm_window_required")
        command = "cd -- " + shlex.quote(directory) + " && exec " + " ".join(shlex.quote(value) for value in (executable, *arguments, conversation))
        profile = self.iterm2.LocalWriteOnlyProfile()
        profile.set_initial_directory_mode(self.iterm2.profile.InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM)
        profile.set_custom_directory(directory)
        profile.set_use_custom_command(self.iterm2.Profile.USE_CUSTOM_COMMAND_ENABLED)
        profile.set_command("/bin/zsh -lc " + shlex.quote(command))
        tab = await app.windows[0].async_create_tab(profile_customizations=profile, select=False)
        if not tab or not tab.sessions:
            raise RuntimeError()
        emit("ack", requestID=request.get("requestID"), createdTerminal=tab.sessions[0].session_id)

    async def resolve(self, request):
        if request.get("connection") != self.connection:
            raise BridgeError("stale_connection")
        terminal = request.get("terminal")
        app, rows = await self.inventory()
        if not isinstance(terminal, dict) or self.identities.get(terminal.get("id")) != terminal:
            raise BridgeError("stale_terminal")
        if request.get("selection") != self.selection or terminal != self.selected:
            raise BridgeError("stale_selection")
        row = next((row for row in rows if row["identity"] == terminal), None)
        if row is None or not row["identityConfirmed"] or not row["local"]:
            raise BridgeError("identity_unconfirmed")
        session = app.get_session_by_id(terminal["id"])
        if session is None:
            raise BridgeError("terminal_closed")
        return session

    def color(self, value):
        if value is None:
            return None
        if value.is_rgb:
            return {"rgb": [value.rgb.red, value.rgb.green, value.rgb.blue]}
        if value.is_standard:
            return {"ansi": value.standard}
        if value.is_alternate:
            return {"alternate": value.alternate.value}
        return None

    def style(self, style):
        """Campos de estilo não padrão (fg, bg, b, i, u, v) ou None; cores padrão equivalem a ausência."""
        if not style:
            return None
        fields = {}
        for key, value in (("fg", self.color(style.fg_color)), ("bg", self.color(style.bg_color))):
            if value and value != {"alternate": 0}:
                fields[key] = value
        for key, attribute in (("b", "bold"), ("i", "italic"), ("u", "underline"), ("v", "inverse")):
            if getattr(style, attribute, False):
                fields[key] = 1
        return fields or None

    def line(self, line, columns):
        """Linha em trechos de estilo único: {"runs": [{"s": estilo?, "t": [texto por célula]}], "hardEOL": bool}.

        Uma célula por entrada em `t` preserva o endereçamento por coluna (caracteres largos deixam "" na
        coluna seguinte). Células finais vazias de estilo padrão são omitidas; a grade as trata como fundo.
        """
        runs = []
        current = None
        for x in range(columns):
            try:
                text = line.string_at(x)
            except IndexError:
                text = ""
            fields = self.style(line.style_at(x))
            key = json.dumps(fields, sort_keys=True) if fields else ""
            if current is None or current[0] != key:
                current = [key, fields, []]
                runs.append(current)
            current[2].append(text)
        while runs and runs[-1][1] is None:
            texts = runs[-1][2]
            while texts and texts[-1] in ("", " "):
                texts.pop()
            if texts:
                break
            runs.pop()
        return {"runs": [({"s": fields, "t": texts} if fields else {"t": texts}) for _, fields, texts in runs],
                "hardEOL": line.hard_eol}

    async def palette(self, session, app):
        cached = self.palettes.get(session.session_id)
        if cached and time.monotonic() - cached[0] < 2:
            return cached[1]
        try:
            profile = await session.async_get_profile()
            suffix = ""
            if profile.use_separate_colors_for_light_and_dark_mode:
                theme = await app.async_get_theme()
                suffix = "_dark" if "dark" in theme else "_light"
            def rgb(name):
                value = getattr(profile, name + suffix)
                return [round(value.red), round(value.green), round(value.blue)]
            result = {"foreground": rgb("foreground_color"), "background": rgb("background_color"),
                      "ansi": [rgb("ansi_" + str(index) + "_color") for index in range(16)]}
            self.palettes[session.session_id] = (time.monotonic(), result)
            return result
        except Exception:
            return None

    async def screen(self, session, identity, selection, contents=None):
        contents = contents or await session.async_get_screen_contents()
        app, _ = await self.inventory(max_age=2.0)
        current = app.get_session_by_id(identity["id"])
        if (self.selected != identity or self.selection != selection or current is None or
                self.identities.get(identity["id"]) != identity):
            return
        if backlog() > SCREEN_BACKLOG_LIMIT:
            self.retry_screen_later(session, identity, selection)
            return
        width = contents.windowed_coord_range.columnRange.length or current.grid_size.width
        emit("screen", connection=self.connection, terminal=identity, selection=selection,
             columns=width, rows=contents.number_of_lines,
             cursor={"x": contents.cursor_coord.x, "y": contents.cursor_coord.y},
             palette=await self.palette(session, app),
             lines=[self.line(contents.line(y), width)
                    for y in range(contents.number_of_lines)])

    def retry_screen_later(self, session, identity, selection):
        """Quadros acumulados no transporte são descartados; o estado atual é reenviado quando o leitor alcançar."""
        if self.screen_retry and not self.screen_retry.done():
            return

        async def retry():
            await asyncio.sleep(0.3)
            if self.selected == identity and self.selection == selection:
                await self.screen(session, identity, selection)
        self.screen_retry = asyncio.create_task(retry())

    async def watch(self, session, identity, selection):
        try:
            async with session.get_screen_streamer() as streamer:
                while self.selected == identity and self.selection == selection:
                    contents = await streamer.async_get(style=True)
                    if self.selected == identity and self.selection == selection:
                        await self.screen(session, identity, selection, contents)
        except asyncio.CancelledError:
            pass
        except Exception:
            emit("diagnostic", code="screen_unavailable", message="Atualize o inventário e selecione novamente.")

    async def stop_stream(self):
        if self.screen_retry:
            self.screen_retry.cancel()
            self.screen_retry = None
        if self.stream:
            self.stream.cancel()
            try:
                await self.stream
            except asyncio.CancelledError:
                pass
            self.stream = None

    async def restore_owned(self, terminal_id):
        record = self.resize_records.pop(terminal_id, None)
        if record is None:
            return False, "no_owned_resize"
        app, _ = await self.inventory()
        session = app.get_session_by_id(terminal_id)
        if session is None or self.identities.get(terminal_id) != record[0]:
            return False, "terminal_changed"
        if session.tab is None or len(session.tab.sessions) != 1 or session.window is None:
            return False, "layout_changed"
        if await session.window.async_get_fullscreen():
            return False, "layout_changed"
        current = (session.grid_size.width, session.grid_size.height)
        if current != record[2]:
            return False, "manual_resize"
        await session.async_set_grid_size(self.iterm2.Size(*record[1]))
        app, _ = await self.inventory()
        current = app.get_session_by_id(terminal_id)
        restored = current is not None and (current.grid_size.width, current.grid_size.height) == record[1]
        return restored, "restored" if restored else "restore_not_confirmed"

    def frame_from(self, request):
        values = [request.get(key) for key in ("frameX", "frameY", "frameWidth", "frameHeight")]
        if any(isinstance(value, bool) or not isinstance(value, (int, float)) for value in values):
            return None
        x, y, width, height = (int(round(value)) for value in values)
        if width < 80 or height < 80:
            return None
        return self.iterm2.Frame(self.iterm2.Point(x, y), self.iterm2.Size(width, height))

    async def place_dock(self, request):
        frame = self.frame_from(request)
        if frame is None or self.embedded is None:
            return
        app, _ = await self.inventory(max_age=1.0)
        window = next((item for item in app.windows if item.window_id == self.embedded["dock_id"]), None)
        if window is not None:
            await window.async_set_frame(frame)

    async def focus_dock(self, request):
        """Bring the docked iTerm2 window forward. It lives at normal level, under the floating header."""
        if request.get("connection") != self.connection or self.embedded is None:
            raise BridgeError("stale_connection")
        app, _ = await self.inventory(max_age=1.0)
        session = app.get_session_by_id(self.embedded["session_id"])
        if session is None:
            raise BridgeError("terminal_closed")
        await session.async_activate()
        emit("ack", requestID=request.get("requestID"))

    async def reveal(self, request):
        """Bring the iTerm2 session forward. The panel does not mirror or move it."""
        if request.get("connection") != self.connection:
            raise BridgeError("stale_connection")
        terminal = request.get("terminal")
        app, rows = await self.inventory()
        if not isinstance(terminal, dict) or self.identities.get(terminal.get("id")) != terminal:
            raise BridgeError("stale_terminal")
        row = next((item for item in rows if item["identity"] == terminal), None)
        if row is None or not row["identityConfirmed"] or not row["local"]:
            raise BridgeError("identity_unconfirmed")
        session = app.get_session_by_id(terminal["id"])
        if session is None:
            raise BridgeError("terminal_closed")
        rpc = getattr(self.iterm2, "rpc", None)
        if rpc is not None:
            # Ordering the window inside iTerm2 leaves it behind other apps. Activating the app raises it.
            await rpc.async_activate(self.api, True, True, True, session_id=session.session_id,
                                     activate_app_opts=[rpc.ACTIVATE_IGNORING_OTHER_APPS])
        else:
            await session.async_activate(select_tab=True, order_window_front=True)
        emit("ack", requestID=request.get("requestID"))

    async def undock_current(self):
        dock = self.embedded
        if dock is None:
            return
        self.embedded = None
        app, _ = await self.inventory()
        session = app.get_session_by_id(dock["session_id"])
        if session is None:
            return
        await session.async_activate()
        await asyncio.sleep(0.15)
        try:
            await self.iterm2.MainMenu.async_select_menu_item(self.api, "Window Style.Normal")
        except Exception:
            pass
        home = next((item for item in app.windows if item.window_id == dock["home_id"] and item.window_id != dock["dock_id"]), None)
        if home is not None:
            await session.async_move_to_new_tab(window=home)
            return
        window = next((item for item in app.windows if item.window_id == dock["dock_id"]), None)
        saved = dock.get("home_frame")
        if window is not None and saved:
            await window.async_set_frame(self.iterm2.Frame(self.iterm2.Point(saved[0], saved[1]), self.iterm2.Size(saved[2], saved[3])))

    async def close_placeholder(self, session_id):
        app, _ = await self.inventory()
        session = app.get_session_by_id(session_id)
        if session is not None:
            await session.async_close(force=True)

    async def dock(self, request):
        """Show the selected session in its own borderless iTerm2 window, placed over the panel card.

        A single-pane window cannot give up its only session, so a throwaway tab is added first and closed after the move.
        """
        session = await self.resolve(request)
        await self.stop_stream()
        if self.embedded and self.embedded["session_id"] != session.session_id:
            await self.undock_current()
        if self.embedded and self.embedded["session_id"] == session.session_id:
            await self.place_dock(request)
            emit("ack", requestID=request.get("requestID"), docked=True)
            return
        app, _ = await self.inventory()
        session = app.get_session_by_id(session.session_id)
        window, tab = app.get_window_and_tab_for_session(session)
        if window is None or tab is None:
            raise BridgeError("terminal_closed")
        home_frame = await window.async_get_frame()
        placeholder = None
        if len(window.tabs) == 1 and len(tab.sessions) == 1:
            profile = self.iterm2.LocalWriteOnlyProfile()
            profile.set_use_custom_command(self.iterm2.Profile.USE_CUSTOM_COMMAND_ENABLED)
            profile.set_command("/bin/sleep 3600")
            created = await window.async_create_tab(profile_customizations=profile, select=False)
            if created and created.sessions:
                placeholder = created.sessions[0].session_id
            app, _ = await self.inventory()
            session = app.get_session_by_id(session.session_id)
            window, tab = app.get_window_and_tab_for_session(session)
        dock_id = await session.async_move_to_new_window()
        self.embedded = {"session_id": session.session_id, "dock_id": dock_id, "home_id": window.window_id,
                     "home_frame": [int(home_frame.origin.x), int(home_frame.origin.y), int(home_frame.size.width), int(home_frame.size.height)]}
        if placeholder:
            try:
                await self.close_placeholder(placeholder)
            except Exception:
                pass
        app, _ = await self.inventory()
        session = app.get_session_by_id(self.embedded["session_id"])
        if session is None:
            raise BridgeError("terminal_closed")
        await session.async_activate()
        await asyncio.sleep(0.15)
        try:
            await self.iterm2.MainMenu.async_select_menu_item(self.api, "Window Style.No Title Bar")
        except Exception:
            pass
        await self.place_dock(request)
        emit("ack", requestID=request.get("requestID"), docked=True)

    async def place(self, request):
        if request.get("connection") != self.connection or self.embedded is None:
            raise BridgeError("stale_connection")
        await self.place_dock(request)
        emit("ack", requestID=request.get("requestID"), docked=True)

    async def release_selection(self):
        await self.undock_current()
        await self.stop_stream()
        if self.selected:
            await self.restore_owned(self.selected["id"])
        self.selected = None

    async def handle(self, request):
        request_id = request.get("requestID")
        kind = request.get("type")
        try:
            if request.get("version") != PROTOCOL:
                raise BridgeError("protocol_incompatible")
            if kind == "inventory":
                _, rows = await self.inventory()
                emit("inventory", requestID=request_id, connection=self.connection, terminals=rows)
                self.inventory_ready.set()
            elif kind == "history":
                await self.history(request)
            elif kind == "resume":
                await self.resume(request)
            elif kind == "dock":
                await self.dock(request)
            elif kind == "place":
                await self.place(request)
            elif kind == "focus":
                await self.focus_dock(request)
            elif kind == "reveal":
                await self.reveal(request)
            elif kind == "select":
                app, _ = await self.inventory()
                terminal = request.get("terminal")
                if (request.get("connection") != self.connection or not isinstance(terminal, dict) or
                        self.identities.get(terminal.get("id")) != terminal):
                    raise BridgeError("stale_terminal")
                selection = request.get("selection")
                if not isinstance(selection, int) or isinstance(selection, bool) or selection <= self.selection:
                    raise BridgeError("stale_selection")
                await self.release_selection()
                self.selected = terminal
                self.selection = selection
                session = app.get_session_by_id(terminal["id"])
                if session is None:
                    raise BridgeError("terminal_closed")
                await self.screen(session, terminal, selection)
                self.stream = asyncio.create_task(self.watch(session, terminal, self.selection))
                emit("ack", requestID=request_id)
            elif kind == "input":
                session = await self.resolve(request)
                if request.get("suppressBroadcast") is not True:
                    raise BridgeError("broadcast_suppression_required")
                text = request.get("text")
                if not isinstance(text, str) or len(text.encode("utf-8")) > 1024 * 1024:
                    raise BridgeError("invalid_input")
                await session.async_send_text(text, suppress_broadcast=True)
                emit("ack", requestID=request_id)
            elif kind == "resize":
                session = await self.resolve(request)
                if session.tab is None or len(session.tab.sessions) != 1:
                    raise BridgeError("resize_split_unavailable")
                if session.window is None or await session.window.async_get_fullscreen():
                    raise BridgeError("resize_fullscreen_unavailable")
                original = (session.grid_size.width, session.grid_size.height)
                size = (request.get("columns"), request.get("rows"))
                if any(not isinstance(value, int) or isinstance(value, bool) for value in size):
                    raise BridgeError("invalid_size")
                if not 2 <= size[0] <= 1000 or not 1 <= size[1] <= 500:
                    raise BridgeError("invalid_size")
                prior = self.resize_records.get(session.session_id)
                if prior and (prior[0] != self.selected or prior[2] != original):
                    self.resize_records.pop(session.session_id, None)
                    raise BridgeError("resize_ownership_lost")
                record = (self.selected.copy(), prior[1] if prior else original, size)
                self.resize_records[session.session_id] = record
                await session.async_set_grid_size(self.iterm2.Size(*size))
                app, _ = await self.inventory()
                current = app.get_session_by_id(session.session_id)
                if current is None or self.identities.get(session.session_id) != self.selected:
                    raise BridgeError("terminal_changed")
                actual = (current.grid_size.width, current.grid_size.height)
                if actual != size:
                    raise BridgeError("resize_not_confirmed")
                emit("ack", requestID=request_id, columns=actual[0], rows=actual[1])
            elif kind == "restore":
                session = await self.resolve(request)
                restored, reason = await self.restore_owned(session.session_id)
                emit("ack", requestID=request_id, restored=restored, reason=reason)
            elif kind == "unselect":
                await self.resolve(request)
                await self.release_selection()
                emit("ack", requestID=request_id)
            elif kind == "shutdown":
                await self.release_selection()
                emit("ack", requestID=request_id)
                return False
            else:
                raise BridgeError("unsupported_operation")
        except BridgeError as error:
            emit("error", requestID=request_id, code=str(error))
        except Exception:
            emit("error", requestID=request_id, code="api_operation_failed", ambiguous=kind in ("input", "resize", "resume"))
        return True

    async def run(self, peer=None):
        global WIRE_WRITER
        if peer is not None:
            reader, WIRE_WRITER = await asyncio.open_connection(sock=peer, limit=2 * 1024 * 1024)
        else:
            reader = asyncio.StreamReader(limit=2 * 1024 * 1024)
            protocol = asyncio.StreamReaderProtocol(reader)
            await asyncio.get_running_loop().connect_read_pipe(lambda: protocol, sys.stdin)
        emit("connected", connection=self.connection, sdk=importlib.metadata.version("iterm2"))
        event_task = asyncio.create_task(self.watch_events())
        status_task = asyncio.create_task(self.watch_status())
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    request = json.loads(line)
                    if not isinstance(request, dict):
                        raise ValueError()
                except (ValueError, UnicodeDecodeError):
                    emit("error", code="invalid_message")
                    continue
                try:
                    keep_running = await asyncio.wait_for(self.handle(request), timeout=10)
                except asyncio.TimeoutError:
                    emit("error", requestID=request.get("requestID"), code="operation_timeout",
                         ambiguous=request.get("type") in ("input", "resize", "resume", "restore"))
                    continue
                if not keep_running:
                    break
        finally:
            event_task.cancel()
            status_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await event_task
            with contextlib.suppress(asyncio.CancelledError):
                await status_task
            try:
                await self.release_selection()
                for terminal_id in list(self.resize_records):
                    await self.restore_owned(terminal_id)
            except Exception:
                emit("diagnostic", code="restore_unavailable",
                     message="A conexão encerrou antes da restauração. Confira a grade no iTerm2.")
            if WIRE_WRITER is not None:
                writer, WIRE_WRITER = WIRE_WRITER, None
                with contextlib.suppress(Exception):
                    await asyncio.wait_for(writer.drain(), timeout=2)
                writer.close()


def serve(socket_path=None):
    global PROTOCOL_OUTPUT
    server = None
    peer = None
    if socket_path:
        try:
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server.bind(socket_path)
            os.chmod(socket_path, 0o600)
            server.listen(1)
            server.settimeout(5)
            emit("socket_ready")
            peer, _ = server.accept()
            PROTOCOL_OUTPUT = peer.makefile("w", encoding="utf-8")
        except OSError:
            emit("diagnostic", code="local_transport_unavailable")
            if server:
                server.close()
            return 3
    try:
        import iterm2
    except ImportError:
        emit("diagnostic", code="sdk_missing", message="Instale helper/requirements.txt no Python selecionado.")
        return 2
    try:
        async def connected(connection):
            await ProofBridge(iterm2, connection).run(peer)
        with open(os.devnull, "w") as quiet:
            with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                iterm2.run_until_complete(connected, retry=False, debug=False)
        return 0
    except (Exception, SystemExit):
        emit("diagnostic", code="connection_unavailable",
             message="Abra iTerm2, habilite a API e autorize este script quando solicitado pelo iTerm2.")
        return 3


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--diagnose", action="store_true")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--socket")
    args = parser.parse_args()
    if args.diagnose:
        return diagnose()
    if args.serve:
        try:
            return serve(args.socket)
        finally:
            if args.socket and os.path.exists(args.socket):
                os.unlink(args.socket)
    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
