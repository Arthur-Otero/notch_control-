import AppKit
import NotchControlCore
import SwiftUI

public struct RailDragHandle: NSViewRepresentable {
    public var label: String
    public var onBegin: (RailPoint) -> Void
    public var onMove: (RailPoint) -> Void
    public var onEnd: (RailPoint) -> Void
    public var onClick: () -> Void
    public var horizontalResize: Bool
    public var onAdjust: (Int) -> Void
    public var contextTitle: String?
    public var onContext: () -> Void
    public var exposesAccessibility: Bool
    public var hint: String?
    public init(label: String, onBegin: @escaping (RailPoint) -> Void, onMove: @escaping (RailPoint) -> Void,
                onEnd: @escaping (RailPoint) -> Void, onClick: @escaping () -> Void = {}, horizontalResize: Bool = false,
                onAdjust: @escaping (Int) -> Void = { _ in }, contextTitle: String? = nil, onContext: @escaping () -> Void = {},
                exposesAccessibility: Bool = true, hint: String? = nil) {
        self.label = label; self.onBegin = onBegin; self.onMove = onMove; self.onEnd = onEnd; self.onClick = onClick
        self.horizontalResize = horizontalResize
        self.onAdjust = onAdjust
        self.contextTitle = contextTitle; self.onContext = onContext
        self.exposesAccessibility = exposesAccessibility; self.hint = hint
    }
    public func makeNSView(context: Context) -> RailDragHandleView { RailDragHandleView() }
    public func updateNSView(_ view: RailDragHandleView, context: Context) {
        view.onBegin = onBegin; view.onMove = onMove; view.onEnd = onEnd; view.onClick = onClick
        view.horizontalResize = horizontalResize
        view.onAdjust = onAdjust
        view.contextTitle = contextTitle; view.onContext = onContext
        view.toolTip = hint
        view.allowsFocus = exposesAccessibility
        if exposesAccessibility {
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(horizontalResize ? .splitter : .button)
            view.setAccessibilityLabel(label)
        } else {
            view.setAccessibilityElement(false)
        }
    }
}

@MainActor
public final class RailDragHandleView: NSView {
    var onBegin: (RailPoint) -> Void = { _ in }
    var onMove: (RailPoint) -> Void = { _ in }
    var onEnd: (RailPoint) -> Void = { _ in }
    var onClick: () -> Void = {}
    var horizontalResize = false
    var onAdjust: (Int) -> Void = { _ in }
    var contextTitle: String?
    var onContext: () -> Void = {}
    var allowsFocus = true
    public override init(frame: NSRect) { super.init(frame: frame); focusRingType = .none }
    public required init?(coder: NSCoder) { super.init(coder: coder); focusRingType = .none }
    public override var focusRingType: NSFocusRingType {
        get { .none }
        set { super.focusRingType = .none }
    }
    public override var acceptsFirstResponder: Bool { allowsFocus }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override func resetCursorRects() { addCursorRect(bounds, cursor: horizontalResize ? .resizeLeftRight : .openHand) }
    public override func rightMouseDown(with event: NSEvent) {
        guard let contextTitle, !contextTitle.isEmpty else { super.rightMouseDown(with: event); return }
        let menu = NSMenu()
        let item = NSMenuItem(title: contextTitle, action: #selector(performContext), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc func performContext() { onContext() }
    public override func accessibilityPerformPress() -> Bool { guard !horizontalResize else { return false }; onClick(); return true }
    public override func accessibilityPerformIncrement() -> Bool { guard horizontalResize else { return false }; onAdjust(1); return true }
    public override func accessibilityPerformDecrement() -> Bool { guard horizontalResize else { return false }; onAdjust(-1); return true }
    public override func keyDown(with event: NSEvent) {
        if horizontalResize, [123, 124].contains(event.keyCode) { onAdjust(event.keyCode == 123 ? -1 : 1) }
        else if !horizontalResize, [36, 49, 76].contains(event.keyCode) { onClick() }
        else { super.keyDown(with: event) }
    }
    public override func mouseDown(with event: NSEvent) {
        guard let trackingWindow = window else { return }
        let begin = NSEvent.mouseLocation
        var gesture = RailPointerGesture()
        gesture.press(RailPoint(x: begin.x, y: begin.y))
        (horizontalResize ? NSCursor.resizeLeftRight : NSCursor.closedHand).push()
        defer { NSCursor.pop() }
        // Keep the original window's event stream even when moving replaces the SwiftUI view.
        while let next = trackingWindow.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let pointer = NSEvent.mouseLocation
            let point = RailPoint(x: pointer.x, y: pointer.y)
            let actions = next.type == .leftMouseUp ? gesture.release(point) : gesture.move(point)
            for action in actions {
                switch action {
                case .began(let point): onBegin(point)
                case .moved(let point): onMove(point)
                case .ended(let point): onEnd(point)
                case .clicked: onClick()
                }
            }
            if next.type == .leftMouseUp { return }
        }
        onEnd(RailPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y))
    }
}
