from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / 'assets/AppIcon.png'
RGBA_COLOR_TYPE = 6


class AppIconTests(unittest.TestCase):
    def testMasterIsTransparent1024Square(self):
        header = MASTER.read_bytes()[:33]
        self.assertEqual(header[:8], b'\x89PNG\r\n\x1a\n')
        width, height, depth, color_type = struct.unpack('>IIBB', header[16:26])
        self.assertEqual((width, height, depth, color_type), (1024, 1024, 8, RGBA_COLOR_TYPE))

    def testIcnsCarriesEverySizeTheFinderAsksFor(self):
        with tempfile.TemporaryDirectory(prefix='NotchControl icon ') as folder:
            icns = Path(folder) / 'NotchControl.icns'
            subprocess.run(['/bin/bash', str(ROOT / 'scripts/make-icns.sh'), str(MASTER), str(icns)],
                           check=True, capture_output=True, text=True, timeout=60)
            self.assertEqual(icns.read_bytes()[:4], b'icns')
            iconset = Path(folder) / 'roundtrip.iconset'
            subprocess.run(['iconutil', '--convert', 'iconset', '--output', str(iconset), str(icns)],
                           check=True, capture_output=True, text=True, timeout=60)
            names = {path.name for path in iconset.iterdir()}
            expected = {f'icon_{size}x{size}{scale}.png' for size in (16, 32, 128, 256, 512) for scale in ('', '@2x')}
            self.assertEqual(names, expected)

    def testBundlePlistPointsToTheIcon(self):
        with tempfile.TemporaryDirectory(prefix='NotchControl plist ') as folder:
            plist = Path(folder) / 'Info.plist'
            subprocess.run(['python3', str(ROOT / 'scripts/app-plist.py'), str(plist), str(ROOT)],
                           check=True, capture_output=True, text=True, timeout=30)
            self.assertEqual(plistlib.loads(plist.read_bytes())['CFBundleIconFile'], 'NotchControl')
