import XCTest
@testable import NotchControlCore

final class WorkBoardTests: XCTestCase {
    private let newest = "00000000-0000-0000-0000-00000000000a"
    private let older = "00000000-0000-0000-0000-00000000000b"
    private let other = "00000000-0000-0000-0000-00000000000c"
    private var markdown: String {
        """
        # Work

        ## 2026-09-30 18:40 — #123 Paywall novo
        - Início: 2026-09-25 10:12
        - Sessões:
          - 2026-09-30 · gpt-6-sol
            cd '/Users/test/My Lib' && codex resume \(newest)
          - 2026-09-25 · Opus 5.5
            `cd /Users/test/app && claude -r \(older.uppercased())`
        - Status: Lib pronta no PR #45; falta integrar no app.

        ## 2026-09-29 10:00 — Revisar PR do time
        - Início: 2026-09-29 10:00
        - Status:

        ## 2026-09-28 — Revisar PR do time
        - Sessões:
          - 2026-09-28 · Opus 5.5
            cd /Users/test/other && claude -r \(other)
        """
    }

    func testEntriesFollowTheFileWithTitlesWithoutDatesAndSessionsNewestFirst() {
        let entries = ReportDocument(markdown: markdown).entries
        XCTAssertEqual(entries.map(\.title), ["#123 Paywall novo", "Revisar PR do time", "Revisar PR do time"])
        XCTAssertEqual(entries.map(\.id), ["work:#123 Paywall novo", "work:Revisar PR do time", "work:Revisar PR do time#2"])
        XCTAssertEqual(entries[0].status, "Lib pronta no PR #45; falta integrar no app.")
        XCTAssertNil(entries[1].status)
        XCTAssertEqual(entries[0].sessions.map(\.provider), [.codex, .claude])
        XCTAssertEqual(entries[0].sessions.map(\.conversation), [newest, older])
        XCTAssertEqual(entries[0].sessions.first?.directory, "/Users/test/My Lib")
        XCTAssertEqual(entries[1].sessions, [])
        XCTAssertEqual(ReportDocument(markdown: "# Work\ncd /tmp && claude -r \(newest)").entries, [])
    }

    func testOpenEntriesShowTheirNewestOpenSessionAndClosedOnesResumeTheNewest() throws {
        let entries = ReportDocument(markdown: markdown).entries
        var registry = AgentRegistry()
        registry.reconcile([session("a", .claude, older), session("b", .claude, other), session("c", .codex, nil)])
        let board = WorkBoard(entries: entries, sessions: registry.sessions)
        // The newest (Codex) is closed, so the older open Claude session represents the entry.
        XCTAssertEqual(board.items[0].mark, .open("claude:a:1"))
        XCTAssertEqual(board.items[1].mark, .note)
        XCTAssertEqual(board.items[2].mark, .open("claude:b:1"))
        XCTAssertEqual(board.unlisted, ["codex:c:1"])

        registry.reconcile([session("b", .claude, other)])
        let closed = WorkBoard(entries: entries, sessions: registry.sessions)
        XCTAssertEqual(closed.items[0].mark, .closed(try XCTUnwrap(ResumeRequest(provider: .codex, conversation: newest, directory: "/Users/test/My Lib"))))
        XCTAssertEqual(closed.unlisted, [])
    }

    func testOnlyTheSameProviderAndConversationMatchAndExtraOpenCopiesStayVisible() {
        let entries = ReportDocument(markdown: markdown).entries
        var registry = AgentRegistry()
        registry.reconcile([session("a", .codex, older), session("b", .claude, other), session("d", .claude, other)])
        let board = WorkBoard(entries: entries, sessions: registry.sessions)
        if case .closed = board.items[0].mark {} else { XCTFail("A Codex terminal must not answer for a Claude conversation") }
        XCTAssertEqual(board.items[2].mark, .open("claude:b:1"))
        XCTAssertEqual(board.unlisted, ["codex:a:1", "claude:d:1"])
    }

    func testInventoryConversationReplacesTheStoredOneButAMissingOneKeepsTheHookProof() {
        var registry = AgentRegistry()
        let terminal = TerminalIdentity(id: "a", generation: "1")
        registry.reconcile([session("a", .claude, nil)])
        registry.apply(.init(terminal: terminal, provider: .claude, conversation: older, sequence: 1, kind: .working, associationProven: true))
        registry.reconcile([session("a", .claude, nil)])
        XCTAssertEqual(registry.sessions.first?.conversation, older)
        registry.reconcile([session("a", .claude, newest.uppercased())])
        XCTAssertEqual(registry.sessions.first?.conversation, newest)
    }

    func testPreferencesSavedBeforeTheWorkModeStillLoad() throws {
        var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any] ?? [:]
        saved["workMode"] = nil
        saved["edge"] = "left"
        saved["panelWidth"] = 777
        let loaded = AppPreferences.load(try JSONSerialization.data(withJSONObject: saved))
        XCTAssertEqual(loaded.edge, .left)
        XCTAssertEqual(loaded.panelWidth, 777)
        XCTAssertFalse(loaded.showsWorkEntries)
        var enabled = loaded
        enabled.showsWorkEntries = true
        XCTAssertTrue(AppPreferences.load(try JSONEncoder().encode(enabled)).showsWorkEntries)
    }

    private func session(_ id: String, _ provider: AgentProvider, _ conversation: String?) -> AgentCandidate {
        AgentCandidate(terminal: .init(id: id, generation: "1"), provider: provider, project: "/project", name: id, conversation: conversation)
    }
}
