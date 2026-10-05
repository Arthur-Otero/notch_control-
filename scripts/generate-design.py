import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'docs' / 'DESIGN.md').read_text().split('---', 2)[1]
colors = re.findall(r'^  (\w+): "(#[0-9A-Fa-f]{6})"$', source, re.M)
numbers = {}
stack = []
for line in source.splitlines():
    match = re.fullmatch(r'( *)([\w]+):(?: "([0-9]+)px")?', line)
    if not match:
        continue
    depth = len(match[1]) // 2
    stack = stack[:depth] + [match[2]]
    if match[3]:
        numbers['.'.join(stack)] = match[3]
text = 'import SwiftUI\n\npublic enum DesignTokens {\n'
for name, value in colors:
    text += f'    public static let {name} = color(0x{value[1:]})\n'
for name, key in [('railWidth', 'components.notchRail.width'), ('iconSize', 'components.sessionIcon.width'), ('pillWidth', 'components.notchPill.width'), ('pillHeight', 'components.notchPill.height'), ('notchRadius', 'rounded.notch'), ('controlRadius', 'rounded.control'), ('compact', 'spacing.compact'), ('regular', 'spacing.regular'), ('content', 'spacing.content'), ('fontSize', 'typography.sans.fontSize'), ('cellHeight', 'typography.mono.lineHeight')]:
    text += f'    public static let {name}: CGFloat = {numbers[key]}\n'
text += f'    public static let tooltipWidth: CGFloat = {numbers["components.tooltip.width"]}\n'
text += f'    public static let tooltipTail: CGFloat = {numbers["spacing.tooltipTail"]}\n'
for name in ['flare', 'topPadding', 'bottomPadding', 'cellSpacing', 'trackStroke', 'activityStroke', 'glyphSize']:
    text += f'    public static let {name}: CGFloat = {numbers["spacing.notch" + name[0].upper() + name[1:]]}\n'
text += '''    private static func color(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
'''
target = ROOT / 'Sources/NotchControlUI/DesignTokens.swift'
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if args.check:
    sys.exit(0 if target.exists() and target.read_text() == text else 1)
target.write_text(text)
