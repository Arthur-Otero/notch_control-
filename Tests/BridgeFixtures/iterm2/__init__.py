import asyncio
import json
import os
import sys
from types import SimpleNamespace


def effect(method, **values):
    print(json.dumps({"type": "fixture_effect", "method": method, **values}), file=sys.__stdout__, flush=True)


class Size:
    def __init__(self, width, height):
        self.width = width
        self.height = height


def styled(x):
    """Estilo diferente a cada célula: pior caso para o tamanho das mensagens."""
    color = SimpleNamespace(is_rgb=True, rgb=SimpleNamespace(red=x % 256, green=(x * 7) % 256, blue=(x * 13) % 256),
                            is_standard=False, is_alternate=False)
    return SimpleNamespace(fg_color=color, bg_color=None, bold=bool(x % 2), italic=False, underline=False, inverse=False)


class Screen:
    number_of_lines = 2
    cursor_coord = SimpleNamespace(x=1, y=0)

    def __init__(self, session):
        self.windowed_coord_range = SimpleNamespace(columnRange=SimpleNamespace(length=session.grid_size.width))

    def line(self, y):
        if os.environ.get("NOTCH_CONTROL_FIXTURE_STYLED") == "1":
            return SimpleNamespace(string_at=lambda x: chr(65 + x % 26), style_at=styled, hard_eol=True)
        return SimpleNamespace(string_at=lambda x: "x" if x == 0 else " ",
                               style_at=lambda x: None, hard_eol=True)


class Stream:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def async_get(self, style=False):
        await asyncio.Event().wait()


class Session:
    def __init__(self, identity, pid):
        self.session_id = identity
        self.name = identity
        self.pid = pid
        self.grid_size = Size(80, 24)
        self.tab = None
        self.window = None
        self.manual_countdown = None

    async def async_get_variable(self, name):
        if os.environ.get("NOTCH_CONTROL_FIXTURE_CLOSING_SESSION") == "1" and self.session_id == "t2":
            raise RuntimeError("NOT_FOUND")  # sessão fechada entre a enumeração e a leitura
        values = {"jobPid": self.pid, "tty": "/dev/test-" + self.session_id,
                  "creationTimeString": "created", "jobName": "codex", "path": "/test/project",
                  "hostname": "", "tmuxRole": ""}
        if os.environ.get("NOTCH_CONTROL_FIXTURE_AGENTS") == "1":
            # Valores observados no iTerm2 3.7.3: Claude Code (binário nomeado pela versão), Cursor Agent (node) e um shell.
            values.update({
                "t1": {"jobName": "2.1.288", "commandLine": "claude", "processTitle": "claude"},
                "t2": {"jobName": "node", "processTitle": "agent",
                       "commandLine": "agent --use-system-ca /Users/me/.local/share/cursor-agent/versions/1/index.js"},
                "t3": {"jobName": "zsh", "commandLine": "-zsh", "processTitle": "zsh"},
            }.get(self.session_id, {}))
        return values.get(name, "")

    async def async_get_screen_contents(self):
        return Screen(self)

    async def async_get_line_info(self):
        return SimpleNamespace(overflow=50 if os.environ.get("NOTCH_CONTROL_FIXTURE_BIG_HISTORY") == "1" else 0,
                               scrollback_buffer_height=1200 if os.environ.get("NOTCH_CONTROL_FIXTURE_BIG_HISTORY") == "1" else 2)

    async def async_get_contents(self, first_line, number_of_lines):
        return [Screen(self).line(0) for _ in range(number_of_lines)]

    def get_screen_streamer(self):
        return Stream()

    async def async_send_text(self, text, suppress_broadcast=False):
        if os.environ.get("NOTCH_CONTROL_FIXTURE_INPUT_FAIL") == "1":
            raise ValueError("PRIVATE-TOOL-MESSAGE")
        effect("send_text", terminal=self.session_id, text=text, suppressBroadcast=suppress_broadcast)
        if os.environ.get("NOTCH_CONTROL_FIXTURE_INPUT_STALL") == "1":
            await asyncio.Event().wait()

    async def async_activate(self, select_tab=True, order_window_front=True):
        effect("activate", terminal=self.session_id, orderFront=order_window_front)

    async def async_close(self, force=False):
        effect("close", terminal=self.session_id, force=force)
        for window in list(app.windows):
            for tab in list(window.tabs):
                if self in tab.sessions:
                    tab.sessions.remove(self)
                    if not tab.sessions:
                        window.tabs.remove(tab)
            if not window.tabs:
                app.windows.remove(window)

    async def async_move_to_new_window(self):
        effect("move_to_new_window", terminal=self.session_id)
        for window in list(app.windows):
            for tab in list(window.tabs):
                if self in tab.sessions:
                    tab.sessions.remove(self)
                    if not tab.sessions:
                        window.tabs.remove(tab)
        dock = Window([SimpleNamespace(tab_id="dock-" + self.session_id, sessions=[self])])
        dock.window_id = "dock-" + self.session_id
        self.window = dock
        app.windows.append(dock)
        return dock.window_id

    async def async_move_to_new_tab(self, window=None):
        effect("move_to_new_tab", terminal=self.session_id, window=getattr(window, "window_id", None))
        app.windows = [item for item in app.windows if item.window_id != "dock-" + self.session_id]
        if window is not None:
            window.tabs.append(SimpleNamespace(tab_id="back-" + self.session_id, sessions=[self]))
            self.window = window
        return "back"

    async def async_set_grid_size(self, size):
        self.grid_size = size
        effect("resize", terminal=self.session_id, columns=size.width, rows=size.height)
        if os.environ.get("NOTCH_CONTROL_FIXTURE_MANUAL_RESIZE") == "1":
            self.manual_countdown = 1


