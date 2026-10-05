import Foundation

public enum PanelEdge: String, Codable, Sendable { case left, right }
public struct ScreenArea: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
public struct PanelLayout: Sendable {
    public let content: ScreenArea
    public let minimumWidth: Double
    public let maximumWidth: Double
    public init(screen: ScreenArea, edge: PanelEdge, preferredWidth: Double, railWidth: Double) {
        let rail = min(max(0, railWidth), max(0, screen.width))
        maximumWidth = max(0, min(screen.width * 0.8, screen.width - rail))
        minimumWidth = min(360, maximumWidth)
        let width = min(max(preferredWidth.isFinite ? preferredWidth : 560, minimumWidth), maximumWidth)
        content = ScreenArea(x: edge == .left ? screen.x : screen.x + screen.width - width,
                             y: screen.y, width: width, height: max(0, screen.height))
    }
    public static func shouldClose(draggedWidth: Double) -> Bool { draggedWidth <= 24 }
}
