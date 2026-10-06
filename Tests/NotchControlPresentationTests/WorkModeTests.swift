import AppKit
import NotchControlCore
import SwiftUI
import XCTest
@testable import NotchControl
@testable import NotchControlUI

final class WorkModeTests: XCTestCase {
    private let open = "00000000-0000-0000-0000-0000000000a1"
    private let closed = "00000000-0000-0000-0000-0000000000b2"

    @MainActor
    func testWorkEntriesAreGroupedByOpenTerminalWithUnlistedSessionsInBetween() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = folder.appendingPathComponent(".notchcontrol")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = folder.appendingPathComponent("work.md")
        try """
        # Work

        ## 2026-10-06 08:00 — Fechada
        - Sessões:
          - 2026-10-06 · Opus 5.5
            cd '/Users/test/closed project' && claude -r \(closed)
        - Status: Lib pronta no PR #45; falta integrar no app e validar no aparelho, depois abrir o PR e esperar a revisão do time.

        ## 2026-10-05 18:00 — Aberta
        - Sessões:
          - 2026-10-05 · Opus 5.5
            cd /Users/test/open && claude -r \(open)
        - Status: Rodando no terminal.

        ## 2026-10-04 12:00 — Revisar PR do time
        - Status: aguardando o autor.
        """.write(to: work, atomically: true, encoding: .utf8)
        var registry = AgentRegistry()
        registry.reconcile([
            AgentCandidate(terminal: .init(id: "claude-tab", generation: "1"), provider: .claude, project: "/Users/test/open", name: "Claude", conversation: open),
            AgentCandidate(terminal: .init(id: "codex-tab", generation: "1"), provider: .codex, project: "/Users/test/other", name: "Codex")
        ])
        try JSONEncoder().encode(registry).write(to: state.appendingPathComponent("sessions.json"))
        var preferences = AppPreferences()
        preferences.workPath = work.path
        preferences.showsWorkEntries = true
        try JSONEncoder().encode(preferences).write(to: state.appendingPathComponent("preferences.json"))

        let store = AppStore(project: folder)
        defer { store.work.stop(); store.history.stop() }
        let deadline = Date().addingTimeInterval(5)
        while store.work.document.entries.count < 3, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }

        let rows = store.railRows
        XCTAssertEqual(rows.map(\.id), ["work:Aberta", "divider:1", "codex:codex-tab:1", "divider:2", "work:Fechada", "work:Revisar PR do time"])
        guard case .entry(let openItem, let openSession) = rows[0], case .entry(let closedItem, .none) = rows[4],
              case .entry(let noteItem, .none) = rows[5] else { return XCTFail("Unexpected rows \(rows.map(\.id))") }
        XCTAssertEqual(openSession?.id, "claude:claude-tab:1")
        XCTAssertEqual(closedItem.mark, .closed(try XCTUnwrap(ResumeRequest(provider: .claude, conversation: closed, directory: "/Users/test/closed project"))))
        XCTAssertEqual(noteItem.mark, .note)
        XCTAssertEqual(store.railCounts.cells, 4)
        XCTAssertEqual(store.railCounts.dividers, 2)
        XCTAssertEqual(store.railHeight(available: 2000), NotchMetrics.contentHeight(sessions: 4, dividers: 2))

        for language in [InterfaceLanguage.portuguese, .english] {
            for (name, session, item) in [("open", openSession, openItem), ("closed", nil, closedItem), ("note", nil, noteItem)] {
                let content = SessionDetails(session: session, item: item, windows: [], messages: Messages(language: language))
                let host = NSHostingView(rootView: content)
                XCTAssertEqual(host.fittingSize.width, DesignTokens.tooltipWidth, accuracy: 1, name)
                XCTAssertGreaterThan(host.fittingSize.height, 100, name)
                XCTAssertLessThan(host.fittingSize.height, 320, name)
                try render(content.background(Color(red: 0.12, green: 0.14, blue: 0.18)), "work-tooltip-\(language.rawValue)-\(name)")
            }
        }
        if !NSScreen.screens.isEmpty {
            try render(RailView(store: store).environment(\.notchPreview, true).frame(width: DesignTokens.railWidth, height: store.railHeight(available: 2000))
                .background(Color(red: 0.5, green: 0.5, blue: 0.5)), "work-rail")
        }

        store.choose(closedItem)
        XCTAssertEqual(store.noticeKey, "connection_unavailable")
        store.choose(noteItem)
        XCTAssertEqual(store.content, "report")

        XCTAssertEqual(NotchMetrics.height(sessions: 10, available: 2000), NotchMetrics.contentHeight(sessions: 10))
        XCTAssertTrue(NotchMetrics.needsScrolling(sessions: 11, available: 2000))

        store.preferences.showsWorkEntries = false
        XCTAssertEqual(store.railRows.map(\.id), ["claude:claude-tab:1", "codex:codex-tab:1"])
    }

    /// Writes a PNG to `NC_RENDER_DIR` for visual review; otherwise only checks that the view renders.
    @MainActor
    private func render(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, name)
        guard let folder = ProcessInfo.processInfo.environment["NC_RENDER_DIR"] else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }
}