class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y


class Frame:
    def __init__(self, origin, size):
        self.origin = origin
        self.size = size


class MainMenu:
    @staticmethod
    async def async_select_menu_item(connection, identifier):
        effect("menu", identifier=identifier)


class Window:
    def __init__(self, tabs):
        self.tabs = tabs
        self.window_id = "window-%s" % id(self)
        self.frame = SimpleNamespace(origin=SimpleNamespace(x=0, y=0), size=SimpleNamespace(width=800, height=600))

    async def async_get_frame(self):
        return self.frame

    async def async_set_frame(self, frame):
        self.frame = frame
        effect("set_frame", x=frame.origin.x, y=frame.origin.y, width=frame.size.width, height=frame.size.height)

    async def async_create_tab(self, profile_customizations=None, select=True):
        effect('create_tab', profile={key: json.loads(value) for key, value in profile_customizations.values.items()}, select=select)
        session = Session('t3', 900103)
        tab = SimpleNamespace(tab_id='tab3', sessions=[session])
        session.tab = tab
        session.window = self
        self.tabs.append(tab)
        app.sessions.append(session)
        if os.environ.get("NOTCH_CONTROL_FIXTURE_EMPTY_TAB_RECEIPT") == "1":
            return None
        return tab

    async def async_get_fullscreen(self):
        return os.environ.get("NOTCH_CONTROL_FIXTURE_FULLSCREEN") == "1"


class App:
    def __init__(self):
        self.sessions = [Session("t1", 900101), Session("t2", 900102)]
        if os.environ.get("NOTCH_CONTROL_FIXTURE_AGENTS") == "1":
            self.sessions.append(Session("t3", 900103))
        if os.environ.get("NOTCH_CONTROL_FIXTURE_SPLIT") == "1":
            tabs = [SimpleNamespace(tab_id="tab1", sessions=self.sessions)]
        else:
            tabs = [SimpleNamespace(tab_id="tab" + str(index), sessions=[session])
                    for index, session in enumerate(self.sessions)]
        window = Window(tabs)
        self.windows = [window]
        for tab in tabs:
            for session in tab.sessions:
                session.tab = tab
                session.window = window

    async def async_refresh(self):
        for session in self.sessions:
            if session.manual_countdown is not None:
                if session.manual_countdown == 0:
                    session.grid_size = Size(95, 31)
                    session.manual_countdown = None
                else:
                    session.manual_countdown -= 1

    def get_session_by_id(self, identity):
        return next((session for session in self.sessions if session.session_id == identity), None)

    def get_window_and_tab_for_session(self, session):
        for window in self.windows:
            for tab in window.tabs:
                if session in tab.sessions:
                    return window, tab
        return None, None


app = App()


async def async_get_app(connection):
    return app


def run_until_complete(coro, retry=False, debug=False):
    asyncio.run(coro("fixture_connection"))

class Transaction:
    def __init__(self, connection):
        self.connection = connection
    async def __aenter__(self):
        return self
    async def __aexit__(self, *args):
        return False
