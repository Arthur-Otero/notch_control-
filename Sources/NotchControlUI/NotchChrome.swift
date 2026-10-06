import NotchControlCore
import SwiftUI

public enum NotchMetrics {
    public static var cellHeight: CGFloat { DesignTokens.iconSize }
    /// Ten sessions fit before the list scrolls.
    public static let maximumHeight: CGFloat = 864
    /// A divider is a 1 pt line that takes one more cell spacing between the rows around it.
    public static func contentHeight(sessions: Int, dividers: Int = 0) -> CGFloat {
        let rows = CGFloat(max(0, sessions)) * cellHeight + CGFloat(max(0, sessions - 1)) * DesignTokens.cellSpacing
            + CGFloat(max(0, dividers)) * (1 + DesignTokens.cellSpacing)
        let fixed = 2 * DesignTokens.flare + DesignTokens.topPadding + DesignTokens.iconSize + 33 + DesignTokens.bottomPadding + (sessions > 0 ? 8 : 0)
        return fixed + rows
    }
    public static func height(sessions: Int, dividers: Int = 0, available: CGFloat) -> CGFloat {
        min(max(0, available), min(maximumHeight, contentHeight(sessions: sessions, dividers: dividers)))
    }
    public static func needsScrolling(sessions: Int, dividers: Int = 0, available: CGFloat) -> Bool {
        sessions > 0 && contentHeight(sessions: sessions, dividers: dividers) > height(sessions: sessions, dividers: dividers, available: available)
    }
}

public enum NotchMotion {
    public static let duration: TimeInterval = 0.28
    public static var animation: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    public static var sessionTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.86)).combined(with: .offset(y: 8))
    }
}

public struct SideNotchShape: Shape {
    public var edge: PanelEdge
    public var folded: Bool
    public init(edge: PanelEdge, folded: Bool = false) { self.edge = edge; self.folded = folded }
    public func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        let corner = min(folded ? width / 2 : DesignTokens.notchRadius, width / 2, height / 4)
        let flare = min(folded ? width / 2 : DesignTokens.flare, width - corner, height / 4)
        let reach: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: width, y: 0))
        p.addCurve(to: CGPoint(x: width - flare, y: flare), control1: CGPoint(x: width, y: flare * reach), control2: CGPoint(x: width - flare + flare * reach, y: flare))
        p.addLine(to: CGPoint(x: corner, y: flare))
        p.addCurve(to: CGPoint(x: 0, y: flare + corner), control1: CGPoint(x: corner * (1 - reach), y: flare), control2: CGPoint(x: 0, y: flare + corner * (1 - reach)))
        p.addLine(to: CGPoint(x: 0, y: height - flare - corner))
        p.addCurve(to: CGPoint(x: corner, y: height - flare), control1: CGPoint(x: 0, y: height - flare - corner * (1 - reach)), control2: CGPoint(x: corner * (1 - reach), y: height - flare))
        p.addLine(to: CGPoint(x: width - flare, y: height - flare))
        p.addCurve(to: CGPoint(x: width, y: height), control1: CGPoint(x: width - flare + flare * reach, y: height - flare), control2: CGPoint(x: width, y: height - flare * reach))
        p.closeSubpath()
        if edge == .left { p = p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)) }
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
