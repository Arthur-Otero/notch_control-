import SwiftUI

public enum DesignTokens {
    public static let primary = color(0xB4C9F5)
    public static let background = color(0x101114)
    public static let surface = color(0x1B1D22)
    public static let hover = color(0x292C33)
    public static let border = color(0x454954)
    public static let text = color(0xF3F4F6)
    public static let muted = color(0xB6BAC4)
    public static let danger = color(0xFF6B73)
    public static let warning = color(0xFFC94D)
    public static let unknown = color(0x969CAA)
    public static let focus = color(0x88B8FF)
    public static let notch = color(0x000000)
    public static let ringTrack = color(0x303030)
    public static let contextTrack = color(0x4A4A4A)
    public static let notchInk = color(0xFFFFFF)
    public static let activity = color(0x00FF88)
    public static let railWidth: CGFloat = 70
    public static let iconSize: CGFloat = 44
    public static let pillWidth: CGFloat = 10
    public static let pillHeight: CGFloat = 79
    public static let notchRadius: CGFloat = 30
    public static let controlRadius: CGFloat = 6
    public static let compact: CGFloat = 6
    public static let regular: CGFloat = 10
    public static let content: CGFloat = 16
    public static let fontSize: CGFloat = 13
    public static let cellHeight: CGFloat = 18
    public static let tooltipWidth: CGFloat = 300
    public static let tooltipTail: CGFloat = 14
    public static let flare: CGFloat = 39
    public static let topPadding: CGFloat = 26
    public static let bottomPadding: CGFloat = 19
    public static let cellSpacing: CGFloat = 22
    public static let trackStroke: CGFloat = 6
    public static let activityStroke: CGFloat = 3
    public static let glyphSize: CGFloat = 18
    private static func color(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
