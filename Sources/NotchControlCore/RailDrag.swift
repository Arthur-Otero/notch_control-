public struct RailPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct RailPlacement: Equatable, Sendable {
    public let screenID: UInt32?
    public let edge: PanelEdge
    public let position: Double
    public init(screenID: UInt32?, edge: PanelEdge, position: Double) {
        self.screenID = screenID; self.edge = edge; self.position = position
    }
}

public struct RailDrag: Sendable {
    private let grabOffsetY: Double
    public init(pointer: RailPoint, centerY: Double) { grabOffsetY = pointer.y - centerY }

    public func placement(pointer: RailPoint, screenID: UInt32?, area: ScreenArea, height: Double) -> RailPlacement {
        let halfHeight = min(max(0, height), max(0, area.height)) / 2
        let center = min(area.y + area.height - halfHeight, max(area.y + halfHeight, pointer.y - grabOffsetY))
        return RailPlacement(screenID: screenID, edge: pointer.x < area.x + area.width / 2 ? .left : .right,
                             position: min(1, max(0, (center - area.y) / max(1, area.height))))
    }
}

public enum RailPointerAction: Equatable, Sendable {
    case began(RailPoint), moved(RailPoint), ended(RailPoint), clicked
}

public struct RailPointerGesture: Sendable {
    private var origin: RailPoint?
    private var dragging = false
    public init() {}
    public mutating func press(_ point: RailPoint) { origin = point; dragging = false }
    public mutating func move(_ point: RailPoint) -> [RailPointerAction] {
        guard let origin else { return [] }
        if !dragging {
            guard (point.x - origin.x) * (point.x - origin.x) + (point.y - origin.y) * (point.y - origin.y) >= 9 else { return [] }
            dragging = true
            return [.began(origin), .moved(point)]
        }
        return [.moved(point)]
    }
    public mutating func release(_ point: RailPoint) -> [RailPointerAction] {
        guard origin != nil else { return [] }
        let updates = move(point)
        let end: RailPointerAction = dragging ? .ended(point) : .clicked
        origin = nil; dragging = false
        return updates + [end]
    }
}

public enum RailGeometry {
    public static func frame(area: ScreenArea, edge: PanelEdge, position: Double, width: Double, height: Double) -> ScreenArea {
        let width = min(max(0, width), max(0, area.width))
        let height = min(max(0, height), max(0, area.height))
        let center = area.y + area.height * (position.isFinite ? min(1, max(0, position)) : 0.5)
        return ScreenArea(x: edge == .left ? area.x : area.x + area.width - width,
                          y: min(area.y + area.height - height, max(area.y, center - height / 2)), width: width, height: height)
    }
}
