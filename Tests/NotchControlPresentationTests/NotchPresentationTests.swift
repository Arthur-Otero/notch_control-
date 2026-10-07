import AppKit
import NotchControlCore
import SwiftUI
import XCTest
@testable import NotchControl
@testable import NotchControlUI

final class NotchPresentationTests: XCTestCase {
    @MainActor
    func testOpeningShortNotchDoesNotShowAScrollbarButOverflowRemainsScrollable() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "Requires access to the macOS window server")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = folder.appendingPathComponent(".notchcontrol")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for count in [0, 1, 3, 12] {
            var registry = AgentRegistry()
            registry.reconcile((0..<count).map {
                AgentCandidate(terminal: .init(id: "session-\($0)", generation: "test"),
                               provider: .claude, project: "/project", name: "Claude")
            })
            try JSONEncoder().encode(registry).write(to: state.appendingPathComponent("sessions.json"))
            let store = AppStore(project: folder)
            defer { store.work.stop(); store.history.stop() }
            for edge in [PanelEdge.left, .right] {
                store.preferences.edge = edge
                for height in [CGFloat(220), NotchMetrics.height(sessions: count, available: store.screen.visibleFrame.height)] {
                    let host = NSHostingView(rootView: RailView(store: store).preferredColorScheme(.dark))
                    let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: DesignTokens.railWidth, height: height),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    defer { window.close() }
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    host.layoutSubtreeIfNeeded()
                    let scroll = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
                    XCTAssertEqual(scroll.hasVerticalScroller, count == 12, "sessions=\(count), opening height=\(height)")
                    XCTAssertFalse(scroll.hasHorizontalScroller)
                    if count == 12 {
                        XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height)
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
                    }
                    if let directory = ProcessInfo.processInfo.environment["NC_NOTCH_LAYOUT_PREVIEWS"], height > 220 {
                        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("notch-\(edge)-\(count).png"))
                    }
                }
            }
        }
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    func testNativeHandleAcceptsFirstMouseAndKeyboardActivation() {
        let view = RailDragHandleView()
        var activations = 0
        view.onClick = { activations += 1 }
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        XCTAssertTrue(view.acceptsFirstResponder)
        XCTAssertEqual(view.focusRingType, .none)
        view.allowsFocus = false
        XCTAssertFalse(view.acceptsFirstResponder)
        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertEqual(activations, 1)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                  context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        view.keyDown(with: key)
        XCTAssertEqual(activations, 2)
        view.horizontalResize = true
        var adjustment = 0
        view.onAdjust = { adjustment += $0 }
        XCTAssertTrue(view.accessibilityPerformIncrement())
        XCTAssertEqual(adjustment, 1)
        XCTAssertTrue(view.accessibilityPerformDecrement())
        XCTAssertEqual(adjustment, 0)
        XCTAssertFalse(view.accessibilityPerformPress())
    }

    @MainActor
    func testContextActionOpensSettingsWithoutAVisibleControl() {
        let view = RailDragHandleView()
        var opened = 0
        view.onContext = { opened += 1 }
        view.contextTitle = "Settings"
        view.performContext()
        XCTAssertEqual(opened, 1)
        view.setAccessibilityElement(false)
        XCTAssertFalse(view.isAccessibilityElement())
    }

    @MainActor
    func testReportClosePreservesPresentationWhileDisablingTerminalInput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(project: folder)
        store.choose("report")
        XCTAssertTrue(store.panelOpen)
        store.close()
        XCTAssertFalse(store.panelOpen)
        XCTAssertEqual(store.presentedContent, "report")
        XCTAssertFalse(store.gateway.canSend)
        store.work.stop(); store.history.stop()
    }

    @MainActor
    func testAFinishedTurnLeavesOpensOrKeepsOpenTheFoldedNotchAsConfigured() throws {
        for (action, showsPin) in AlertNotchAction.allCases.flatMap({ action in [true, false].map { (action, $0) } }) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let state = folder.appendingPathComponent(".notchcontrol")
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let candidate = AgentCandidate(terminal: .init(id: "one", generation: "test"), provider: .claude, project: "/project", name: "Claude")
            var registry = AgentRegistry()
            registry.reconcile([candidate])
            try JSONEncoder().encode(registry).write(to: state.appendingPathComponent("sessions.json"))
            var preferences = AppPreferences()
            preferences.alwaysVisible = false
            preferences.showsPin = showsPin
            preferences.notchVisibility = .alwaysFolded
            preferences.completed.notchAction = action
            preferences.completed.sound = false
            preferences.completed.notification = false
            try JSONEncoder().encode(preferences).write(to: state.appendingPathComponent("preferences.json"))
            let store = AppStore(project: folder)
            defer { store.work.stop(); store.history.stop() }
            store.gateway.onEvidence?(AgentEvidence(terminal: candidate.terminal, provider: .claude, conversation: nil,
                sequence: 1, kind: .working, associationProven: true), true)
            XCTAssertFalse(store.railExpanded, "\(action), pin shown \(showsPin): unpinned, always folded and not hovered")
            store.gateway.onEvidence?(AgentEvidence(terminal: candidate.terminal, provider: .claude, conversation: nil,
                sequence: 2, kind: .completed, reason: "result", associationProven: true), false)
            XCTAssertEqual(store.railExpanded, action != .nothing, "\(action), pin shown \(showsPin)")
            XCTAssertEqual(store.preferences.alwaysVisible, action == .pin && showsPin, "\(action), pin shown \(showsPin): without the pin it only opens")
            XCTAssertEqual(store.preferences.notchVisibility, .alwaysFolded, "\(action): the visibility itself is left alone")
        }
    }

    @MainActor
    func testTheFoldedArrowSitsAtTheCenterOfThePillOnBothEdges() throws {
        let scale: CGFloat = 8
        let width = DesignTokens.pillWidth, height = DesignTokens.pillHeight
        for edge in [PanelEdge.right, .left] {
            let renderer = ImageRenderer(content: FoldedPill(edge: edge, cue: DesignTokens.notchInk)
                .frame(width: width, height: height).background(Color(red: 1, green: 0, blue: 1)))
            renderer.scale = scale
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.greenComponent ?? 0) > 0.5 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            XCTAssertGreaterThan(maxX, minX, "\(edge): the arrow is drawn")
            let drawn = CGSize(width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
            XCTAssertEqual(drawn.width, PillArrow.width, accuracy: 0.5, "\(edge)")
            XCTAssertEqual(drawn.height, PillArrow.height, accuracy: 0.5, "\(edge)")
            XCTAssertEqual(CGFloat(minX + maxX + 1) / 2 / scale, width / 2, accuracy: 0.25, "\(edge): horizontally centered")
            XCTAssertEqual(CGFloat(minY + maxY + 1) / 2 / scale, height / 2, accuracy: 0.25, "\(edge): vertically centered")
        }
    }

    @MainActor
    func testTheNotchOnlyKeepsTheSpaceOfThePinWhileThePinIsShown() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(project: folder)
        defer { store.work.stop(); store.history.stop() }
        XCTAssertTrue(store.preferences.showsPin)
        XCTAssertEqual(NotchMetrics.topPadding(pin: true), DesignTokens.topPadding)
        XCTAssertEqual(NotchMetrics.topPadding(pin: false), DesignTokens.regular)
        for sessions in [0, 1, 4] {
            let shown = NotchMetrics.contentHeight(sessions: sessions)
            let hidden = NotchMetrics.contentHeight(sessions: sessions, pin: false)
            XCTAssertEqual(shown - hidden, DesignTokens.topPadding - DesignTokens.regular, "\(sessions) sessions")
            XCTAssertEqual(NotchMetrics.height(sessions: sessions, available: 2000, pin: false), hidden)
        }
        XCTAssertFalse(NotchMetrics.needsScrolling(sessions: 10, available: NotchMetrics.contentHeight(sessions: 10, pin: false), pin: false))
        XCTAssertTrue(NotchMetrics.needsScrolling(sessions: 10, available: NotchMetrics.contentHeight(sessions: 10, pin: false), pin: true),
                      "The pin's space no longer fits where the hidden pin's notch did")

        let withPin = store.railHeight(available: 2000)
        store.preferences.showsPin = false
        XCTAssertEqual(withPin - store.railHeight(available: 2000), DesignTokens.topPadding - DesignTokens.regular)
        store.preferences.showsPin = true
        XCTAssertEqual(store.railHeight(available: 2000), withPin, "Showing the pin again gives its space back")
    }

    @MainActor
    func testThePinOverridesTheVisibilityWhichFollowsTheSessionsWhenUnpinned() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = folder.appendingPathComponent(".notchcontrol")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = AgentCandidate(terminal: .init(id: "one", generation: "test"), provider: .claude, project: "/project", name: "Claude")
        let second = AgentCandidate(terminal: .init(id: "two", generation: "test"), provider: .codex, project: "/project", name: "Codex")
        var registry = AgentRegistry()
        registry.reconcile([first, second])
        try JSONEncoder().encode(registry).write(to: state.appendingPathComponent("sessions.json"))
        let store = AppStore(project: folder)
        defer { store.work.stop(); store.history.stop() }
        var sequence: UInt64 = 0
        func report(_ candidate: AgentCandidate, _ kind: AgentEventKind, reason: String? = nil) {
            sequence += 1
            store.gateway.onEvidence?(AgentEvidence(terminal: candidate.terminal, provider: candidate.provider, conversation: nil,
                sequence: sequence, kind: kind, reason: reason, associationProven: true), true)
        }

        XCTAssertTrue(store.preferences.alwaysVisible, "New installs start pinned")
        XCTAssertEqual(store.preferences.notchVisibility, .automatic)
        XCTAssertTrue(store.railExpanded, "Pinned, with nothing to show")
        store.togglePin()
        XCTAssertFalse(store.railExpanded, "Unpinned and automatic: nothing recognized yet, so nothing needs the notch")
        report(first, .working)
        XCTAssertTrue(store.railExpanded, "Working")
        report(second, .waiting)
        report(first, .completed)
        XCTAssertTrue(store.railExpanded, "A decision is still pending")
        report(second, .completed, reason: "result")
        XCTAssertTrue(store.railExpanded, "Finished, but the result was not seen yet")
        store.markSeen(second.key)
        XCTAssertFalse(store.railExpanded, "Every session idle")
        report(first, .working)
        XCTAssertTrue(store.railExpanded)
        report(first, .interrupted)
        XCTAssertFalse(store.railExpanded)

        report(first, .working)
        store.setHover(true)
        report(first, .interrupted)
        XCTAssertTrue(store.railExpanded, "The pointer holds it open until it leaves")
        store.expandedRail = false

        store.setNotchVisibility(.alwaysFolded)
        report(first, .working)
        report(second, .waiting)
        XCTAssertFalse(store.railExpanded, "Always folded, even with work and a pending decision")
        store.setNotchVisibility(.alwaysOpen)
        report(first, .interrupted)
        report(second, .interrupted)
        XCTAssertTrue(store.railExpanded, "Always open, even with every session idle")

        store.setNotchVisibility(.alwaysFolded)
        XCTAssertFalse(store.railExpanded)
        store.togglePin()
        XCTAssertTrue(store.railExpanded, "The pin wins over always folded")
        store.setNotchVisibility(.automatic)
        XCTAssertTrue(store.railExpanded, "The pin wins over automatic with every session idle")
        let saved = AppPreferences.load(try Data(contentsOf: state.appendingPathComponent("preferences.json")))
        XCTAssertTrue(saved.alwaysVisible)
        XCTAssertEqual(saved.notchVisibility, .automatic)

        store.preferences.showsPin = false
        store.persistPreferences()
        XCTAssertTrue(store.preferences.alwaysVisible, "Hiding the pin keeps its state")
        XCTAssertFalse(store.railExpanded, "Without the pin on the notch only the visibility applies: automatic with every session idle")
        report(first, .working)
        XCTAssertTrue(store.railExpanded)
        store.preferences.showsPin = true
        store.persistPreferences()
        report(first, .interrupted)
        XCTAssertTrue(store.railExpanded, "Showing the pin again brings back its hold")
    }

    @MainActor
    func testNotchCanRenderProviderStatesOffscreen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = folder.appendingPathComponent(".notchcontrol")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        var registry = AgentRegistry()
        let candidates = [
            AgentCandidate(terminal: .init(id: "one", generation: "test"), provider: .claude, project: "/project", name: "Claude"),
            AgentCandidate(terminal: .init(id: "two", generation: "test"), provider: .codex, project: "/project", name: "Codex"),
            AgentCandidate(terminal: .init(id: "three", generation: "test"), provider: .claude, project: "/project", name: "Claude")
        ]
        registry.reconcile(candidates)
        try JSONEncoder().encode(registry).write(to: state.appendingPathComponent("sessions.json"))
        let store = AppStore(project: folder)
        for (candidate, kind) in zip(candidates, [AgentEventKind.working, .completed, .waiting]) {
            store.gateway.onEvidence?(AgentEvidence(terminal: candidate.terminal, provider: candidate.provider, conversation: nil,
                sequence: 1, kind: kind, associationProven: true), true)
        }
        XCTAssertEqual(store.registry.sessions.map(\.state), [.working, .idle, .waiting])
        XCTAssertFalse(store.expandedRail)
        XCTAssertFalse(store.panelOpen)
        XCTAssertTrue(store.railExpanded, "New installs start pinned")
        XCTAssertEqual(store.registry.attention, .waiting, "The pill arrow shows the pending decision")
        store.togglePin()
        XCTAssertTrue(store.railExpanded, "Unpinned and automatic, the pending decision keeps the notch open")
        store.setNotchVisibility(.alwaysFolded)
        XCTAssertFalse(store.railExpanded, "Always folded, work or a pending decision no longer holds the notch open")
        store.setNotchVisibility(.automatic)
        store.togglePin()
        let height = NotchMetrics.height(sessions: candidates.count, available: 900)
        let renderer = ImageRenderer(content: RailView(store: store).frame(width: DesignTokens.railWidth, height: height)
            .environment(\.notchPreview, true).preferredColorScheme(.dark).background(Color.gray))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 140)
        XCTAssertEqual(image.height, Int(height * 2))
        let bitmap = NSBitmapImageRep(cgImage: image)
        var workingPixels = 0, waitingPixels = 0, unsupportedPixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.greenComponent > 0.8 && color.redComponent < 0.2 { workingPixels += 1 }
                if color.redComponent > 0.8 && color.greenComponent < 0.6 && color.blueComponent < 0.6 { waitingPixels += 1 }
                if color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent < 0.1 { unsupportedPixels += 1 }
            }
        }
        XCTAssertGreaterThan(workingPixels, 10)
        XCTAssertGreaterThan(waitingPixels, 10)
        XCTAssertEqual(unsupportedPixels, 0)
        let output = ProcessInfo.processInfo.environment["NOTCHCONTROL_PREVIEW_PATH"]
        if let output {
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output))
        }
        for candidate in candidates {
            store.gateway.onEvidence?(AgentEvidence(terminal: candidate.terminal, provider: candidate.provider, conversation: nil,
                sequence: 2, kind: .completed, associationProven: true), false)
        }
        XCTAssertEqual(store.registry.sessions.map(\.state), [.idle, .idle, .idle])
        XCTAssertNil(store.registry.attention)
        store.gateway.onEvidence?(AgentEvidence(terminal: candidates[0].terminal, provider: .claude, conversation: nil,
            sequence: 3, kind: .completed, reason: "result", associationProven: true), false)
        XCTAssertTrue(store.registry.sessions[0].unseenResult)
        XCTAssertEqual(store.registry.sessions[0].state, .idle)
        XCTAssertEqual(store.registry.attention, .working, "An unseen result lights the pill arrow green")
        store.markSeen(store.registry.sessions[0].id)
        XCTAssertFalse(store.registry.sessions[0].unseenResult)
        XCTAssertNil(store.registry.attention)
        store.work.stop(); store.history.stop()
    }
}
