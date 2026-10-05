import importlib.util
from pathlib import Path
import runpy
import sys

import iterm2

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("terminal_transport_fixture", Path(__file__).parent / "iterm2/__init__.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def screen(session):
    proto = iterm2.api_pb2.GetBufferResponse()
    proto.windowed_coord_range.columns.length = session.grid_size.width
    proto.cursor.x = 1
    proto.cursor.y = 0
    for text in ("A",):
        line = proto.contents.add(text=text)
        line.code_points_per_cell.add(num_code_points=1, repeats=1)
        line.style.add(repeats=1)
    return iterm2.screen.ScreenContents(proto)


fixture.Screen = screen
iterm2.async_get_app = fixture.async_get_app
iterm2.run_until_complete = fixture.run_until_complete
sys.argv = [str(ROOT / "helper/proof_bridge.py"), "--serve"]
runpy.run_path(sys.argv[0], run_name="__main__")
