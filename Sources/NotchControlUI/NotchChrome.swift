import NotchControlCore
import SwiftUI

public enum NotchMetrics {
    public static var cellHeight: CGFloat { DesignTokens.iconSize }
    /// Ten sessions fit before the list scrolls.
    public static let maximumHeight: CGFloat = 864
    /// Task titles column the inner tab opens beside the bubbles.
    public static let titlesWidth: CGFloat = 230
    /// Tab on the inner side of the notch: how far it sticks out and how tall it is.
    public static let tabDepth: CGFloat = 14
    public static let tabHeight: CGFloat = 60
    /// Space between the top flare and the document icon. It holds the pin; without the pin the glyph sits as far from the top
    /// as the last bubble does from the bottom, which takes the icon's own margin into account.
    public static func topPadding(pin: Bool) -> CGFloat { pin ? DesignTokens.topPadding : DesignTokens.regular }
    /// A divider is a 1 pt line that takes one more cell spacing between the rows around it.
    public static func contentHeight(sessions: Int, dividers: Int = 0, pin: Bool = true) -> CGFloat {
        let rows = CGFloat(max(0, sessions)) * cellHeight + CGFloat(max(0, sessions - 1)) * DesignTokens.cellSpacing
            + CGFloat(max(0, dividers)) * (1 + DesignTokens.cellSpacing)
        let fixed = 2 * DesignTokens.flare + topPadding(pin: pin) + DesignTokens.iconSize + 33 + DesignTokens.bottomPadding + (sessions > 0 ? 8 : 0)
        return fixed + rows
    }
    public static func height(sessions: Int, dividers: Int = 0, available: CGFloat, pin: Bool = true) -> CGFloat {
        min(max(0, available), min(maximumHeight, contentHeight(sessions: sessions, dividers: dividers, pin: pin)))
    }
    public static func needsScrolling(sessions: Int, dividers: Int = 0, available: CGFloat, pin: Bool = true) -> Bool {
        sessions > 0 && contentHeight(sessions: sessions, dividers: dividers, pin: pin)
            > height(sessions: sessions, dividers: dividers, available: available, pin: pin)
    }
}

public enum NotchMotion {
    public static let duration: TimeInterval = 0.28
    public static var animation: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    public static var sessionTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.86)).combined(with: .offset(y: 8))
    }
}

/// The notch body against the screen edge, with flares into the edge and an optional tab sticking out of the inner side.
public struct SideNotchShape: Shape {
    public var edge: PanelEdge
    public var folded: Bool
    public var tab: CGFloat
    public var tabHeight: CGFloat
    public init(edge: PanelEdge, folded: Bool = false, tab: CGFloat = 0, tabHeight: CGFloat = 0) {
        self.edge = edge; self.folded = folded; self.tab = tab; self.tabHeight = tabHeight
    }
    public func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        let left = min(max(0, tab), width / 2), body = width - left
        let corner = min(folded ? body / 2 : DesignTokens.notchRadius, body / 2, height / 4)
        let flare = min(folded ? body / 2 : DesignTokens.flare, body - corner, height / 4)
        let reach: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: width, y: 0))
        p.addCurve(to: CGPoint(x: width - flare, y: flare), control1: CGPoint(x: width, y: flare * reach), control2: CGPoint(x: width - flare + flare * reach, y: flare))
        p.addLine(to: CGPoint(x: left + corner, y: flare))
        p.addCurve(to: CGPoint(x: left, y: flare + corner), control1: CGPoint(x: left + corner * (1 - reach), y: flare), control2: CGPoint(x: left, y: flare + corner * (1 - reach)))
        let bump = min(tabHeight, height - 2 * (flare + corner))
        if left > 0, bump > 2 * left {
            // S-curves keep the tab tangent to the body, like the flares.
            let top = height / 2 - bump / 2, bottom = height / 2 + bump / 2
            p.addLine(to: CGPoint(x: left, y: top))
            p.addCurve(to: CGPoint(x: 0, y: top + left), control1: CGPoint(x: left, y: top + left * reach), control2: CGPoint(x: 0, y: top + left * (1 - reach)))
            p.addLine(to: CGPoint(x: 0, y: bottom - left))
            p.addCurve(to: CGPoint(x: left, y: bottom), control1: CGPoint(x: 0, y: bottom - left * (1 - reach)), control2: CGPoint(x: left, y: bottom - left * reach))
        }
        p.addLine(to: CGPoint(x: left, y: height - flare - corner))
        p.addCurve(to: CGPoint(x: left + corner, y: height - flare), control1: CGPoint(x: left, y: height - flare - corner * (1 - reach)), control2: CGPoint(x: left + corner * (1 - reach), y: height - flare))
        p.addLine(to: CGPoint(x: width - flare, y: height - flare))
        p.addCurve(to: CGPoint(x: width, y: height), control1: CGPoint(x: width - flare + flare * reach, y: height - flare), control2: CGPoint(x: width, y: height - flare * reach))
        p.closeSubpath()
        if edge == .left { p = p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)) }
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
