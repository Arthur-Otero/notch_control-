from pathlib import Path
import plistlib
import sys

values = {'CFBundleName': 'NotchControl', 'CFBundleDisplayName': 'NotchControl', 'CFBundleExecutable': 'NotchControl',
          'CFBundleIdentifier': 'local.notchcontrol.app', 'CFBundlePackageType': 'APPL',
          'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': '15.0',
          'LSUIElement': True, 'NSHighResolutionCapable': True, 'NotchControlProject': sys.argv[2]}
Path(sys.argv[1]).write_bytes(plistlib.dumps(values))
