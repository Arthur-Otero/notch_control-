import AppKit
import NotchControlCore
import SwiftUI
import XCTest
@testable import NotchControl
@testable import NotchControlUI

/// A digitação vai para o espelho do terminal, que é onde cada CLI desenha as próprias sugestões.
final class SessionPanelTests: XCTestCase {
    @MainActor
    func testSlashAndArrowsAreSentToTheTerminalSoTheCLICanDrawItsOwnSuggestions() {
        let canvas = TerminalCanvas(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        canvas.inputEnabled = true
        var sent = ""
        canvas.send = { sent += $0 }
        func press(_ code: UInt16, _ characters: String) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
            canvas.keyDown(with: event)
        }
        press(44, "/")
        press(126, "")
        press(36, "\r")
        XCTAssertEqual(sent, "/\u{1b}[A\r")
    }

    @MainActor
    func testTypingFocusWaitsForTheKeyWindowInsteadOfBeingDropped() {
        let canvas = TerminalCanvas(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        canvas.inputEnabled = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        canvas.requestTypingFocus()
        guard !window.isKeyWindow else {
            XCTAssertFalse(canvas.waitingToType)
            XCTAssertTrue(window.firstResponder === canvas)
            return
        }
        XCTAssertTrue(canvas.waitingToType)
        XCTAssertFalse(window.firstResponder === canvas)
    }

    // MARK: Apresentação

    @MainActor
    func testPanelRendersSessionAsTerminalExtensionAndWritesPreviewWhenAsked() throws {
        let directory = ProcessInfo.processInfo.environment["NC_RENDER_DIR"]
        for (provider, state, name) in [(AgentProvider.claude, AgentEventKind.working, "working"),
                                        (.codex, .waiting, "waiting"), (.cursor, .completed, "idle")] {
            let store = try makeStore(provider: provider)
            let session = try XCTUnwrap(store.registry.sessions.first)
            store.gateway.onEvidence?(AgentEvidence(terminal: session.terminal, provider: provider, conversation: nil, sequence: 1,
                                                    kind: state, reason: state == .waiting ? "approval" : nil, associationProven: true), false)
            store.content = session.id
            let image = try render(PanelContent(store: store), size: NSSize(width: 640, height: 820))
            let bitmap = NSBitmapImageRep(cgImage: image)
            if let directory {
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("panel-\(provider.rawValue)-\(name).png"))
            }
            // O cartão do terminal usa o fundo do perfil (azul-escuro) e o painel, preto: as duas áreas precisam existir.
            XCTAssertGreaterThan(share(bitmap) { $0.blueComponent > 0.14 && $0.blueComponent < 0.3 && $0.redComponent < 0.12 }, 0.3)
            XCTAssertGreaterThan(share(bitmap) { $0.redComponent < 0.01 && $0.greenComponent < 0.01 && $0.blueComponent < 0.01 }, 0.02)
            if state == .waiting { XCTAssertGreaterThan(share(bitmap) { $0.redComponent > 0.8 && $0.greenComponent < 0.6 && $0.blueComponent < 0.65 }, 0.00005) }
            if state == .working { XCTAssertGreaterThan(share(bitmap) { $0.greenComponent > 0.6 && $0.greenComponent - $0.redComponent > 0.4 && $0.greenComponent - $0.blueComponent > 0.1 }, 0.00005) }
            store.work.stop(); store.history.stop()
        }
    }

    // MARK: Apoio

    @MainActor
    private func makeStore(provider: AgentProvider) throws -> AppStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let identity = TerminalIdentity(id: "T-\(provider.rawValue)", generation: "created:1:/dev/ttys001")
        var registry = AgentRegistry()
        registry.reconcile([AgentCandidate(terminal: identity, provider: provider, project: "/Users/me/notch_control",
                                           name: "Design e funcionalidade (\(provider.rawValue))")])
        let state = folder.appendingPathComponent(".notchcontrol")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try JSONEncoder().encode(registry).write(to: state.appendingPathComponent("sessions.json"))
        let store = AppStore(project: folder)
        let terminal = try JSONDecoder().decode(TerminalDescriptor.self, from: Data("""
        {"identity":{"id":"\(identity.id)","generation":"\(identity.generation)"},"name":"x","provider":"\(provider.rawValue)",
         "project":"/Users/me/notch_control","columns":96,"rows":30,"singlePane":true,"local":true,"identityConfirmed":true,"fullscreen":false}
        """.utf8))
        store.gateway.installFixture(terminal: terminal, snapshot: try snapshot(identity), history: [])
        return store
    }

    private func snapshot(_ identity: TerminalIdentity) throws -> TerminalSnapshot {
        func color(_ ansi: Int) throws -> TerminalColor { try JSONDecoder().decode(TerminalColor.self, from: Data("{\"ansi\":\(ansi)}".utf8)) }
        func line(_ parts: [(String, Int?, Bool)]) throws -> TerminalLine {
            TerminalLine(cells: try parts.flatMap { text, ansi, bold in
                try text.map { TerminalCell(text: String($0), foreground: try ansi.map(color), bold: bold) }
            }, hardEOL: true)
        }
        let palette = try JSONDecoder().decode(TerminalPalette.self, from: Data("""
        {"foreground":[220,224,232],"background":[22,26,38],"ansi":[[30,34,44],[255,107,115],[0,215,135],[255,200,87],[125,170,255],
        [200,140,255],[90,210,220],[200,204,212],[90,96,110],[255,107,115],[0,215,135],[255,200,87],[125,170,255],[200,140,255],[90,210,220],[255,255,255]]}
        """.utf8))
        let rows: [[(String, Int?, Bool)]] = [
            [("● ", 2, true), ("Reading ", nil, true), ("Sources/NotchControl/AppViews.swift", 8, false)],
            [],
            [("> ", 4, true), ("make the open panel a simple terminal extension", nil, false)],
            [],
            [("✻ ", 3, false), ("I'll start by reading how the panel renders the terminal mirror.", nil, false)],
            [],
            [("  ⎿ ", 8, false), ("Read 298 lines", 8, false)],
            [("● ", 2, true), ("Update(", nil, true), ("Sources/NotchControl/SessionPanel.swift", 6, false), (")", nil, true)],
            [("    + ", 2, false), ("struct SessionPanelBody: View {", 2, false)],
            [("    - ", 1, false), ("struct PanelContent: View {", 1, false)],
            [],
            [("Do you want to proceed?", nil, true)],
            [("❯ 1. Yes", 4, false)],
            [("  2. Yes, and don't ask again", nil, false)],
            [("  3. No, and tell the agent what to do differently", nil, false)]
        ]
        return TerminalSnapshot(connection: "c", terminal: identity, selection: 1, columns: 96, rows: 30,
                                cursor: .init(x: -1, y: -1), lines: try rows.map(line), palette: palette)
    }

    @MainActor
    private func render<Content: View>(_ content: Content, size: NSSize) throws -> CGImage {
        let hosting = NSHostingView(rootView: content.preferredColorScheme(.dark).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        }
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        XCTAssertEqual(bitmap.pixelsWide, Int(size.width * window.backingScaleFactor))
        XCTAssertEqual(bitmap.pixelsHigh, Int(size.height * window.backingScaleFactor))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.cgImage)
    }

    private func share(_ bitmap: NSBitmapImageRep, where match: (NSColor) -> Bool) -> Double {
        var hits = 0, total = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                total += 1
                if match(color) { hits += 1 }
            }
        }
        return Double(hits) / Double(max(1, total))
    }
}
