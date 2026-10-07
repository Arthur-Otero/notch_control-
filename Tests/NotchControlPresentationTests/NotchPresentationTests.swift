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
        XCTAssertFalse(store.railExpanded, "Unpinned, work or a pending decision no longer holds the notch open")
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
